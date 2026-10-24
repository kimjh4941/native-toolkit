"""Mutation runs of the iOS UI test runner (design chapter 7; stage 0d reviews v1 and v2).

Breaks one decision at a time in a copy of the repository's runner (scripts/, the UI test folder,
the sample's sources and the project file) and runs scripts/tests/test_ios_ui_runner.py there.
Every mutation must be caught; the first entry changes nothing and must survive.

Every copy is kept away from the real approval ledger: the copy's ledger home is replaced by the
copy's folder and HOME points there too, whatever the mutation does, and the real ledger
(~/Library/Application Support/native-toolkit/) is compared before and after the run.

Not a unit test (the name does not start with test_). Run:
    python3 scripts/tests/ios_ui_runner_mutations.py [--only <part of a title>,...]
"""

import argparse
import hashlib
import os
import pathlib
import pwd
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
M = "scripts/ios_ui_runner.py"
S = "scripts/test_ios.sh"
H = "scripts/tests/ios_ui_runner_mutations.py"
SB = "ios/IosLibraryExample/IosLibraryExampleUITests/Support/Springboard.swift"
CB = "ios/IosLibraryExample/IosLibraryExampleUITests/ClipboardPasteUITests.swift"
SAMPLE = "ios/IosLibraryExample/IosLibraryExample/NotificationSampleView.swift"
COPIED = ("scripts", "ios/IosLibraryExample/IosLibraryExampleUITests", "ios/IosLibraryExample/IosLibraryExample",
          "ios/IosLibraryExample/IosLibraryExample.xcodeproj/project.pbxproj")
LEDGER_HOME = "pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)"
REAL_LEDGER_DIR = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library" / "Application Support" / "native-toolkit"

MUTATIONS = [
    ('baseline: no mutation (must survive)', None, None, None),
    ('pillar 1 selection: all categories -> any category', M, '        if kind == "device" and missing:', '        if kind == "device" and len(missing) == len(categories) and categories:'),
    ('pillar 1 destination: fail open', M, '    return "simulator" if udid in sim_udids else "device"', '    return "simulator"'),
    ('pillar 1 enumeration: on the device', M, '    target = udid if kind == "simulator" else enumerate_udid', '    target = udid'),
    ('pillar 1 naming: an empty -only-testing list', M, '    if not names:\n        raise RunnerError(f"{invocation.get(\'name\')}: refusing', '    if False:\n        raise RunnerError(f"{invocation.get(\'name\')}: refusing'),
    ('pillar 1 naming: a class on the device', M, '            if name.count("/") != 2 or not name.endswith("()"):', '            if False:'),
    ('pillar 1 results: duplicates ignored', M, '    if duplicates(result_keys):\n        problems.append', '    if False:\n        problems.append'),
    ('pillar 1 results: sets not compared', M, '    if len(result_keys) != len(set(result_keys)) or sorted(set(result_keys)) != sorted(set(expected_keys)):', '    if False:'),
    ('pillar 2: a missing declaration passes', M, '    if missing:\n        problems.append(f"tests without a declaration', '    if False:\n        problems.append(f"tests without a declaration'),
    ('pillar 2: UI_CLASSES not checked', M, '    if classes != known_classes:', '    if False:'),
    ('pillar 2: class minimums not checked', M, '        if not minimum <= set(categories):', '        if False:'),
    ('pillar 2: the frozen 22 not checked', M, '    if sorted(methods) != sorted(FROZEN_CLIPBOARD_METHODS):', '    if False:'),
    ('pillar 2: the bundled declarations not checked', M, '    return [f"the bundled copy differs from {DECLARATIONS_FILE}: {p}" for p in bundle_paths if file_sha256(p) != expected]', '    return []'),
    ('pillar 2 binary: AndReturnError kept', M, '    if selector.endswith("AndReturnError:"):\n        selector = selector[: -len("AndReturnError:")]', '    pass'),
    ('pillar 2 rules: a class that is not final', M, '        if modifiers != ["final"] or attributes or inherits != [":", BASE_CLASS]:', '        if inherits[:1] != [":"]:'),
    ('pillar 2 rules: any override', M, '            if not ok or _word(prev, "static", "class"):', '            if False:'),
    ('pillar 2 rules: #if allowed', M, '    if role != "base":\n        return [(t.line,', '    if role != "base":\n        return []\n        return [(t.line,'),
    ('pillar 2 rules: async tests allowed', M, '    shape_ok = after[:2] == ["(", ")"] and (after[2] == "{" or after[2:4] == ["throws", "{"])', '    shape_ok = after[:2] == ["(", ")"]'),
    ('pillar 2 rules: dangerous names anywhere', M, '    elif relative not in DANGEROUS_NAME_FILES:', '    elif False:'),
    ('pillar 2 rules: XCTExpectFailure allowed', M, 'FORBIDDEN_NAMES = ("XCTExpectFailure", "XCTExpectedFailure", ', 'FORBIDDEN_NAMES = ('),
    ('pillar 2 rules: identifier strings allowed', M, '                if not in_enum and any(IDENTIFIER_STRING.search(s) for s in t.segments):', '                if False:'),
    ("pillar 2 rules: the frozen file's counts not checked", M, '            if dangerous_counts[name] != expected:', '            if False:'),
    ('trusted part: hashes not checked', M, '        if actual != expected:\n            changes.append', '        if False:\n            changes.append'),
    ('pillar 3: the approved tests not compared', M, '        if approval[field] != expected[field]:', '        if field != "tests" and approval[field] != expected[field]:'),
    ('pillar 3: --device-allow not compared', M, '        if field in ("approvalId", "createdAt"):', '        if field in ("approvalId", "createdAt", "deviceAllow"):'),
    ('pillar 3: the ledger not read', M, '        if approval_id in ledger_ids(text):', '        if False:'),
    ('results: Expected Failure passes', M, '    if result == "Expected Failure":\n        return "failed"', '    if result == "Expected Failure":\n        return "passed"'),
    ('results: an unlisted skip is a skip', M, '        return "failed", f"skip not in the intended list', '        return "skipped", f"skip not in the intended list'),
    ('results: NTK-GATED is a skip', M, '        if "NTK-GATED:" in reason:\n            return "failed"', '        if "NTK-GATED:" in reason:\n            return "skipped"'),
    ('cleanup: HUP left out of the trap', S, "  trap 'exit 129' HUP\n", ''),
    ('cleanup: the trap set after the first device call', S, '  setup_device_tmp\n  RESULT_ROOT=', '  RESULT_ROOT='),
    ('cleanup: the device guard removed', S, '  if [[ "${DEVICE_TRAP_READY}" != 1 || "${APPROVAL_CONSUMED}" != 1 ]]; then', '  if false; then'),
    ('baseline: lost coverage in scope ignored', M, '            if baseline_results[t] == "passed":\n                lost.append(t)', '            pass'),
    ('v1-1 cmd_approve ignores a mismatch', M, '    if problems:\n        return _fail("the approval does not match this run', '    if False:\n        return _fail("the approval does not match this run'),
    ('v1-2 cmd_record does not return 3 on the device', M, 'stopping the device run", 3)', 'stopping the device run", 0)'),
    ('v1-3 cmd_may_uninstall always 0', M, '    return _fail("reinstall is not allowed and approved; not removing the sample from the device")', '    return 0'),
    ('v1-4 cmd_verify_tree always 0', M, '    if problems:\n        return _fail("the tree changed after the enumeration', '    if False:\n        return _fail("the tree changed after the enumeration'),
    ('v1-5 preflight accepts a changed trusted part', M, '    if args.kind == "device" and changes and not args.dry_run:', '    if False:'),
    ('v1-6 summary skips the ran-versus-approved check', M, '        if ran != approved:', '        if False:'),
    ('v1-7 lost baseline tests do not fail', M, '    failed = failed or (bool(lost) and not args.save_baseline)', '    failed = failed'),
    ('v1-8 exit code != 0 with every test passed', M, '    if exit_code != 0 and cases and all(', '    if False and cases and all('),
    ('v1-9 zero tests', M, '    if not cases:\n        pseudo("zeroTests"', '    if False:\n        pseudo("zeroTests"'),
    ('v1-10 duplicated tests in the binary', M, '    if duplicates(binary_keys):', '    if False:'),
    ('v1-11 NSPrincipalClass in the Info.plist', M, '        if "NSPrincipalClass" in info:', '        if False:'),
    ('R-6 the ledger follows an environment variable', M, '    ledger = pathlib.Path(args.ledger_for_self_test) if args.ledger_for_self_test else DEFAULT_LEDGER', '    ledger = pathlib.Path(os.environ.get("NTK_TEST_IOS_APPROVAL_LEDGER", str(DEFAULT_LEDGER)))'),
    ('R-6 the ledger follows $HOME', M, 'DEFAULT_LEDGER = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)', 'DEFAULT_LEDGER = pathlib.Path.home()'),
    ('R-7 malformed lines not checked', M, '        if not LEDGER_LINE.match(line):\n            raise', '        if False:\n            raise'),
    ('R-7 an incomplete last line not checked', M, '    if text and not text.endswith("\\n"):', '    if False:'),
    ('R-7 a symlinked ledger allowed', M, '        if path.is_symlink() or (path.exists() and not path.is_file()):', '        if False:'),
    ('R-8 only the test IDs compared', M, '        if approval[field] != expected[field]:', '        if (field == "tests" and [t.get("id") for t in approval[field]] != [t["id"] for t in expected[field]]) or (field not in ("tests", "excluded") and approval[field] != expected[field]):'),
    ('R-8 unknown keys allowed', M, '    if unknown or missing:', '    if missing:'),
    ('R-9 uncommitted changes under ios/ ignored', M, '    dirty = git_ios_changes(repo)\n    if dirty:\n        problems.append(f"uncommitted', '    dirty = git_ios_changes(repo)\n    if False:\n        problems.append(f"uncommitted'),
    ('R-10 sim_xcodebuild does not check the destination', S, '    if [[ "${previous}" == "-destination" && "${argument}" != "platform=iOS Simulator,id="* ]]; then', '    if false; then'),
    ('R-10 a device destination on a continuation line', S, '  -destination "platform=iOS Simulator,id=${ENUM_UDID}" -derivedDataPath "${DD_SIM}" -quiet \\', '  -destination "platform=iOS,id=${UDID}" -derivedDataPath "${DD_SIM}" -quiet \\'),
    ('R-11 nothing stops the device', M, '    def pseudo(problem, message, stops=True):', '    def pseudo(problem, message, stops=False):'),
    ('R-11 unknown shapes ignored', M, '        if case["unknownShape"]:', '        if False:'),
    ('R-11 unreadable names not counted', M, '    if len(pairs) != len(cases):', '    if False:'),
    ('R-12 the device DerivedData outside the trap folder', S, '      -derivedDataPath "${DEVICE_TMP}/dd-test" -collect-test-diagnostics never \\\n', ''),
    ('R-13 a failed exec exits 0', S, ' or die "cannot run $ARGV[0]: $!\\n"\'', "'"),
    ('R-14 the device bundle not checked', M, '    problems = binary_inventory_problems(keys, plan["enumeration"])\n    problems += bundle_problems(args.tests_dir, args.products)', '    problems = binary_inventory_problems(keys, plan["enumeration"])'),
    ('R-15 an empty device plan allowed', M, '    if kind == "device" and not selected:', '    if False:'),
    ('R-17 the simulator does not name each test', M, '        if kind == "simulator" and not name_each_test:', '        if kind == "simulator":'),
    ("R-18 the runner files' commit not checked", M, '    problems = []\n    for relative in RUNNER_FILES:', '    problems = []\n    for relative in ():'),
    ("R-18 the runner files' hashes not compared", M, '    if not plan.get("runnerFiles") or runner_file_hashes(repo) != plan["runnerFiles"]:', '    if False:'),
    ('R-18 approve does not check the runner', M, '    problems += runner_problems(plan, args.repo)\n', ''),
    ('R-19 the gate ignores the plan digest', M, '    if plan_digest(plan) != approval.get("planDigest"):', '    if False:'),
    ('R-19 the gate ignores the ledger', M, '    if not consumed:\n        problems.append', '    if False:\n        problems.append'),
    ('R-19 device_guard without the gate', S, '  runner device-gate --plan "${PLAN}" --approved "${APPROVED}" --repo "${ROOT_DIR}" --tests-dir "${TESTS_DIR}" || return 97\n', ''),
    ('R-19 the plan is not switched to the read-only copy', S, '  PLAN="${DEVICE_TMP}/plan.approved.json"\n', ''),
    ('R-20 only four unknown child kinds', M, '            shapes = sorted({str(c.get("nodeType")) for c in node.get("children", [])} - KNOWN_CASE_CHILDREN)', '            shapes = sorted({str(c.get("nodeType")) for c in node.get("children", [])} & {"Repetition", "Arguments", "Device", "Test Plan Configuration"})'),
    ("R-21 the sample's reply placeholder back to Type a message", SAMPLE, 'textInputPlaceholder: "IosLibraryExample reply"', 'textInputPlaceholder: "Type a message"'),
    ("R-21 the expanded root not checked for the sample's content", SB, '        )), "content of the expanded sample notification")\n        return root', '        ))\n        return root'),
    ('R-21 the reply window not taken again before Send', SB, '        let typed = try exactlyOne(springboard.windows.containing(afterTyping), "reply window")', '        let typed = scope'),
    ('R-3 CB1 presses Allow Paste without the source check', CB, 'try springboard.tapPasteAlertFromKnownSource(SystemLabels.allowPaste)', 'try springboard.tapAlertButton(SystemLabels.allowPaste)'),
    ('C NTK_TEST_IOS_SOURCE_ONLY works when executed', S, 'if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then\n  if [[ "${NTK_TEST_IOS_SOURCE_ONLY:-0}" == 1 ]]; then\n    return 0\n  fi\nelif [[ -n "${NTK_TEST_IOS_SOURCE_ONLY:-}" ]]; then\n  echo "Error: NTK_TEST_IOS_SOURCE_ONLY is for the self-tests that source this file; unset it to run" >&2\n  exit 2\nfi', 'if [[ "${NTK_TEST_IOS_SOURCE_ONLY:-0}" == 1 ]]; then\n  return 0 2>/dev/null || exit 0\nfi'),
    ('device run 1: sim_xcodebuild without the path check', S, '  require_own_paths "${OUT_DIR:-}" "$@" || return 97\n', ''),
    ('device run 1: device_xcodebuild without the path check', S, '  require_own_paths "${DEVICE_TMP:-}" "$@" || return 97\n', ''),
    ('device run 1: the simulator may use BUILD_ROOT outside the run', S, '  require_own_paths "${OUT_DIR:-}" "$@" || return 97\n', '  require_own_paths "${BUILD_ROOT}" "$@" || return 97\n'),
    ('device run 1: the device may use BUILD_ROOT', S, '  require_own_paths "${DEVICE_TMP:-}" "$@" || return 97\n', '  require_own_paths "${BUILD_ROOT}" "$@" || return 97\n'),
    ('device run 1: the device build outside DEVICE_TMP', S, '  DD_DEVICE="${DEVICE_TMP}/dd-build"\n', '  DD_DEVICE="${BUILD_ROOT}/DerivedData-device"\n'),
    ('device run 1: the simulator build shared between runs', S, 'DD_SIM="${OUT_DIR}/dd-build"\n', 'DD_SIM="${BUILD_ROOT}/DerivedData-simulator"\n'),
    ('device run 1: -derivedDataPath given twice', S, '  if [[ "${derived_count}" -ne 1 ]] || ! path_inside', '  if [[ "${derived_count}" -lt 1 ]] || ! path_inside'),
    ('device run 1: -resultBundlePath given twice', S, '  if [[ "${bundle_count}" -ne 1 ]] || ! path_inside', '  if [[ "${bundle_count}" -lt 1 ]] || ! path_inside'),
    ('device run 1: -derivedDataPath without a value', S, '  if [[ "${derived_count}" -ne 1 ]] || ! path_inside "${root}" "${derived}"; then', '  if [[ "${derived_count}" -ne 1 ]] || { [[ -n "${derived}" ]] && ! path_inside "${root}" "${derived}"; }; then'),
    ('device run 1: the = form and other spellings', S, '    if [[ "${lower}" == *deriveddatapath* || "${lower}" == *resultbundlepath* ]]; then', '    if false; then'),
    ('device run 1: a symlink accepted', S, '    [[ -L "${prefix}" ]] && return 1\n', ''),
    ('device run 1: a test without -resultBundlePath', S, '  if [[ "${action}" == "build-for-testing" ]]; then\n    [[ "${bundle_count}" -eq 0 ]] && return 0\n  fi\n', '  [[ "${bundle_count}" -eq 0 ]] && return 0\n'),
    ('device run 1: the enumeration in the default DerivedData', S, '  -derivedDataPath "${OUT_DIR}/dd-enumerate" -resultBundlePath "${OUT_DIR}/enumerate.xcresult" \\\n', ''),
    ('device run 1: the simulator classes in the default DerivedData', S, '      -derivedDataPath "${OUT_DIR}/dd-test" -parallel-testing-enabled NO', '      -parallel-testing-enabled NO'),
    ('C the harness stops moving the ledger', H, '    code = code.replace(LEDGER_HOME, f"pathlib.Path({str(root)!r})")\n', ''),
]


def snapshot(directory):
    """The real ledger folder: None when it does not exist, else each file's hash."""
    if not directory.exists():
        return None
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(directory.iterdir()) if p.is_file()}


def prepare_copy(root, relative=None, old=None, new=None):
    """Copies what the self-tests read into root, applies one mutation, and moves the copy's
    ledger into root. Returns False when the mutation's text is not found exactly once."""
    for part in COPIED:
        source, target = REPO / part, root / part
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
        else:
            shutil.copy(source, target)
    applied = True
    if relative is not None:
        path = root / relative
        text = path.read_text(encoding="utf-8")
        if text.count(old) != 1:
            applied = False
        else:
            path.write_text(text.replace(old, new), encoding="utf-8")
    runner = root / M
    code = runner.read_text(encoding="utf-8")
    code = code.replace(LEDGER_HOME, f"pathlib.Path({str(root)!r})")
    if "getpwuid" in code:
        raise RuntimeError("the copy of the runner could still reach the real ledger; update LEDGER_HOME")
    runner.write_text(code, encoding="utf-8")
    return applied


def run_one(title, relative, old, new):
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        if not prepare_copy(root, relative, old, new):
            return "NOT APPLIED"
        finished = subprocess.run([sys.executable, "-m", "unittest", "scripts.tests.test_ios_ui_runner"], cwd=root,
                                  capture_output=True, text=True, timeout=900, env=dict(os.environ, HOME=str(root)),
                                  stdin=subprocess.DEVNULL)
        failing = sorted({line.split(" ")[1] for line in finished.stderr.splitlines()
                          if line.startswith(("FAIL:", "ERROR:"))})
        return ("CAUGHT " if finished.returncode else "SURVIVED ") + ", ".join(failing[:3])


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", default="", help="comma-separated parts of titles")
    args = parser.parse_args()
    before = snapshot(REAL_LEDGER_DIR)
    bad = 0
    for title, relative, old, new in MUTATIONS:
        if args.only and title != MUTATIONS[0][0] and not any(o in title for o in args.only.split(",")):
            continue
        outcome = run_one(title, relative, old, new)
        expected = "SURVIVED" if title == MUTATIONS[0][0] else "CAUGHT"
        bad += not outcome.startswith(expected)
        print(f"{'ok ' if outcome.startswith(expected) else 'BAD'} {title}: {outcome}", flush=True)
    after = snapshot(REAL_LEDGER_DIR)
    if before != after:
        print(f"BAD the real ledger changed during the run: {before} -> {after}")
        bad += 1
    else:
        print(f"ok  the real ledger is unchanged ({'absent' if after is None else 'present'})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
