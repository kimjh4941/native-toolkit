#!/usr/bin/env python3
"""Check internal consistency of a native-toolkit design document.

Design documents cross-reference the same facts from a dozen sections
(operation counts, bridge endpoints, ports, error codes, task estimates).
Six review rounds on the macOS clipboard design were dominated by drift
between those copies rather than by design decisions, so the invariants are
checked here instead of by hand.

This is meant to grow into a tool shared by every feature, so each check
reports one of three states. A check that cannot find its subject reports
SKIP and never OK: a silent vacuous pass hands out false confidence, which
is worse than having no check at all.

Usage:
    python3 scripts/check_design_consistency.py <design.md> [...]

Exit status is 1 when any check fails.
"""

import re
import sys
from pathlib import Path

# Wording replaced by later revisions, per feature. The key is matched against
# the document path; a document matching no key skips the check rather than
# being declared clean against another feature's vocabulary.
RETIRED_TERMS = {
    "clipboard": [
        "request.write",
        "FilePromiseRequest.write",
        "AsyncThrowingStream",
        "pendingRelease",
        "fulfilling",
        "promiseHandleNotFound",
        "filePromiseTimedOut",
        "noMatchingItem",
        "observationAlreadyActive",
        "cancelReceipt(handle)",
    ],
}
# Lines that explain a removal are allowed to name the retired term.
RETIRED_EXEMPT = ("削除", "存在しない", "定義しない", "当時", "旧", "R6-L11", "残っていない")

ID_PREFIXES = ("IT", "BT", "CT", "PT", "OP", "RK", "DV")

# design-feature/workflow.md step 7: "1タスクを 0.5日〜1.5日程度の粒度に分割する".
# The bound belongs to the workflow rule, not to whichever document is being
# checked — an earlier revision relaxed it to 2.0 to fit the document at hand,
# which is the drift this script exists to catch.
TASK_DAYS_MIN, TASK_DAYS_MAX = 0.5, 1.5


class Report:
    def __init__(self, path):
        self.path = path
        self.notes = []
        self.failures = []

    def ok(self, name):
        self.notes.append(f"  OK   {name}")

    def skip(self, name, why):
        self.notes.append(f"  SKIP {name}: {why}")

    def check(self, condition, name, detail=""):
        if condition:
            self.ok(name)
        else:
            self.failures.append(f"  FAIL {name}: {detail}")

    def dump(self):
        print(f"== {self.path}")
        for line in self.notes + self.failures:
            print(line)
        return not self.failures


def section(text, start_pattern, stop_pattern):
    """Return the body after a heading, up to the next matching heading.

    Returns None when the heading is absent, so callers can skip rather than
    check an empty string and pass.
    """
    m = re.search(start_pattern, text, re.M)
    if not m:
        return None
    rest = text[m.end():]
    stop = re.search(stop_pattern, rest, re.M)
    return rest[:stop.start()] if stop else rest


def declared_int(text, pattern):
    m = re.search(pattern, text)
    return int(m.group(1)) if m else None


def check_ops(text, rep):
    s81 = section(text, r"^### 8\.1 ", r"^### 8\.2 ")
    s9 = section(text, r"^## 9\. ", r"^### 9\.1")
    if s81 is None or s9 is None:
        rep.skip("OP set: 8.1 == 9", "no '### 8.1' / '## 9.' section")
        rep.skip("OP count matches declaration", "no '### 8.1' / '## 9.' section")
        return
    pat = re.compile(r"\|\s*\*{0,2}(OP-\d{2})\*{0,2}\s*\|")
    a, b = set(pat.findall(s81)), set(pat.findall(s9))
    if not a and not b:
        rep.skip("OP set: 8.1 == 9", "no OP rows in either section")
    else:
        rep.check(a == b, "OP set: 8.1 == 9",
                  f"only in 8.1={sorted(a - b)} only in 9={sorted(b - a)}")
    declared = declared_int(text, r"\*\*公開 OP\*\*: OP-01〜OP-\d+ の \*\*(\d+) 件\*\*")
    if declared is None:
        rep.skip("OP count matches declaration", "no '**公開 OP**: ... **N 件**' declaration")
    else:
        rep.check(declared == len(a), "OP count matches declaration",
                  f"declared={declared} actual={len(a)}")


def check_bridge(text, rep):
    proto = section(text, r"^#### [\d.]+ 完全な C prototype", r"^#### ")
    declared = declared_int(text, r"\*\*Bridge endpoint\*\*: \*\*(\d+) 件\*\*")
    if proto is None or declared is None:
        rep.skip("Bridge endpoint count", "no C prototype section or no declaration")
        return
    n = len(re.findall(r"^void\s+\w+\s*\(", proto, re.M))
    rep.check(declared == n, "Bridge endpoint count",
              f"declared={declared} prototypes={n}")


def check_ports(text, rep):
    m = re.search(r"\*\*Port (\d+) 種\*\*（(.+?)）", text)
    if not m:
        rep.skip("Port count and definitions", "no '**Port N 種**（...）' declaration")
        return
    declared, names = int(m.group(1)), re.findall(r"`(\w+)`", m.group(2))
    rep.check(declared == len(names), "Port count matches the names listed",
              f"declared={declared} names={names}")
    missing = [n for n in names
               if not re.search(rf"^(?:public )?protocol {n}\b", text, re.M)]
    rep.check(not missing, "every named Port has a protocol definition",
              f"no 'protocol X' block for {missing}")


def check_error_codes(text, rep):
    codes = re.findall(r"^\|\s*(1\d{3})\s*\|", text, re.M)
    if not codes:
        rep.skip("error codes unique", "no 1xxx error code rows")
        rep.skip("error code bands disjoint", "no 1xxx error code rows")
        return
    dupes = sorted({c for c in codes if codes.count(c) > 1})
    rep.check(not dupes, "error codes unique", f"duplicates={dupes}")
    bands = {}
    for code in codes:
        bands.setdefault(code[:2], set()).add(code)
    rep.check(len(bands) == len({frozenset(v) for v in bands.values()}),
              "error code bands disjoint", f"bands={ {k: len(v) for k, v in bands.items()} }")


def check_tasks(text, rep):
    rows = re.findall(r"^\|\s*\*{0,2}(T-\d+\w*)\*{0,2}\s*\|([^|]*)\|\s*([\d.]+)日\s*\|([^|]*)\|",
                      text, re.M)
    names = [r[0] for r in rows]
    if not rows:
        for name in ("task ids unique",
                     f"task granularity {TASK_DAYS_MIN}-{TASK_DAYS_MAX} days",
                     "task dependencies resolve", "task estimate total"):
            rep.skip(name, "no 'T-NN | ... | N.N日 | deps' rows matched")
        return
    rep.check(len(names) == len(set(names)), "task ids unique",
              f"duplicates={sorted({n for n in names if names.count(n) > 1})}")
    bad = [(n, d) for n, _, d, _ in rows
           if not TASK_DAYS_MIN <= float(d) <= TASK_DAYS_MAX]
    rep.check(not bad, f"task granularity {TASK_DAYS_MIN}-{TASK_DAYS_MAX} days",
              f"violations={bad}")
    known = set(names)
    missing = [(name, dep) for name, _, _, deps in rows
               for dep in re.findall(r"T-\d+\w*", deps) if dep not in known]
    rep.check(not missing, "task dependencies resolve", f"missing={missing}")
    total = round(sum(float(d) for _, _, d, _ in rows), 2)
    declared = re.search(r"合計見積: 約 ([\d.]+) 日", text)
    if declared is None:
        rep.skip("task estimate total", "no '合計見積: 約 N 日' declaration")
    else:
        rep.check(abs(float(declared.group(1)) - total) < 0.01, "task estimate total",
                  f"declared={declared.group(1)} actual={total} ({len(rows)} rows)")


def check_id_order(text, rep):
    for prefix in ID_PREFIXES:
        seen = [int(m) for m in re.findall(rf"^\|\s*\*{{0,2}}{prefix}-(\d+)\*{{0,2}}\s*\|",
                                           text, re.M)]
        if len(seen) < 2:
            rep.skip(f"{prefix} ids ascending", f"{len(seen)} row(s) found")
            continue
        # Each table restarts, so only flag a decrease inside a run of >2 rows.
        drops = [(a, b) for a, b in zip(seen, seen[1:]) if b < a and b != 1]
        rep.check(not drops, f"{prefix} ids ascending", f"drops={drops[:5]}")


def check_tables(text, rep):
    bad = []
    block, header = [], None
    for lineno, line in enumerate(text.splitlines(), 1):
        if line.startswith("|"):
            # `\|` inside a cell is an escaped pipe, not a column separator.
            cols = len(re.findall(r"(?<!\\)\|", line))
            if header is None:
                header, block = cols, [(lineno, cols)]
            else:
                block.append((lineno, cols))
        else:
            if header is not None:
                bad += [(ln, c, header) for ln, c in block if c != header]
            header, block = None, []
    if header is not None:
        bad += [(ln, c, header) for ln, c in block if c != header]
    if not block and header is None and "|" not in text:
        rep.skip("markdown table column counts", "no tables")
        return
    rep.check(not bad, "markdown table column counts", f"first mismatches={bad[:5]}")


def check_retired(text, path, rep):
    key = next((k for k in RETIRED_TERMS if k in str(path).lower()), None)
    if key is None:
        rep.skip("retired wording removed",
                 f"no retired-term list for this document (known: {sorted(RETIRED_TERMS)})")
        return
    hits = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if any(k in line for k in RETIRED_EXEMPT):
            continue
        hits += [(lineno, t) for t in RETIRED_TERMS[key] if t in line]
    rep.check(not hits, "retired wording removed", f"hits={hits[:6]}")


def check_heading_order(text, rep):
    for label, pattern, key in (
        ("top-level", r"^## (\d+)\.", lambda m: (int(m),)),
        ("sub", r"^### (\d+)\.(\d+)", lambda m: (int(m[0]), int(m[1]))),
    ):
        found = re.findall(pattern, text, re.M)
        if len(found) < 2:
            rep.skip(f"{label} heading order ascending", f"{len(found)} heading(s)")
            continue
        nums = [key(m) for m in found]
        drops = [(x, y) for x, y in zip(nums, nums[1:]) if y < x]
        rep.check(not drops, f"{label} heading order ascending", f"drops={drops[:5]}")


def run(path):
    text = Path(path).read_text(encoding="utf-8")
    rep = Report(path)
    check_ops(text, rep)
    check_bridge(text, rep)
    check_ports(text, rep)
    check_error_codes(text, rep)
    check_tasks(text, rep)
    check_id_order(text, rep)
    check_tables(text, rep)
    check_retired(text, path, rep)
    check_heading_order(text, rep)
    return rep.dump()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    return 0 if all([run(p) for p in argv[1:]]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
