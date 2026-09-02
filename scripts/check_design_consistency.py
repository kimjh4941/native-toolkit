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
        # Removed in design v9 with the File Promise operations (OP-16..18 / OP-20).
        "provideFilePromise",
        "receiveFilePromises",
        "cancelReceiveFilePromises",
        "FilePromiseSnapshotting",
        "FilePromiseReceiptPolicy",
        "ClipboardReceiptCallback",
        "clipboardProvideFilePromise",
        "clipboardReceiveFilePromises",
    ],
}
# Lines that explain a removal are allowed to name the retired term.
RETIRED_EXEMPT = ("削除", "存在しない", "定義しない", "当時", "旧", "R6-L11", "残っていない")

ID_PREFIXES = ("IT", "BT", "CT", "PT", "OP", "RK", "DV")

# Where a feature's implementation lives. The design is checked against the code rather than
# against a list of words a reviewer happened to notice: a deny-list only ever knows about the
# drift that has already been found once.
SOURCE_ROOTS = {
    "clipboard": ["mac/MacLibrary", "mac/UnityMacPlugin", "mac/MacLibraryExample"],
}
# A test that asserts a type is *gone* has to name it, and it does so in a string literal:
#     for gone in ["HandleJson", "ReceiptEventJson"] { #expect(!all.contains(gone)) }
# Those literals put every deleted shape back into the corpus, so the check passed for exactly
# the drift it exists to catch (R11-H1). String literals are therefore dropped from test
# sources, while the code around them still counts: a test that uses a live type refers to it
# as code, not as text.
TEST_DIR = re.compile(r"(^|/)\w*Tests?/")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
# Prose in a comment is not an implementation. "isolation domains (…)" read as a symbol.
COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)

# Sections that legitimately name things the code does not contain: the change log, the
# out-of-scope table, and any measurement record of why something was not built.
HISTORY_HEADING = re.compile(r"^## 0(\.\d+)?\. ")
EXEMPT_SECTIONS = re.compile(r"^#{2,4} (2\.1|2\.2|7\.12)[ .]")
# Lines that state something is absent are describing the absence, not relying on it.
ABSENCE_MARKERS = ("対象外", "定義しない", "持たない", "使わない", "採用しない", "残っていない",
                   "削除", "存在しない", "当時", "旧", "v1 では不要", "レガシー",
                   "実装しない", "永久に返らない")
# Platform and build vocabulary. A design names the APIs it evaluated, including the ones it
# turned down, so an AppKit or Foundation symbol missing from the sources proves nothing about
# drift. Only project symbols are worth checking.
FOREIGN_SYMBOL = re.compile(r"^(NS|UT|CF|CG|AV|OS|DD)[A-Z]|^[A-Z0-9_]{6,}$|^with[A-Z]")

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


# A design document and the enum it describes must agree case by case. Checking only that
# codes are unique and banded misses a uniform shift: an edit that moved every row by five
# left both invariants intact while renaming every error a caller depends on.
ERROR_SOURCES = {
    "clipboard": "mac/MacLibrary/MacLibrary/Clipboard/Domain/Error/ClipboardError.swift",
}


def check_error_mapping(text, path, rep):
    key = next((k for k in ERROR_SOURCES if k in str(path).lower()), None)
    source = Path(ERROR_SOURCES[key]) if key else None
    if source is None or not source.exists():
        rep.skip("error codes match the implementation",
                 "no implementation file mapped for this document")
        return
    actual = {m.group(1): int(m.group(2)) for m in
              re.finditer(r"case \.(\w+):\s*return (\d{4})", source.read_text())}
    if not actual:
        rep.skip("error codes match the implementation", f"no 'case .x: return NNNN' in {source}")
        return
    declared = {m.group(2): int(m.group(1))
                for m in re.finditer(r"^\|\s*(\d{4})\s*\|\s*`(\w+)`\s*\|", text, re.M)}
    documented = {k: v for k, v in declared.items() if k in actual}
    if not documented:
        rep.skip("error codes match the implementation", "no documented case matches the enum")
        return
    wrong = sorted((k, v, actual[k]) for k, v in documented.items() if v != actual[k])
    rep.check(not wrong, "error codes match the implementation",
              f"documented != implemented for {wrong[:5]}")
    missing = sorted(set(actual) - set(documented))
    rep.check(not missing, "every implemented error case is documented", f"missing={missing}")
    # The other direction. Drift shows up here first: a row survives an edit that removed the
    # case it describes, and every check that only walks implementation -> design misses it
    # (R12-H4).
    invented = sorted(set(declared) - set(actual))
    rep.check(not invented, "every documented error case exists in the implementation",
              f"not implemented={invented}")


def check_error_codes(text, rep):
    codes = re.findall(r"^\|\s*(1\d{3})\s*\|", text, re.M)
    if not codes:
        rep.skip("error codes unique", "no 1xxx error code rows")
        rep.skip("error code bands disjoint", "no 1xxx error code rows")
        return
    dupes = sorted({c for c in codes if codes.count(c) > 1})
    rep.check(not dupes, "error codes unique", f"duplicates={dupes}")
    # Bridge failures are 13xx and clipboard domain failures are 15xx. The check that matters
    # is that a code stays in the band its owner declares: an earlier version compared band
    # membership to itself, which no input could ever fail (R11-M6).
    misplaced = []
    for lineno, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^\|\s*(1\d{3})\s*\|\s*`([\w.]+)`", line)
        if not m:
            continue
        code, name = int(m.group(1)), m.group(2)
        band = 1300 if name.startswith("BridgeError.") else 1500
        if not band <= code < band + 100:
            misplaced.append((lineno, name, code))
    rep.check(not misplaced, "error codes stay in their owner's band",
              f"misplaced={misplaced[:5]}")


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
    # The "## 0.x での変更点" blocks are a change log. They describe what past revisions did,
    # so naming something a later revision removed is correct there, not drift.
    in_history = False
    for lineno, line in enumerate(text.splitlines(), 1):
        if re.match(r"^## 0(\.\d+)?\. ", line):
            in_history = True
        elif re.match(r"^## [1-9]", line):
            in_history = False
        if in_history or any(k in line for k in RETIRED_EXEMPT):
            continue
        hits += [(lineno, t) for t in RETIRED_TERMS[key] if t in line]
    rep.check(not hits, "retired wording removed", f"hits={hits[:6]}")


def live_lines(text):
    """Yields (lineno, line) for the sections that state the current contract.

    The change log records what past revisions did, the out-of-scope table names platform APIs
    the design deliberately does not use, and a measurement record explains why something was
    not built. All three legitimately mention things the code does not contain.
    """
    in_history = in_exempt = False
    for lineno, line in enumerate(text.splitlines(), 1):
        if HISTORY_HEADING.match(line):
            in_history = True
        elif re.match(r"^## [1-9]", line):
            in_history = False
        if EXEMPT_SECTIONS.match(line):
            in_exempt = True
        elif re.match(r"^#{2,4} \d", line) and not EXEMPT_SECTIONS.match(line):
            in_exempt = False
        if in_history or in_exempt:
            continue
        yield lineno, line


def check_live_symbols(text, path, rep):
    """Every identifier the current contract names must exist in the implementation.

    This is what catches a removed feature whose description survives in the test design, the
    task table or the DoD. Matching on wording cannot: the rows that outlived the File Promise
    removal spoke of `inFlightCount` and `overallTimeout`, never of "file promise".
    """
    # A plan describes code that does not exist yet, so "does this symbol exist" has no meaning
    # for one; the check applies to a design of code that has been written. The exemption is
    # narrow on purpose: a blanket skip for every sample-app plan would also silence the check
    # for plans whose code *has* been written, which is how an exclusion becomes an excuse
    # (R-S3-M7). A plan opts in by saying so in its own front matter.
    if "PLANNED_SYMBOLS_EXEMPT" in text:
        rep.skip("named symbols exist in the implementation",
                 "the document declares PLANNED_SYMBOLS_EXEMPT: it names code not yet written")
        return
    key = next((k for k in SOURCE_ROOTS if k in str(path).lower()), None)
    if key is None:
        rep.skip("named symbols exist in the implementation", "no source root for this document")
        return
    roots = [Path(r) for r in SOURCE_ROOTS[key]]
    if not all(r.exists() for r in roots):
        rep.skip("named symbols exist in the implementation", f"missing source root in {roots}")
        return
    corpus = []
    for root in roots:
        for suffix in ("*.swift", "*.h", "*.m"):
            for f in root.rglob(suffix):
                if "/Build/" in str(f):
                    continue
                body = f.read_text(encoding="utf-8", errors="ignore")
                if TEST_DIR.search(str(f)):
                    body = STRING_LITERAL.sub('""', body)
                corpus.append(COMMENT.sub("", body))
    # Whole identifiers, not raw text. `ident in corpus` was a substring test, so any prefix of
    # a real symbol passed: `ScopeResult` rode in on `ScopeResultJson` (R12-H4).
    symbols = set(re.findall(r"\b\w+\b", "\n".join(corpus)))
    if not symbols:
        rep.skip("named symbols exist in the implementation", "no sources read")
        return

    hits = []
    for lineno, line in live_lines(text):
        if any(marker in line for marker in ABSENCE_MARKERS):
            continue
        for ident in re.findall(r"`(\w{6,})`", line):
            if FOREIGN_SYMBOL.match(ident) or ident in symbols:
                continue
            hits.append((lineno, ident))
    rep.check(not hits, "named symbols exist in the implementation", f"hits={hits[:8]}")


def check_live_ids(text, rep):
    """Every test or operation ID the current contract names must exist in its table.

    Ranges are the blind spot this closes. `IT-21〜IT-53` reads as a single token, so a symbol
    or wording scan never sees the 30 IDs it silently requires — including the ones a later
    revision deleted.
    """
    # A row's first cell can define more than one ID: "| RK-01 / RK-02 |", "| F-01〜F-07 |".
    defined = {prefix: set() for prefix in ID_PREFIXES}
    for row in re.findall(r"^\|([^|]*)\|", text, re.M):
        for prefix in ID_PREFIXES:
            for a, b in re.findall(rf"{prefix}-(\d+)〜(?:{prefix}-)?(\d+)", row):
                defined[prefix] |= set(range(int(a), int(b) + 1))
            defined[prefix] |= {int(n) for n in
                                re.findall(rf"(?<![\w-]){prefix}-(\d+)(?![\d〜])", row)}
    if not any(defined.values()):
        rep.skip("referenced IDs exist in their tables", "no ID rows found")
        return

    referenced = {}
    for lineno, line in live_lines(text):
        if any(marker in line for marker in ABSENCE_MARKERS):
            continue
        # A row defines its own ID; only references elsewhere on the line are claims.
        row = re.match(r"^\|\s*\*{0,2}([A-Z]{2})-(\d+)\*{0,2}\s*\|", line)
        body = line[row.end():] if row else line
        for prefix in ID_PREFIXES:
            if not defined[prefix]:
                continue
            for a, b in re.findall(rf"{prefix}-(\d+)〜(?:{prefix}-)?(\d+)", body):
                for n in range(int(a), int(b) + 1):
                    referenced.setdefault((prefix, n), lineno)
            for n in re.findall(rf"(?<![\w-]){prefix}-(\d+)(?![\d〜])", body):
                referenced.setdefault((prefix, int(n)), lineno)

    missing = sorted((f"{p}-{n:02d}", ln) for (p, n), ln in referenced.items()
                     if n not in defined[p])
    rep.check(not missing, "referenced IDs exist in their tables", f"missing={missing[:8]}")


def check_live_code_blocks(text, rep):
    """Type names inside the schema samples must match the inventory above them.

    The samples are fenced code, so the identifier scan skips them: a shape deleted from the
    table can survive as a worked example that Unity authors would copy.
    """
    # Only the inventory table counts. Taking every backticked name would include the notes
    # that say a shape was deleted, which is how a stale sample stayed "in the inventory".
    rows = re.findall(r"^\|\s*(?:入力専用|入出力共用|出力専用|イベント)\s*\|([^|]*)\|", text, re.M)
    inventory = {n for row in rows for n in re.findall(r"`?\*{0,2}(\w+Json)\*{0,2}`?", row)}
    if not inventory:
        rep.skip("schema samples match the inventory", "no JSON inventory table found")
        return
    sampled, in_fence = {}, False
    for lineno, line in live_lines(text):
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            continue
        for name in re.findall(r"//\s*(\w+Json)\b", line):
            sampled.setdefault(name, lineno)
    orphan = sorted((n, ln) for n, ln in sampled.items() if n not in inventory)
    rep.check(not orphan, "schema samples match the inventory", f"not in the inventory: {orphan[:6]}")


def check_live_counts(text, rep):
    """Counts quoted in the current contract must match the document's own declarations.

    The declarations at the top are already checked against the sections that define them, so
    tying prose figures to the same numbers keeps a superseded count from surviving in a test
    table or a task row.
    """
    canonical = {}
    m = re.search(r"\*\*Bridge endpoint\*\*: \*\*(\d+) 件\*\*", text)
    if m:
        canonical["endpoint"] = int(m.group(1))
    m = re.search(r"実体 \*\*(\d+) 型\*\*", text)
    if m:
        canonical["json"] = int(m.group(1))
    if not canonical:
        rep.skip("quoted counts match the declarations", "no declaration to compare against")
        return

    hits = []
    for lineno, line in live_lines(text):
        if any(marker in line for marker in ABSENCE_MARKERS):
            continue
        if "endpoint" in canonical:
            for n in re.findall(r"全 \*{0,2}(\d+) endpoint", line):
                if int(n) != canonical["endpoint"]:
                    hits.append((lineno, f"{n} endpoint", canonical["endpoint"]))
        if "json" in canonical:
            for n in re.findall(r"実体 \*{0,2}(\d+) (?:JSON )?型", line):
                if int(n) != canonical["json"]:
                    hits.append((lineno, f"実体 {n} 型", canonical["json"]))
    rep.check(not hits, "quoted counts match the declarations", f"hits={hits[:6]}")


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
    check_error_mapping(text, path, rep)
    check_tasks(text, rep)
    check_id_order(text, rep)
    check_tables(text, rep)
    check_retired(text, path, rep)
    check_live_symbols(text, path, rep)
    check_live_counts(text, rep)
    check_live_ids(text, rep)
    check_live_code_blocks(text, rep)
    check_heading_order(text, rep)
    return rep.dump()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    return 0 if all([run(p) for p in argv[1:]]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
