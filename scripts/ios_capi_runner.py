"""The decisions of `scripts/test_ios.sh --capi`: the checks of the C ABI that run on one simulator.

C ABI design part 1, C-6 and 6.1 (P1-20), part 2, TB-12 and 12.1 to 12.4: IosLibraryCApiTests in three
variants (no sanitizer, ASan, TSan), a build of the distributable outside dist/, check_ios_dist.py, the
contract check with --library on each slice of that build, --require-compile and --require-complete, and
the smoke. test_ios.sh runs xcodebuild and the scripts; this file reads what they left and says whether
each step passed, and the summary says whether the run did.

Nothing here reaches the device: --capi refuses one before anything is built (test_ios.sh).

Commands:
  version       the library version of the tree's Common.h (NTK_VERSION_MAJOR.MINOR.PATCH)
  check-xcode   exit 2 unless `xcodebuild -version` is the Xcode the C ABI compiles with
  unit-record   one variant of IosLibraryCApiTests: its result bundle's summary, the sanitizer runtime
                each framework loads, and no sanitizer report in the logs
  step-record   one of the other steps: its exit status and its report
  summary       every step once, all passed, and the three variants ran the same number of tests

Python 3.9 (/usr/bin/python3) runs it.
"""

import argparse
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
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


def xcode_problem(xcode):
    """`xcode` is `xcodebuild -version` on one line. None for the Xcode the C ABI compiles with."""
    if re.match(r"Xcode " + re.escape(CAPI_UI_XCODE) + r"(\.\d+)? ", xcode + " "):
        return None
    return (f"--capi needs Xcode {CAPI_UI_XCODE}, not '{xcode}'. Run it as "
            f"DEVELOPER_DIR=/Applications/Xcode{CAPI_UI_XCODE}.app/Contents/Developer scripts/test_ios.sh --udid <simulator> --capi")


def sanitizer_reports(text):
    """The lines of a log that are a sanitizer's report."""
    return [line.strip() for line in text.splitlines() if SANITIZER_REPORT.search(line)]


def runtime_problems(variant, otool_by_framework):
    """What the frameworks load against what the variant needs: the variant's runtime and no other."""
    problems = []
    wanted = SANITIZER_RUNTIME.get(variant)
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


def unit_record(variant, exit_code, timed_out, summary_json, logs, otool_files):
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
    problems += runtime_problems(variant, otool)
    for label, path in logs:
        text = _read_optional(path)
        if text is None:
            problems.append(f"no {label} to read for sanitizer reports")
            continue
        reports = sanitizer_reports(text)
        if reports:
            problems.append(f"{len(reports)} sanitizer report line(s) in the {label}, first: {reports[0][:200]}")
    status = "FAIL" if problems else "PASS"
    detail = "; ".join(problems) if problems else f"{total} tests"
    return {"step": f"unit-{variant}", "status": status, "detail": detail, "tests": total}


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


def main(argv):
    parser = argparse.ArgumentParser(prog="ios_capi_runner.py")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("version")
    p.add_argument("--common-h", required=True)
    p = sub.add_parser("check-xcode")
    p.add_argument("--xcode", required=True)
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
    args = parser.parse_args(argv)
    try:
        if args.command == "version":
            print(library_version(pathlib.Path(args.common_h).read_text(encoding="utf-8")))
            return 0
        if args.command == "check-xcode":
            problem = xcode_problem(args.xcode)
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
    except (RunnerError, OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
