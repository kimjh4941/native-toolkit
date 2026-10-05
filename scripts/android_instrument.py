#!/usr/bin/env python3
"""Run one `am instrument -w -r` and turn its output into per-test results.

Used by scripts/test_android.sh (android-c-abi UI test design, section 8). Prints one JSON object
per test to stdout and the raw instrument output to the file given with --raw. A run that crashed,
timed out, ran zero tests, or left a started test without an end is reported as a failed
pseudo-test named `<class>#<problem>`.

Status codes of `INSTRUMENTATION_STATUS_CODE`: 1 start, 0 ok, -1 error, -2 failure, -3 ignored,
-4 assumption failure.
"""

import argparse
import json
import re
import subprocess
import sys

RESULTS = {"0": "passed", "-1": "failed", "-2": "failed", "-3": "skipped", "-4": "skipped"}


def parse(output: str, target: str) -> list:
    results = []
    status = {}
    started = None
    final_code = None
    crashed = False
    for line in output.splitlines():
        m = re.match(r"INSTRUMENTATION_STATUS: (\w+)=(.*)", line)
        if m:
            status[m.group(1)] = m.group(2)
            continue
        m = re.match(r"INSTRUMENTATION_STATUS_CODE: (-?\d+)", line)
        if m:
            code = m.group(1)
            name = f"{status.get('class', '?')}#{status.get('test', '?')}"
            if code == "1":
                started = name
            else:
                stack = status.get("stack", "")
                results.append({
                    "test": name,
                    "result": RESULTS.get(code, "failed"),
                    "message": stack.splitlines()[0][:300] if stack else "",
                })
                started = None
            status = {}
            continue
        m = re.match(r"INSTRUMENTATION_CODE: (-?\d+)", line)
        if m:
            final_code = m.group(1)
        if "shortMsg=Process crashed" in line or line.startswith("INSTRUMENTATION_ABORTED"):
            crashed = True
    problems = []
    if started:
        problems.append(("unfinished", f"{started} started but did not finish"))
    if crashed:
        problems.append(("crashed", "the instrumentation process crashed or was aborted"))
    if final_code is None:
        problems.append(("noFinalCode", "no INSTRUMENTATION_CODE line"))
    if not results and not problems:
        problems.append(("zeroTests", "no test ran"))
    for key, message in problems:
        results.append({"test": f"{target}#{key}", "result": "failed", "message": message})
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--adb", required=True)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--runner", required=True, help="<test package>/<runner class>")
    parser.add_argument("--target", required=True, help="class or class#method, fully qualified (or a package with --package)")
    parser.add_argument("--package", action="store_true", help="treat --target as a package")
    parser.add_argument("--not-annotation", action="append", default=[])
    parser.add_argument("--not-class", action="append", default=[], help="a fully qualified class to leave out")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--raw", required=True)
    args = parser.parse_args()

    command = [args.adb, "-s", args.serial, "shell", "am", "instrument", "-w", "-r", "--no-window-animation",
               "-e", "package" if args.package else "class", args.target]
    for annotation in args.not_annotation:
        command += ["-e", "notAnnotation", annotation]
    if args.not_class:
        command += ["-e", "notClass", ",".join(args.not_class)]
    command.append(args.runner)
    try:
        output = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout).stdout
        timed_out = False
    except subprocess.TimeoutExpired as e:
        output = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        timed_out = True
    with open(args.raw, "w", encoding="utf-8") as raw:
        raw.write(output)
    results = parse(output, args.target)
    if timed_out:
        results.append({"test": f"{args.target}#timeout", "result": "failed", "message": f"timed out after {args.timeout} s"})
    for result in results:
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
