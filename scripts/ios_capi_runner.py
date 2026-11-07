"""The decisions of `scripts/test_ios.sh --capi`: the checks of the C ABI that run on one simulator.

C ABI design part 1, C-6 and 6.1 (P1-20), part 2, TB-12 and 12.1 to 12.4: IosLibraryCApiTests in three
variants (no sanitizer, ASan, TSan), a build of the distributable outside dist/, check_ios_dist.py, the
contract check with --library on each slice of that build, --require-compile and --require-complete, and
the smoke. test_ios.sh runs xcodebuild and the scripts; this file reads what they left and says whether
each step passed, and the summary says whether the run did.

--capi never reaches the device: it refuses one before anything is built (test_ios.sh). The device has its
own option, --capi-device (stage 2 working notes, 17: the checkpoint before 2.0.0; part 1, 6 P1-20; part 2,
15.2): IosLibraryCApiTests with ASan on the device and the smoke installed and launched there. It runs only
with an approval list that --dry-run wrote and the user approved, once, as the sample's device runs do
(agent-rules/device-testing.md; UI test design U-9 and 6.3). The device-* commands below make and check
that list and judge what ran.

Commands:
  version       the library version of the tree's Common.h (NTK_VERSION_MAJOR.MINOR.PATCH)
  check-xcode   exit 2 unless `xcodebuild -version` is the Xcode the C ABI compiles with
  unit-record   one variant of IosLibraryCApiTests: its result bundle's summary, the sanitizer runtime
                each framework loads, and no sanitizer report in the logs
  step-record   one of the other steps: its exit status and its report
  summary       every step once, all passed, and the three variants ran the same number of tests
  device-plan   --capi-device: the plan of the device run; with --dry-run also the approval list to show
  device-approve
                the approval matches the plan, the runner and the tree; its ID is consumed in the ledger
  device-gate   before each call that reaches the device or signs: the approved plan, the consumed ID, the
                runner and the tree unchanged
  device-team   the signing team the C ABI's own project uses (never written to a file); --check only checks
  device-identity
                the device that --devicectl-id names (devicectl device info details) is the plan's --udid
  last-status   the status of the last record of a results file (PASS or FAIL)
  device-unit-record, device-step-record, device-summary
                what ran on the device, as unit-record, step-record and summary do for the simulator

Python 3.9 (/usr/bin/python3) runs it.
"""

import argparse
import datetime
import json
import pathlib
import re
import secrets
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ios_ui_runner as ui  # noqa: E402
from ios_ui_runner import CAPI_UI_XCODE  # noqa: E402

VARIANTS = ("normal", "asan", "tsan")
# The xcodebuild option that turns each variant on (test_ios.sh passes it; the record checks its effect).
VARIANT_OPTION = {"normal": None, "asan": "-enableAddressSanitizer", "tsan": "-enableThreadSanitizer"}
# The runtime a framework built with the variant loads (otool -L).
SANITIZER_RUNTIME = {"asan": "libclang_rt.asan_iossim_dynamic.dylib", "tsan": "libclang_rt.tsan_iossim_dynamic.dylib"}
ANY_SANITIZER_RUNTIME = re.compile(r"libclang_rt\.\w*san\w*\.dylib")
# The frameworks whose code the sanitizers must measure (part 1, 6.1: both are built from source).
FRAMEWORKS = ("IosLibraryCApi", "IosLibrary")
# What a sanitizer prints when it reports (compiler-rt's own forms), and UBSan's runtime error: an error or
# a warning, its summary, a deadly signal, a failed internal check, a fatal stop, and TSan's count at exit
# when it is not zero.
_SANITIZER = r"(?:Address|Thread|UndefinedBehavior|Leak)Sanitizer"
SANITIZER_REPORT = re.compile(
    r"(?:ERROR|WARNING): " + _SANITIZER
    + r"|SUMMARY: " + _SANITIZER
    + r"|" + _SANITIZER + r":DEADLYSIGNAL"
    + r"|" + _SANITIZER + r": CHECK failed:"
    + r"|FATAL: " + _SANITIZER
    + r"|FATAL: Memory layout is incompatible with TSan"
    + r"|ThreadSanitizer: reported [1-9]\d* warnings?"
    + r"|==\d+==ERROR:"
    + r"|: runtime error: ")
# The slices of README 7.3 and the architectures each must have.
SLICES = (("ios-arm64", "arm64"), ("ios-arm64_x86_64-simulator", "arm64,x86_64"))
STEPS = (("unit-normal", "unit-asan", "unit-tsan", "dist-build", "dist-check")
         + tuple(f"contract-{slice_name}" for slice_name, _ in SLICES) + ("smoke",))


class RunnerError(Exception):
    pass


def library_version(common_h):
    parts = []
    for name in ("MAJOR", "MINOR", "PATCH"):
        found = re.findall(r"^#define NTK_VERSION_%s (\d+)\s*$" % name, common_h, flags=re.M)
        if len(found) != 1:
            raise RunnerError(f"Common.h defines NTK_VERSION_{name} {len(found)} times")
        parts.append(str(int(found[0])))
    return ".".join(parts)


def xcode_problem(xcode, option="--capi"):
    """`xcode` is `xcodebuild -version` on one line. None for the Xcode the C ABI compiles with."""
    if re.match(r"Xcode " + re.escape(CAPI_UI_XCODE) + r"(\.\d+)? ", xcode + " "):
        return None
    where = "<device>" if option == "--capi-device" else "<simulator>"
    return (f"{option} needs Xcode {CAPI_UI_XCODE}, not '{xcode}'. Run it as "
            f"DEVELOPER_DIR=/Applications/Xcode{CAPI_UI_XCODE}.app/Contents/Developer scripts/test_ios.sh --udid {where} {option}")


def sanitizer_reports(text):
    """The lines of a log that are a sanitizer's report."""
    return [line.strip() for line in text.splitlines() if SANITIZER_REPORT.search(line)]


def runtime_problems(variant, otool_by_framework, runtimes=None):
    """What the frameworks load against what the variant needs: the variant's runtime and no other."""
    problems = []
    wanted = (SANITIZER_RUNTIME if runtimes is None else runtimes).get(variant)
    for framework in FRAMEWORKS:
        text = otool_by_framework.get(framework)
        if text is None:
            problems.append(f"{framework}: no otool -L of the built framework")
            continue
        loaded = sorted(set(ANY_SANITIZER_RUNTIME.findall(text)))
        expected = [wanted] if wanted else []
        if loaded != expected:
            problems.append(f"{framework} loads {loaded or 'no sanitizer runtime'}, expected {expected or 'none'}")
    return problems


def summary_problems(summary):
    """The result bundle's summary (xcresulttool get test-results summary): every test passed, none
    skipped, none expected to fail, and at least one ran."""
    problems = []
    total = summary.get("totalTestCount")
    if not isinstance(total, int) or total <= 0:
        return [f"totalTestCount is {total!r}"], 0
    for key, want in (("passedTests", total), ("failedTests", 0), ("skippedTests", 0), ("expectedFailures", 0)):
        value = summary.get(key, 0 if key in ("skippedTests", "expectedFailures") else None)
        if value != want:
            problems.append(f"{key} is {value!r}, expected {want}")
    if summary.get("result") != "Passed":
        problems.append(f"result is {summary.get('result')!r}")
    return problems, total


def _read_optional(path):
    p = pathlib.Path(path) if path else None
    return p.read_text(encoding="utf-8", errors="replace") if p and p.is_file() else None


def _append(results, record):
    with open(results, "a", encoding="utf-8") as f:
        f.write(json.dumps(record, sort_keys=True) + "\n")
    print(f"  {record['status']} {record['step']}" + (f": {record['detail']}" if record.get("detail") else ""))


def unit_record(variant, exit_code, timed_out, summary_json, logs, otool_files, device=False, expected=None,
                tests_json=None):
    """One variant of IosLibraryCApiTests. On the device, also exactly the plan's expected tests, and a sanitizer's
    report is named by its kinds and counts only (its lines stay in the device's folder, which is removed)."""
    problems = []
    if timed_out:
        problems.append("xcodebuild was cut off by the time limit")
    elif exit_code != 0:
        problems.append(f"xcodebuild ended with status {exit_code}")
    summary_text = _read_optional(summary_json)
    total = 0
    if summary_text is None:
        problems.append("no summary of the result bundle")
    else:
        try:
            found, total = summary_problems(json.loads(summary_text))
            problems += found
        except ValueError as error:
            problems.append(f"the summary is not JSON ({error})")
    otool = {}
    for framework, path in otool_files:
        text = _read_optional(path)
        if text is not None:
            otool[framework] = text
    problems += runtime_problems(variant, otool, DEVICE_SANITIZER_RUNTIME if device else None)
    if device:
        tests_text = _read_optional(tests_json)
        if tests_text is None:
            problems.append("no list of the tests of the result bundle")
        else:
            problems += expected_tests_problems(expected or [], tests_text)
    for label, path in logs:
        text = _read_optional(path)
        if text is None:
            problems.append(f"no {label} to read for sanitizer reports")
            continue
        reports = sanitizer_reports(text)
        if reports and device:
            problems.append(f"{len(reports)} sanitizer report line(s) in the {label}: {report_kinds(reports)}")
        elif reports:
            problems.append(f"{len(reports)} sanitizer report line(s) in the {label}, first: {reports[0][:200]}")
    status = "FAIL" if problems else "PASS"
    detail = "; ".join(problems) if problems else f"{total} tests"
    return {"step": f"{'device-' if device else ''}unit-{variant}", "status": status, "detail": detail, "tests": total}


def report_problems(step, text):
    """What the report of a step must say beyond its exit status."""
    lines = text.splitlines()
    problems = []
    if step == "dist-check" or step.startswith("contract-"):
        title = "== iOS distribution" if step == "dist-check" else "== C ABI contract (iOS)"
        if not any(line.startswith(title) for line in lines):
            problems.append(f"no '{title}' report")
        failed = [line.strip() for line in lines if line.startswith("  FAIL ")]
        if failed:
            problems.append(f"{len(failed)} FAIL, first: {failed[0][:200]}")
        if not any(line.startswith("  OK ") for line in lines):
            problems.append("no OK line")
        # A check that did not run is not a pass, in either report (TB-12 review C-a).
        skipped = [line.strip() for line in lines if line.startswith("  SKIP ")]
        if skipped:
            problems.append(f"{len(skipped)} SKIP, first: {skipped[0][:200]}")
    if step.startswith("contract-"):
        if not any(re.match(r"  OK   symbols\b", line) for line in lines):
            problems.append("no OK symbols line (the library was not compared)")
    if step == "smoke":
        if not any(line.startswith("== iOS C ABI smoke") for line in lines):
            problems.append("no '== iOS C ABI smoke' report")
        failed = [line.strip() for line in lines if re.match(r"\s+FAIL ", line)]
        if failed:
            problems.append(f"{len(failed)} FAIL, first: {failed[0][:200]}")
        for needed in ("simulator build", "device build", "simulator run"):
            if not any(re.match(r"\s+PASS " + re.escape(needed) + r"\b", line) for line in lines):
                problems.append(f"no PASS {needed}")
    return problems


def step_record(step, exit_code, timed_out, log, not_run):
    if step not in STEPS or step.startswith("unit-"):
        raise RunnerError(f"unknown step {step}")
    if not_run:
        return {"step": step, "status": "FAIL", "detail": f"not run: {not_run}"}
    problems = []
    if timed_out:
        problems.append("cut off by the time limit")
    elif exit_code != 0:
        problems.append(f"ended with status {exit_code}")
    text = _read_optional(log)
    if text is None:
        problems.append("no log")
    else:
        problems += report_problems(step, text)
    detail = "; ".join(problems)
    if problems and log:
        detail += f" ({log})"
    return {"step": step, "status": "FAIL" if problems else "PASS", "detail": detail}


def summary(records):
    """Lines to print and whether the run passed."""
    problems = []
    by_step = {}
    for record in records:
        by_step.setdefault(record.get("step"), []).append(record)
    for step in by_step:
        if step not in STEPS:
            problems.append(f"{step}: not a step of --capi")
    for step in STEPS:
        found = by_step.get(step, [])
        if len(found) != 1:
            problems.append(f"{step}: recorded {len(found)} times, expected once")
    counts = {}
    for variant in VARIANTS:
        found = by_step.get(f"unit-{variant}", [])
        if len(found) == 1 and found[0].get("status") == "PASS":
            counts[variant] = found[0].get("tests")
    if len(counts) == len(VARIANTS) and len(set(counts.values())) != 1:
        problems.append(f"the variants ran different numbers of tests: {counts}")
    failed = [r["step"] for r in records if r.get("status") != "PASS"]
    lines = [f"  {r.get('status')} {r.get('step')}" + (f": {r['detail']}" if r.get("detail") else "") for r in records]
    lines += [f"  PROBLEM {p}" for p in problems]
    passed = sum(1 for r in records if r.get("status") == "PASS")
    lines.append(f"[summary] {passed} passed, {len(failed) + len(problems)} problem(s)")
    return lines, not failed and not problems


# --- The device: --capi-device (stage 2 working notes, 17.1 decision 4; part 1, 6 P1-20; part 2, 15.2) --------
#
# The same three guards as the sample's device runs (agent-rules/device-testing.md; UI test design U-9, 6.3):
# --dry-run writes the list of what will happen on the device and never reaches it; --approved checks that the
# list is exactly what this run would do, with the runner and the tree committed and unchanged, and consumes its
# ID in the same ledger (an approval runs once); every call that reaches the device or signs checks the approved
# plan again first (device-gate). What the steps do is fixed here, so the list says it in words.

DEVICE_KIND = "capi-device"
# The files the device run is made of: the approval names their hashes, and each must be committed.
DEVICE_RUNNER_FILES = ("scripts/test_ios.sh", "scripts/ios_capi_runner.py", "scripts/ios_ui_runner.py",
                       "scripts/run_ios_capi_smoke.sh", "scripts/build_ios_library_xcframework.sh")
# The runtime a framework built with ASan for the device loads (otool -L); the simulator's is *_iossim_*.
DEVICE_SANITIZER_RUNTIME = {"asan": "libclang_rt.asan_ios_dynamic.dylib"}
DEVICE_STEPS = ("device-unit-asan", "device-dist-build", "device-smoke-build", "device-smoke-install",
                "device-smoke-run")
# The signing of the existing device paths: Automatic, with the team the projects already carry, and
# -allowProvisioningUpdates (test_ios.sh's device build of the sample). The smoke's own project has no team,
# so its device build takes the team of the C ABI's project on the command line; it is never written to a file.
TEAM_PBXPROJ = "ios/IosLibraryCApi/IosLibraryCApi.xcodeproj/project.pbxproj"
_TEAM = re.compile(r"^\s*DEVELOPMENT_TEAM = \"?([^\";]*)\"?;\s*$", re.M)
_TEAM_VALUE = re.compile(r"^[A-Z0-9]{10}$")
SMOKE_BUNDLE_ID = "com.jonghyunkim.nativetoolkit.IosLibraryCApiSmoke"
DEVICE_ACTIONS = (
    {"step": "device-identity", "reachesDevice": True,
     "does": "xcrun devicectl device info details --device <the --devicectl-id> (reads only): the device it names "
             "must be the one given by --udid, or nothing else runs"},
    {"step": "device-unit-asan", "reachesDevice": True,
     "does": "xcodebuild test -scheme IosLibraryCApi -only-testing:IosLibraryCApiTests -enableAddressSanitizer YES "
             "on the device: builds and signs the Debug build (Automatic, -allowProvisioningUpdates), installs the "
             f"test host {ui.CAPI_TEST_HOST_BUNDLE_ID} (no window) and runs the tests in it. The tests use named "
             "pasteboards of their own and fakes for notifications and share; dialogs are cancelled before they "
             "start. The tests that run must be exactly the expected tests of this list"},
    {"step": "device-dist-build", "reachesDevice": False,
     "does": "builds the distributable, unsigned, into the run's folder (never dist/)"},
    {"step": "device-smoke-build", "reachesDevice": False,
     "does": "builds the smoke from the distributable alone for generic/platform=iOS, signed (Automatic, the "
             f"team of {TEAM_PBXPROJ}, -allowProvisioningUpdates)"},
    {"step": "device-smoke-install", "reachesDevice": True,
     "does": f"xcrun devicectl device install app: the smoke {SMOKE_BUNDLE_ID}"},
    {"step": "device-smoke-run", "reachesDevice": True,
     "does": "xcrun devicectl device process launch --console --terminate-existing: the smoke opens a window, "
             "shows an alert for 1.5 seconds and cancels it itself, writes and reads a named pasteboard of its "
             "own, installs the notification delegate (ntk_notification_install), prints SMOKE lines and ends "
             "itself (60 seconds at most). Do not touch the screen while it runs"},
)
# What the device path takes out of the environment of every xcodebuild it runs, so that nothing outside the
# approved list changes the build or the tests: an xcconfig that overrides the projects' settings, another
# toolchain, and every TEST_RUNNER_ variable (it reaches the test host's environment).
DEVICE_ENV_REMOVED = ("XCODE_XCCONFIG_FILE", "TOOLCHAINS")
DEVICE_ENV_REMOVED_PREFIXES = ("TEST_RUNNER_",)
# The smoke's steps (ios/IosLibraryCApiSmoke: main.m and Smoke.c), each printed once as `SMOKE PASS <step>: ...`.
SMOKE_STEPS = ("version", "notification install", "notification listener", "clipboard create", "clipboard copy",
               "clipboard read", "clipboard remove", "dialog show", "dialog cancel", "dialog",
               "callbacks: clipboard create", "callbacks: clipboard copy", "callbacks: clipboard read",
               "callbacks: clipboard remove", "callbacks: dialog", "callbacks: notification listener")
DEVICE_NOT_TOUCHED = ("the general pasteboard (no paste alert)", "notification permission, notifications, badges",
                      "share sheets and other apps", "Photos and Files", "settings")
DEVICE_LEFT = (
    {"bundleId": ui.CAPI_TEST_HOST_BUNDLE_ID, "by": "device-unit-asan"},
    {"bundleId": SMOKE_BUNDLE_ID, "by": "device-smoke-install"},
)
DEVICE_REMOVAL = ("neither app is removed: removing an app needs its own approval each time "
                  "(agent-rules/device-testing.md). They stay on the device until the user removes them")
DEVICE_SIGNING = ("Automatic signing with the team of the C ABI's project and -allowProvisioningUpdates: Xcode may "
                  "register the two bundle IDs in the user's developer account and create development profiles "
                  "for them, as for the sample's device build")
DEVICE_RESULTS = ("the device's result bundles, DerivedData and logs stay in a temporary folder that the run "
                  "removes at its end; no attachment is exported; only the judgements go to results.jsonl")


def team_values(pbxproj_text):
    """The distinct DEVELOPMENT_TEAM values of a project (empty values are left out)."""
    return sorted({value for value in _TEAM.findall(pbxproj_text) if value})


def signing_team(pbxproj_text):
    values = team_values(pbxproj_text)
    if len(values) != 1:
        raise RunnerError(f"{TEAM_PBXPROJ} has {len(values)} signing teams; the device run needs exactly one")
    if not _TEAM_VALUE.match(values[0]):
        raise RunnerError(f"{TEAM_PBXPROJ}: the signing team is not ten letters and digits")
    return values[0]


def device_runner_file_hashes(repo):
    return {relative: ui.file_sha256(pathlib.Path(repo) / relative) for relative in DEVICE_RUNNER_FILES}


def unit_test_ids(enumeration_text):
    """The tests of IosLibraryCApiTests in a simulator's enumeration (`-enumerate-tests ... -test-enumeration-format
    json`), as the result bundle names them: `Class/test()`."""
    data = json.loads(enumeration_text)
    if data.get("errors"):
        raise RunnerError(f"the enumeration has errors: {str(data['errors'])[:200]}")
    ids = []
    for value in data.get("values", []):
        for test in value.get("enabledTests", []):
            identifier = test.get("identifier", "")
            parts = identifier.split("/")
            if len(parts) == 3 and parts[0] == "IosLibraryCApiTests" and parts[2].endswith("()"):
                ids.append(f"{parts[1]}/{parts[2]}")
    if not ids:
        raise RunnerError("the enumeration lists no test of IosLibraryCApiTests")
    if len(set(ids)) != len(ids):
        raise RunnerError("the enumeration lists a test twice")
    return sorted(ids)


def result_cases(tests_text):
    """The test cases of a result bundle (`xcresulttool get test-results tests`): {identifier: [results]}."""
    cases = {}

    def walk(node):
        if node.get("nodeType") == "Test Case":
            cases.setdefault(node.get("nodeIdentifier"), []).append(node.get("result"))
        for child in node.get("children", []):
            walk(child)
    for node in json.loads(tests_text).get("testNodes", []):
        walk(node)
    return cases


def expected_tests_problems(expected, tests_text):
    """Exactly the expected tests ran, each once, and each passed."""
    if not expected:
        return ["the plan has no expected tests"]
    try:
        cases = result_cases(tests_text)
    except ValueError as error:
        return [f"the tests of the result bundle are not JSON ({error})"]
    problems = []
    missing = sorted(set(expected) - set(cases))
    extra = sorted(set(cases) - set(expected))
    if missing:
        problems.append(f"{len(missing)} expected test(s) did not run, first: {missing[0]}")
    if extra:
        problems.append(f"{len(extra)} test(s) ran that the list does not name, first: {extra[0]}")
    twice = sorted(k for k, v in cases.items() if len(v) != 1)
    if twice:
        problems.append(f"{len(twice)} test(s) ran more than once, first: {twice[0]}")
    failed = sorted(k for k, v in cases.items() if any(r != "Passed" for r in v))
    if failed:
        problems.append(f"{len(failed)} test(s) did not pass, first: {failed[0]}")
    return problems


def report_kinds(reports):
    """A sanitizer's report as its kinds and counts, never its lines (they can carry paths and addresses)."""
    kinds = {}
    for line in reports:
        name = re.search(_SANITIZER, line)
        name = name.group(0) if name else ("UBSan" if ": runtime error: " in line else "sanitizer")
        form = next((f for f in ("DEADLYSIGNAL", "CHECK failed", "FATAL", "SUMMARY", "WARNING", "ERROR", "reported",
                                 "runtime error") if f in line), "report")
        key = f"{name} {form}"
        kinds[key] = kinds.get(key, 0) + 1
    return ", ".join(f"{k} x{v}" for k, v in sorted(kinds.items()))


def make_device_plan(udid, head, xcode, version, runner_files, expected_tests):
    if not re.fullmatch(r"[0-9A-Za-z-]+", udid or ""):
        raise RunnerError("malformed udid")
    return {
        "schema": 1, "kind": DEVICE_KIND, "udid": udid, "head": head, "xcode": xcode, "libraryVersion": version,
        "expectedTests": list(expected_tests),
        "runnerFiles": dict(runner_files), "actions": [dict(a) for a in DEVICE_ACTIONS],
        "notTouched": list(DEVICE_NOT_TOUCHED), "leftOnDevice": [dict(a) for a in DEVICE_LEFT],
        "removal": DEVICE_REMOVAL, "signing": DEVICE_SIGNING, "results": DEVICE_RESULTS,
    }


def make_device_approval(plan, created_at=None, approval_id=None):
    if plan.get("kind") != DEVICE_KIND:
        raise RunnerError("not a --capi-device plan")
    approval = dict(plan)
    approval.update({
        "planDigest": ui.plan_digest(plan),
        "approvalId": approval_id or secrets.token_hex(16),
        "createdAt": created_at or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    })
    return approval


_CREATED_AT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\+00:00|Z)$")


def device_approval_problems(approval, plan):
    """The approved list must be exactly the list this run would write, apart from its ID and time."""
    if not isinstance(approval, dict) or approval.get("schema") != 1 or approval.get("kind") != DEVICE_KIND:
        return ["the approval file is not a --capi-device approval list"]
    if plan.get("kind") != DEVICE_KIND:
        return ["not a --capi-device plan"]
    problems = []
    if not ui.APPROVAL_ID.match(str(approval.get("approvalId", ""))):
        problems.append("the approval ID is missing or malformed")
    if not _CREATED_AT.match(str(approval.get("createdAt", ""))):
        problems.append("the approval time is missing or malformed")
    expected = make_device_approval(plan, created_at=approval.get("createdAt"), approval_id=approval.get("approvalId"))
    unknown = sorted(set(approval) - set(expected))
    missing = sorted(set(expected) - set(approval))
    if unknown or missing:
        problems.append(f"the approval's keys differ: unknown {unknown}, missing {missing}")
    for field in sorted(set(expected) & set(approval)):
        if field not in ("approvalId", "createdAt") and approval[field] != expected[field]:
            problems.append(f"{field} differs from this run")
    return problems


def _git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)


def device_runner_problems(plan, repo):
    """Every file of the device run is committed as it is, and is the one the plan was made with."""
    problems = []
    for relative in DEVICE_RUNNER_FILES:
        if _git(repo, "ls-files", "--error-unmatch", "--", relative).returncode != 0:
            problems.append(f"{relative} is not committed")
            continue
        status = _git(repo, "status", "--porcelain=v1", "--", relative)
        if status.returncode != 0 or status.stdout.strip():
            problems.append(f"{relative} differs from the commit")
    if not plan.get("runnerFiles") or device_runner_file_hashes(repo) != plan["runnerFiles"]:
        problems.append("the runner files differ from the ones the approved plan was made with")
    return problems


def device_tree_problems(plan, repo, head):
    """The device builds the commit the plan names, with nothing under ios/ changed or added."""
    problems = []
    if head != plan.get("head"):
        problems.append(f"HEAD is {head}, the plan was made at {plan.get('head')}")
    dirty = ui.git_ios_changes(repo)
    if dirty:
        problems.append(f"uncommitted changes under ios/ ({len(dirty)}): {dirty[:5]}")
    return problems


def device_gate_problems(plan, approval, repo, head, ledger):
    if plan.get("kind") != DEVICE_KIND or not isinstance(approval, dict):
        return ["not an approved --capi-device plan"]
    problems = []
    if ui.plan_digest(plan) != approval.get("planDigest"):
        problems.append("the plan differs from the approved one")
    try:
        consumed = approval.get("approvalId") in ui.ledger_ids(pathlib.Path(ledger).read_text(encoding="utf-8"))
    except (OSError, ui.RunnerError):
        consumed = False
    if not consumed:
        problems.append("the approval was not consumed in the ledger")
    return problems + device_runner_problems(plan, repo) + device_tree_problems(plan, repo, head)


def print_device_plan(plan):
    # The hardware UDID stays in the plan and the approval files (as the sample's); it is never printed.
    print(f"[capi-device] the device given by --udid, library {plan['libraryVersion']}, {plan['xcode']}, HEAD {plan['head']}")
    print(f"  EXPECTED TESTS: {len(plan['expectedTests'])} of IosLibraryCApiTests (the simulator's enumeration), "
          "each exactly once")
    for action in plan["actions"]:
        where = "DEVICE" if action["reachesDevice"] else "mac   "
        print(f"  {where} {action['step']}: {action['does']}")
    print(f"  NOT TOUCHED: {'; '.join(plan['notTouched'])}")
    for app in plan["leftOnDevice"]:
        print(f"  LEFT ON THE DEVICE: {app['bundleId']} (installed by {app['by']})")
    print(f"  REMOVAL: {plan['removal']}")
    print(f"  SIGNING: {plan['signing']}")
    print(f"  RESULTS: {plan['results']}")


SMOKE_RESULT = re.compile(r"^SMOKE RESULT PASS failures=0$")


def smoke_step(line):
    """`SMOKE PASS dialog: ...` is `dialog`; `SMOKE PASS callbacks: dialog: ...` is `callbacks: dialog`."""
    rest = line[len("SMOKE PASS "):]
    parts = rest.split(": ")
    if parts[0] == "callbacks" and len(parts) > 1:
        return f"callbacks: {parts[1]}"
    return parts[0]


def device_report_problems(step, text):
    lines = [line.rstrip("\r") for line in text.splitlines()]
    problems = []
    if step == "device-smoke-build":
        if not any(line.startswith("== iOS C ABI smoke") for line in lines):
            problems.append("no '== iOS C ABI smoke' report")
        failed = [line.strip() for line in lines if re.match(r"\s+FAIL ", line)]
        if failed:
            problems.append(f"{len(failed)} FAIL, first: {failed[0][:200]}")
        for needed in ("device build (signed)", "device embeds", "device needs no Swift library",
                       "device imports nothing of IosLibrary"):
            if not any(re.match(r"\s+PASS " + re.escape(needed) + r"(?=:|\s*$)", line) for line in lines):
                problems.append(f"no PASS {needed}")
    if step == "device-smoke-run":
        # Only the app's own SMOKE lines are read and counted; devicectl's lines (they can name the device)
        # are never copied into the record.
        smoke = [line for line in lines if line.startswith("SMOKE ")]
        if any(line.startswith("SMOKE FAIL") for line in smoke):
            problems.append(f"{sum(line.startswith('SMOKE FAIL') for line in smoke)} SMOKE FAIL line(s)")
        if any(line.startswith("SMOKE RESULT FAIL") for line in smoke):
            problems.append("a SMOKE RESULT FAIL line")
        steps = [smoke_step(line) for line in smoke if line.startswith("SMOKE PASS ")]
        missing = [s for s in SMOKE_STEPS if steps.count(s) == 0]
        repeated = sorted({s for s in steps if steps.count(s) > 1})
        unknown = sorted({s for s in steps if s not in SMOKE_STEPS})
        if missing:
            problems.append(f"{len(missing)} smoke step(s) without SMOKE PASS: {', '.join(missing)}")
        if repeated:
            problems.append(f"smoke step(s) passed more than once: {', '.join(repeated)}")
        if unknown:
            problems.append(f"{len(unknown)} SMOKE PASS line(s) of no known step")
        if sum(bool(SMOKE_RESULT.match(line)) for line in smoke) != 1:
            problems.append("no single 'SMOKE RESULT PASS failures=0' line")
    return problems


def device_step_record(step, exit_code, timed_out, log, not_run):
    if step not in DEVICE_STEPS or step == "device-unit-asan":
        raise RunnerError(f"unknown device step {step}")
    if not_run:
        return {"step": step, "status": "FAIL", "detail": f"not run: {not_run}"}
    problems = []
    if timed_out:
        problems.append("cut off by the time limit")
    elif exit_code != 0:
        problems.append(f"ended with status {exit_code}")
    text = _read_optional(log)
    if text is None:
        problems.append("no log")
    else:
        problems += device_report_problems(step, text)
    detail = "; ".join(problems)
    if not problems and step == "device-smoke-run":
        detail = f"the {len(SMOKE_STEPS)} smoke steps passed once each"
    return {"step": step, "status": "FAIL" if problems else "PASS", "detail": detail}


def device_summary(records):
    problems = []
    by_step = {}
    for record in records:
        by_step.setdefault(record.get("step"), []).append(record)
    for step in by_step:
        if step not in DEVICE_STEPS:
            problems.append(f"{step}: not a step of --capi-device")
    for step in DEVICE_STEPS:
        if len(by_step.get(step, [])) != 1:
            problems.append(f"{step}: recorded {len(by_step.get(step, []))} times, expected once")
    failed = [r["step"] for r in records if r.get("status") != "PASS"]
    lines = [f"  {r.get('status')} {r.get('step')}" + (f": {r['detail']}" if r.get("detail") else "") for r in records]
    lines += [f"  PROBLEM {p}" for p in problems]
    passed = sum(1 for r in records if r.get("status") == "PASS")
    lines.append(f"[summary] {passed} passed, {len(failed) + len(problems)} problem(s) (the device)")
    return lines, not failed and not problems


def _head(repo):
    return _git(repo, "rev-parse", "HEAD").stdout.strip()


def cmd_device_plan(args):
    signing_team(pathlib.Path(args.repo, TEAM_PBXPROJ).read_text(encoding="utf-8"))
    problem = xcode_problem(args.xcode, "--capi-device")
    if problem:
        print(f"Error: {problem}", file=sys.stderr)
        return 2
    expected = unit_test_ids(pathlib.Path(args.enumeration).read_text(encoding="utf-8"))
    plan = make_device_plan(args.udid, args.head, args.xcode, args.version, device_runner_file_hashes(args.repo), expected)
    ui._write_json(args.plan, plan)
    print_device_plan(plan)
    if not args.dry_run:
        return 0
    approval = make_device_approval(plan)
    ui._write_json(args.approval_out, approval)
    print(f"[dry-run] approval ID {approval['approvalId']}")
    for problem in device_runner_problems(plan, args.repo):
        print(f"[dry-run] {problem.upper()}: the device run will refuse until the runner is committed")
    dirty = ui.git_ios_changes(args.repo)
    if dirty:
        print(f"[dry-run] UNCOMMITTED CHANGES UNDER ios/ ({len(dirty)}, e.g. {dirty[:3]}): the device run will "
              "refuse until they are committed")
    print(f"[dry-run] approval list: {args.approval_out}")
    print("[dry-run] show the list above to the user; after approval run again with --approved <that file> "
          "--devicectl-id <id>")
    return 0


def cmd_device_approve(args):
    plan = json.loads(pathlib.Path(args.plan).read_text(encoding="utf-8"))
    try:
        approval = json.loads(pathlib.Path(args.approved).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"Error: cannot read the approval file: {error}", file=sys.stderr)
        return 1
    problems = device_approval_problems(approval, plan)
    if not problems:
        problems += device_tree_problems(plan, args.repo, args.head) + device_runner_problems(plan, args.repo)
    for problem in problems:
        print(f"  FAIL {problem}")
    if problems:
        print("Error: the approval does not match this run; run --dry-run and ask the user again", file=sys.stderr)
        return 1
    ui.consume_approval(ui.DEFAULT_LEDGER, approval["approvalId"], plan["udid"])
    print(f"[approval] {approval['approvalId']} matches and is now consumed ({ui.DEFAULT_LEDGER})")
    return 0


def cmd_device_gate(args):
    plan = json.loads(pathlib.Path(args.plan).read_text(encoding="utf-8"))
    approval = json.loads(pathlib.Path(args.approved).read_text(encoding="utf-8"))
    problems = device_gate_problems(plan, approval, args.repo, _head(args.repo), ui.DEFAULT_LEDGER)
    for problem in problems:
        print(f"  FAIL {problem}", file=sys.stderr)
    if problems:
        print("Error: not touching the device: the approved plan, the runner or the tree changed", file=sys.stderr)
        return 1
    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog="ios_capi_runner.py")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("version")
    p.add_argument("--common-h", required=True)
    p = sub.add_parser("check-xcode")
    p.add_argument("--xcode", required=True)
    p.add_argument("--device", action="store_true", help="for --capi-device")
    p = sub.add_parser("unit-record")
    p.add_argument("--variant", required=True, choices=VARIANTS)
    p.add_argument("--exit-code", required=True, type=int)
    p.add_argument("--timed-out", required=True, type=int, choices=(0, 1))
    p.add_argument("--summary-json", required=True)
    p.add_argument("--log", action="append", default=[], nargs=2, metavar=("LABEL", "PATH"))
    p.add_argument("--otool", action="append", default=[], nargs=2, metavar=("FRAMEWORK", "PATH"))
    p.add_argument("--results", required=True)
    p = sub.add_parser("step-record")
    p.add_argument("--step", required=True)
    p.add_argument("--exit-code", type=int, default=0)
    p.add_argument("--timed-out", type=int, default=0, choices=(0, 1))
    p.add_argument("--log", default="")
    p.add_argument("--not-run", default="")
    p.add_argument("--results", required=True)
    p = sub.add_parser("summary")
    p.add_argument("--results", required=True)
    p = sub.add_parser("device-identity")
    p.add_argument("--plan", required=True)
    p.add_argument("--devicectl-json", required=True)
    p = sub.add_parser("last-status")
    p.add_argument("--results", required=True)
    p = sub.add_parser("device-plan")
    for name in ("--udid", "--head", "--xcode", "--version", "--repo", "--plan", "--enumeration"):
        p.add_argument(name, required=True)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--approval-out", default="")
    p = sub.add_parser("device-approve")
    for name in ("--plan", "--approved", "--repo", "--head"):
        p.add_argument(name, required=True)
    p = sub.add_parser("device-gate")
    for name in ("--plan", "--approved", "--repo"):
        p.add_argument(name, required=True)
    p = sub.add_parser("device-team")
    p.add_argument("--repo", required=True)
    p.add_argument("--check", action="store_true")
    p = sub.add_parser("device-unit-record")
    p.add_argument("--plan", required=True)
    p.add_argument("--tests-json", required=True)
    p.add_argument("--exit-code", required=True, type=int)
    p.add_argument("--timed-out", required=True, type=int, choices=(0, 1))
    p.add_argument("--summary-json", required=True)
    p.add_argument("--log", action="append", default=[], nargs=2, metavar=("LABEL", "PATH"))
    p.add_argument("--otool", action="append", default=[], nargs=2, metavar=("FRAMEWORK", "PATH"))
    p.add_argument("--results", required=True)
    p = sub.add_parser("device-step-record")
    p.add_argument("--step", required=True)
    p.add_argument("--exit-code", type=int, default=0)
    p.add_argument("--timed-out", type=int, default=0, choices=(0, 1))
    p.add_argument("--log", default="")
    p.add_argument("--not-run", default="")
    p.add_argument("--results", required=True)
    p = sub.add_parser("device-summary")
    p.add_argument("--results", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "version":
            print(library_version(pathlib.Path(args.common_h).read_text(encoding="utf-8")))
            return 0
        if args.command == "device-plan":
            if args.dry_run and not args.approval_out:
                raise RunnerError("--dry-run needs --approval-out")
            return cmd_device_plan(args)
        if args.command == "device-identity":
            plan = json.loads(pathlib.Path(args.plan).read_text(encoding="utf-8"))
            try:
                ui.device_environment(plan["udid"], pathlib.Path(args.devicectl_json).read_text(encoding="utf-8"))
            except (ui.RunnerError, ValueError, AttributeError):
                # The JSON is never printed: it describes the user's device.
                print("Error: the device that --devicectl-id names is not the device of the approved list "
                      "(or its details could not be read); nothing reached it but the read", file=sys.stderr)
                return 1
            print("[capi-device] --devicectl-id names the device of the approved list")
            return 0
        if args.command == "last-status":
            lines = [line for line in (_read_optional(args.results) or "").splitlines() if line.strip()]
            print(json.loads(lines[-1]).get("status") if lines else "NONE")
            return 0
        if args.command == "device-approve":
            return cmd_device_approve(args)
        if args.command == "device-gate":
            return cmd_device_gate(args)
        if args.command == "device-team":
            team = signing_team(pathlib.Path(args.repo, TEAM_PBXPROJ).read_text(encoding="utf-8"))
            if args.check:
                print(f"[signing] one team in {TEAM_PBXPROJ}")
            else:
                print(team)
            return 0
        if args.command == "device-unit-record":
            for framework, _ in args.otool:
                if framework not in FRAMEWORKS:
                    raise RunnerError(f"unknown framework {framework}")
            plan = json.loads(pathlib.Path(args.plan).read_text(encoding="utf-8"))
            _append(args.results, unit_record("asan", args.exit_code, bool(args.timed_out), args.summary_json,
                                              args.log, args.otool, device=True, expected=plan.get("expectedTests"),
                                              tests_json=args.tests_json))
            return 0
        if args.command == "device-step-record":
            _append(args.results, device_step_record(args.step, args.exit_code, bool(args.timed_out), args.log,
                                                     args.not_run))
            return 0
        if args.command == "device-summary":
            records = [json.loads(line) for line in (_read_optional(args.results) or "").splitlines() if line.strip()]
            lines, passed = device_summary(records)
            print("\n".join(lines))
            return 0 if passed else 1
        if args.command == "check-xcode":
            problem = xcode_problem(args.xcode, "--capi-device" if args.device else "--capi")
            if problem:
                print(f"Error: {problem}", file=sys.stderr)
                return 2
            return 0
        if args.command == "unit-record":
            for framework, _ in args.otool:
                if framework not in FRAMEWORKS:
                    raise RunnerError(f"unknown framework {framework}")
            _append(args.results, unit_record(args.variant, args.exit_code, bool(args.timed_out), args.summary_json,
                                              args.log, args.otool))
            return 0
        if args.command == "step-record":
            _append(args.results, step_record(args.step, args.exit_code, bool(args.timed_out), args.log, args.not_run))
            return 0
        text = _read_optional(args.results) or ""
        records = []
        for line in text.splitlines():
            if line.strip():
                records.append(json.loads(line))
        lines, passed = summary(records)
        print("\n".join(lines))
        return 0 if passed else 1
    except (RunnerError, ui.RunnerError, OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
