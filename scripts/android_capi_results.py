#!/usr/bin/env python3
"""Turn the Android C ABI's test outputs into the JSON lines of scripts/test_android.sh.

  gradle <prefix> <results dir> [<exit code>]
      The JUnit XML that a Gradle connected test task wrote (one file per device) and the logcat
      file it saved per test. Each test case becomes "<prefix>:<class>#<name>". A logcat file with
      no result is a test that ran but whose result never reached Gradle (seen twice in stage 2b,
      TB-9): it is a failed "<prefix>:<name>#resultLost". No result at all, or a nonzero exit code
      without a failed case, is a failed "<prefix>#noResult" / "<prefix>#gradle".

  smoke <prefix> <summary file>
      The PASS / FAIL / SKIP lines of scripts/run_android_capi_smoke.sh; each is "<prefix>:<item>".

Prints one JSON object per line: {"test", "result" (passed, failed or skipped), "message"}.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def emit(test, result, message=""):
    print(json.dumps({"test": test, "result": result, "message": message[:300]}, ensure_ascii=False))


def gradle(prefix, results_dir, exit_code):
    root = Path(results_dir)
    cases = []
    for path in sorted(root.rglob("*.xml")):
        try:
            suite = ET.parse(path).getroot()
        except ET.ParseError as error:
            emit(f"{prefix}#unreadable", "failed", f"{path.name}: {error}")
            continue
        for case in suite.iter("testcase"):
            failure = case.find("failure")
            if failure is None:
                failure = case.find("error")
            if failure is not None:
                result, message = "failed", (failure.text or failure.get("message") or "").strip().splitlines()[:1]
                message = message[0] if message else ""
            elif case.find("skipped") is not None:
                result, message = "skipped", ""
            else:
                result, message = "passed", ""
            cases.append((f"{case.get('classname')}#{case.get('name')}", case.get("name"), result, message))
    for test, _, result, message in cases:
        emit(f"{prefix}:{test}", result, message)
    # AGP names the logcat of a test logcat-<class>-<name with [] as _>.txt.
    reported = {re.sub(r"[\[\]]", "_", name) for _, name, _, _ in cases}
    for log in sorted(root.rglob("logcat-*.txt")):
        name = log.stem.split("-", 2)[-1] if log.stem.count("-") >= 2 else log.stem
        if name not in reported:
            emit(f"{prefix}:{name}#resultLost", "failed",
                 f"the test ran ({log.name}) but its result did not reach Gradle")
    if not cases:
        emit(f"{prefix}#noResult", "failed", f"no JUnit XML under {results_dir}")
    elif exit_code not in (None, 0) and not any(result == "failed" for _, _, result, _ in cases):
        emit(f"{prefix}#gradle", "failed", f"the Gradle task ended with {exit_code} without a failed test")


def smoke(prefix, summary):
    found = False
    for line in Path(summary).read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*(PASS|FAIL|SKIP) (.+?)(?:: (.*))?$", line)
        if m:
            found = True
            result = {"PASS": "passed", "FAIL": "failed", "SKIP": "skipped"}[m.group(1)]
            emit(f"{prefix}:{m.group(2)}", result, m.group(3) or "")
    if not found:
        emit(f"{prefix}#noResult", "failed", f"no PASS / FAIL / SKIP line in {summary}")


def main(argv):
    if len(argv) >= 3 and argv[0] == "gradle":
        exit_code = int(argv[3]) if len(argv) > 3 else None
        gradle(argv[1], argv[2], exit_code)
        return 0
    if len(argv) == 3 and argv[0] == "smoke":
        smoke(argv[1], argv[2])
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
