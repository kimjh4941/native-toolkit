#!/usr/bin/env python3
"""Check the Android C ABI against its design (Android C ABI design part 2, 12.3).

Both sides of every comparison are read from source, never from a list kept
here, so neither can drift without the other noticing:

  functions   the public headers, the table of section 8.2 and Appendix A
              all name the same functions, as many as 8.2 says.
  signatures  every declaration in the headers - function, callback type,
              struct, enum value and typedef - against Appendix A, and no
              preprocessor line a header may not have (an #if would hide a
              declaration from this reading).
  operations  the rows of 8.1 against those of chapter 9, and the C function
              each names against Appendix A.
  kotlin      the Kotlin entry each row of 8.1 calls exists in
              android_library (AP-1).
  behaviours  every behaviour of chapter 10 has operations of 8.1, the rows
              of each kind are as many as README chapter 6 numbers, each
              row's kind agrees with its functions (a completion callback, a
              listener, or neither) and with chapter 9, and every function
              that takes a callback belongs to a row.
  values      the error enumerations against the tables of chapter 11, the
              shared meanings of 0 to 5 (AP-12), and the Kotlin declaration
              order that 11.3 and 11.4 follow.
  names       every function, type and constant follows the naming rules.
  ascii       the public headers are ASCII only.
  common      the Android Common.h against the Windows one (part 1, 5.2).
  symbols     after a build, the ntk_* symbols libntk.so exports are those of
              8.2, with JNI_OnLoad and nothing else (AP-15).

A file that cannot be read fails its check (R-30). Two checks run only when
asked, and say so: the headers come with stage 2b, so --design-only reads
Appendix A in their place until then (and fails once a header exists);
symbols needs a built library. An argument this script does not know is a
usage error, so a misspelt option cannot turn a check into a SKIP.

What every OS checks the same way lives in c_abi_contract_common.py.

Usage:
    python3 scripts/check_c_abi_contract_android.py [--root <tree>] [--design-only]
                                                    [--library <libntk.so> [--nm <llvm-nm>]]

--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.

Exit status is 1 when any check fails.
"""

import glob
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import c_abi_contract_common as common
from c_abi_contract_common import Report, appendix_headers, backticked, declarations, merged, op_range, table_rows

ROOT = Path(__file__).resolve().parent.parent

DESIGN = "artifact/topics/android-c-abi/designs/2026-10-05-android-c-abi-c-abi-design-part2.md"
README = "artifact/topics/android-c-abi/README.md"
KOTLIN = "android/android_library/src/main/java"
INCLUDE = "android/android_library_capi/src/main/cpp/include/NativeToolkitC"
HEADERS = {name: f"{INCLUDE}/{name}" for name in
           ("Common.h", "Android.h", "Clipboard.h", "Dialog.h", "Notification.h", "Share.h")}
WINDOWS_COMMON = "windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h"
# The NDK the build is pinned to (part 1, AC-12). Preferred when several are installed.
NDK_VERSION = "30.0.16248370"

# The prefix every function of a header starts with. Common.h holds what
# belongs to no feature.
FEATURE_OF = {"Android.h": "android", "Clipboard.h": "clipboard", "Dialog.h": "dialog",
              "Notification.h": "notification", "Share.h": "share"}
COMMON_FUNCTIONS = re.compile(r"^ntk_(version|last_system_code|string_\w+|bytes_\w+|string_list_\w+)$")
# Where the chapter 11 table of each error enumeration is.
ERROR_TABLES = {
    "NTK_DIALOG_ERROR_": "### 11.1",
    "NTK_NOTIFICATION_ERROR_": "### 11.2",
    "NTK_CLIPBOARD_ERROR_": "### 11.3",
    "NTK_SHARE_ERROR_": "### 11.4",
    "NTK_ANDROID_ERROR_": "### 11.5",
}
# The errors whose 0 to 5 mean the same in every feature (AP-12). 11.5 keeps
# the values part 1 gave it.
SHARED_ERRORS = ("NTK_DIALOG_ERROR_", "NTK_NOTIFICATION_ERROR_", "NTK_CLIPBOARD_ERROR_", "NTK_SHARE_ERROR_")
# The tables whose Kotlin column follows a Kotlin declaration order: the
# heading, the Kotlin type, and the members the table maps elsewhere (11.3:
# ClipboardErrorCode.UNKNOWN is the shared 4).
KOTLIN_ORDER = {
    "### 11.3": ("ClipboardErrorCode", {"UNKNOWN"}),
    "### 11.4": ("ShareDomainError", set()),
}
# The kinds of chapter 10 (part 1, chapter 8), and which kinds each ID allows.
SYNC, POSTED, COMPLETION, EVENT, REGISTRATION = (
    "同期の結果", "受け付けだけ（main に積む）", "受け付けた後の完了", "イベント", "登録と解除")
KINDS_OF = {
    "BH": {SYNC, POSTED, COMPLETION},
    "EV": {EVENT},
    "RG": {REGISTRATION, POSTED},
    "PR": {COMPLETION},
}
# Constants only the Windows Common.h may define (part 1, 5.2).
WINDOWS_ONLY = r"^NTK_SYSTEM_CODE_\w+$"

USAGE = ("usage: check_c_abi_contract_android.py [--root <tree>] [--design-only] "
         "[--library <libntk.so> [--nm <llvm-nm>]]")


def at(fragment):
    return ROOT / fragment


def read(fragment, rep, check_name):
    return common.read(ROOT, fragment, rep, check_name)


def find_ndk_tool(name, given=None, search_path=True):
    """A tool of the NDK's LLVM (clang, llvm-nm), or None. An explicit path is
    returned as given, for the caller to fail on if it does not exist. Without
    one: PATH (unless search_path is false, for a tool whose host build would
    not do, such as clang without the Android sysroot), then ANDROID_NDK_HOME /
    ANDROID_NDK_ROOT, then the SDK's ndk/ folder, preferring the pinned NDK."""
    if given:
        return given
    found = shutil.which(name) if search_path else None
    if found:
        return found
    roots = [os.environ.get("ANDROID_NDK_HOME"), os.environ.get("ANDROID_NDK_ROOT")]
    sdk = os.environ.get("ANDROID_HOME") or os.path.expanduser("~/Library/Android/sdk")
    roots += [f"{sdk}/ndk/{NDK_VERSION}"] + sorted(glob.glob(f"{sdk}/ndk/*"), reverse=True)
    for home in roots:
        if home:
            matches = sorted(glob.glob(f"{home}/toolchains/llvm/prebuilt/*/bin/{name}"))
            if matches:
                return matches[-1]
    return None


# ---------------------------------------------------------------------------
# Reading the design and the Kotlin sources
# ---------------------------------------------------------------------------

def operations(design):
    """OP -> (Kotlin entry or None, C function) from 8.1."""
    table = {}
    for cells in table_rows(design, "### 8.1"):
        if len(cells) < 3 or not cells[0].startswith("OP-"):
            continue
        kotlin = backticked(cells[1])
        c = backticked(cells[2])
        if c:
            table[cells[0]] = (kotlin[0] if kotlin else None, c[0].split("(")[0].strip())
    return table


def chapter_9(design):
    """OP -> its 'C ABI（Bridge）' cell of chapter 9."""
    return {cells[0]: cells[3] for cells in table_rows(design, "## 9.")
            if len(cells) > 3 and cells[0].startswith("OP-")}


def kotlin_sources():
    """path -> text with comments removed: a declaration in a comment is not one."""
    return {path: common.strip_comments(path.read_text(encoding="utf-8"))
            for path in sorted(at(KOTLIN).rglob("*.kt"))}


def kotlin_declarations(sources, name):
    """(text, index) of every class, object or interface declared as name."""
    pattern = re.compile(r"^[ \t]*(?:[a-z]+\s+)*(?:class|object|interface)\s+" + re.escape(name) + r"\b", re.M)
    return [(text, match.start()) for text in sources.values() for match in pattern.finditer(text)]


def members(text, start):
    """The text at the top level of the body of the declaration at start: the
    members of that type, with every nested body (functions, nested types)
    removed."""
    index, parens = start, 0
    while index < len(text):
        char = text[index]
        if char == "(":
            parens += 1
        elif char == ")":
            parens -= 1
        elif char == "{" and parens == 0:
            break
        elif char == "\n" and parens == 0 and re.match(r"\s*(?:[a-z]+\s+)*(?:class|object|interface|fun|val)\b",
                                                         text[index + 1:]):
            return ""                     # a declaration without a body
        index += 1
    depth, kept = 0, []
    for char in text[index:]:
        if char == "{":
            depth += 1
            if depth == 1:
                continue
        elif char == "}":
            depth -= 1
            if depth == 0:
                break
        if depth == 1:
            kept.append(char)
    return "".join(kept)


def kotlin_type(sources, name, problems):
    """The members of the one type declared as name, or None and a problem."""
    found = kotlin_declarations(sources, name)
    if not found:
        problems.append(f"no Kotlin declares {name}")
        return None
    if len(found) > 1:
        problems.append(f"{len(found)} Kotlin types are named {name}")
        return None
    return members(*found[0])


def kotlin_order(sources, name, problems):
    """The entries of an enum class, or the subclasses of a sealed class
    declared in its file, in declaration order."""
    found = kotlin_declarations(sources, name)
    if len(found) != 1:
        problems.append(f"{len(found)} Kotlin types are named {name}")
        return None
    text, start = found[0]
    body = members(text, start)
    if re.search(r"\benum\s+class\s+" + re.escape(name) + r"\b", text):
        # The entries end at the first ; outside parentheses; each is a name,
        # perhaps with arguments over several lines.
        entries, depth, current = [], 0, []
        for char in body:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            if depth == 0 and char in ",;":
                entries.append("".join(current))
                current = []
                if char == ";":
                    break
                continue
            current.append(char)
        else:
            entries.append("".join(current))
        return [m.group(1) for entry in entries for m in [re.match(r"\s*([A-Z][A-Z0-9_]*)\b", entry)] if m]
    pattern = r"\b(?:data\s+)?(?:class|object)\s+(\w+)\b[^{};]*?:\s*" + re.escape(name) + r"\(\)"
    return re.findall(pattern, text, re.S)


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def check_functions(design, expected, headers, rep):
    name = "functions: headers, 8.2 and Appendix A agree"
    ops = {op: c for op, (_, c) in operations(design).items()}
    in_8_2, total, problems = common.section_8_2(design, ops)
    listed = set(in_8_2)
    if len(in_8_2) != len(listed):
        problems.append("8.2 names a function twice")
    in_appendix = set(expected["function"])
    sides = [("Appendix A", in_appendix)]
    if headers is not None:
        sides.append(("the headers", set(merged(headers)["function"])))
    else:
        name += " (headers skipped: --design-only)"
    for label, other in sides:
        if other - listed:
            problems.append(f"{label} but not 8.2: {', '.join(sorted(other - listed))}")
        if listed - other:
            problems.append(f"8.2 but not {label}: {', '.join(sorted(listed - other))}")
    heading = re.search(r"^### 8\.2 [^\n]*（(\d+)）", design, re.M)
    if total is None:
        problems.append("8.2 has no total")
    elif total != len(listed):
        problems.append(f"8.2 says {total} in all but names {len(listed)}")
    if heading and total is not None and int(heading.group(1)) != total:
        problems.append(f"the heading of 8.2 says {heading.group(1)}, its total {total}")
    if not listed:
        problems.append("8.2 names nothing")
    rep.check(not problems, f"{name} ({len(listed)} functions)", "; ".join(problems))
    return listed


def check_operations(design, expected, rep):
    name = "operations: 8.1, chapter 9 and Appendix A agree"
    ops = operations(design)
    in_9 = set(chapter_9(design))
    problems = []
    numbers = sorted(int(op[3:]) for op in ops)
    if numbers != list(range(1, len(numbers) + 1)):
        problems.append("the operations of 8.1 are not OP-01 to OP-N without gaps")
    if set(ops) != in_9:
        problems.append(f"8.1 and chapter 9 list different operations: {', '.join(sorted(set(ops) ^ in_9))}")
    for op, (_, function) in sorted(ops.items()):
        if function not in expected["function"]:
            problems.append(f"{op} names {function}, which Appendix A does not declare")
    rep.check(not problems and ops, f"{name} ({len(ops)} operations)", "; ".join(problems) or "8.1 is empty")


def check_kotlin(design, sources, rep):
    name = "kotlin: every Kotlin entry of 8.1 exists"
    problems, compared = [], 0
    for op, (entry, _) in sorted(operations(design).items()):
        if entry is None:
            continue
        parts = entry.split(".")
        if len(parts) < 2:
            problems.append(f"{op}: '{entry}' is not Type.member")
            continue
        found = []
        body = kotlin_type(sources, parts[-2], found)
        if body is None:
            problems.extend(f"{op}: {p}" for p in found)
            continue
        member = re.escape(parts[-1])
        if not re.search(r"(?:^|\s)(?:fun(?:\s+<[^>]*>)?|val|var)\s+" + member + r"\b", body):
            problems.append(f"{op}: {parts[-2]} has no member {parts[-1]}")
            continue
        compared += 1
    rep.check(not problems and compared > 0, f"{name} ({compared} entries)", "; ".join(problems) or "nothing was compared")


def takes_callback(signature):
    """Whether a declaration takes a callback of its own and a release."""
    callbacks = set(re.findall(r"\bntk_\w+_fn\b", signature))
    return "ntk_release_fn" in callbacks and len(callbacks) > 1


def is_listener(function, signature):
    return bool(re.fullmatch(r"ntk_\w+_add_\w+_listener", function)) and takes_callback(signature)


def readme_ranges(readme):
    """ID prefix -> how many README chapter 6 numbers ('BH-01〜BH-45', 'PR-01')."""
    counts = {}
    for prefix, last in re.findall(r"\b(BH|EV|RG|PR)-01〜(?:BH|EV|RG|PR)-(\d+)", readme or ""):
        counts[prefix] = int(last)
    for prefix in re.findall(r"\b(BH|EV|RG|PR)-01\b(?!〜)", readme or ""):
        counts.setdefault(prefix, 1)
    return counts


def check_behaviours(design, readme, expected, rep):
    name = "behaviours: chapter 10 maps every behaviour to operations of 8.1"
    ops = operations(design)
    cells_9 = chapter_9(design)
    functions = expected["function"]
    rows = [cells for cells in table_rows(design, "## 10.") if cells and re.match(r"^[A-Z]+-\d+$", cells[0])]
    problems, by_prefix, used = [], {}, {COMPLETION: set(), EVENT: set(), REGISTRATION: set()}
    for prefix in KINDS_OF:
        numbers = [int(cells[0].split("-")[1]) for cells in rows if cells[0].startswith(prefix + "-")]
        by_prefix[prefix] = len(numbers)
        if numbers != list(range(1, len(numbers) + 1)):
            problems.append(f"the {prefix} rows are not {prefix}-01 to {prefix}-N without gaps")
    expected_counts = readme_ranges(readme)
    if set(expected_counts) != set(KINDS_OF):
        problems.append(f"README chapter 6 does not number every kind: {expected_counts}")
    for prefix, count in sorted(expected_counts.items()):
        if by_prefix.get(prefix) != count:
            problems.append(f"chapter 10 has {by_prefix.get(prefix)} {prefix} rows, README chapter 6 numbers {count}")
    total = re.search(r"^\| 計 \| (\d+) \| (\d+) \|", readme or "", re.M)
    if total is None:
        problems.append("README chapter 6 has no total row")
    elif by_prefix.get("BH") != int(total.group(2)):
        problems.append(f"chapter 10 has {by_prefix.get('BH')} operations, README chapter 6 counts {total.group(2)}")

    for cells in rows:
        prefix = cells[0].split("-")[0]
        if prefix not in KINDS_OF:
            problems.append(f"{cells[0]} is not one of {', '.join(KINDS_OF)}")
            continue
        if len(cells) < 6:
            problems.append(f"{cells[0]} has {len(cells)} columns, not 6")
            continue
        kind = cells[3]
        if kind not in KINDS_OF[prefix]:
            problems.append(f"{cells[0]}: '{kind}' is not a kind a {prefix} row can have")
            continue
        named = op_range(cells[5])
        if not named:
            problems.append(f"{cells[0]} names no operation")
            continue
        missing = [op for op in named if op not in ops]
        if missing:
            problems.append(f"{cells[0]} names {', '.join(missing)}, which 8.1 lacks")
            continue
        names = {op: ops[op][1] for op in named}
        listeners = [op for op, f in names.items() if is_listener(f, functions.get(f, ""))]
        completions = [op for op, f in names.items()
                       if takes_callback(functions.get(f, "")) and op not in listeners]
        if kind == SYNC:
            wrong = [op for op in named if listeners or completions
                     or not cells_9.get(op, "").startswith("同期") or "main に積む" in cells_9.get(op, "")]
            if wrong:
                problems.append(f"{cells[0]} is '{kind}' but {', '.join(wrong)} take a callback or are not 同期 in chapter 9")
        elif kind == POSTED:
            wrong = [op for op in named if listeners or completions or "main に積む" not in cells_9.get(op, "")]
            if wrong:
                problems.append(f"{cells[0]} is '{kind}' but {', '.join(wrong)} take a callback or chapter 9 does not post them")
        elif kind == COMPLETION:
            # The operation and, at most, the function that cancels it (PR-01: OP-38 and OP-39).
            others = [op for op in named if op not in completions and "_cancel" not in names[op]]
            if not completions or listeners or others:
                problems.append(f"{cells[0]} is '{kind}' but its functions are not completions "
                                f"and their cancels: {', '.join(others or listeners) or 'no completion'}")
        elif kind == EVENT:
            if not listeners or len(listeners) != len(named):
                problems.append(f"{cells[0]} is '{kind}' but not every function adds a listener")
        elif kind == REGISTRATION:
            others = [op for op in named if op not in listeners and not names[op].endswith("_listener_remove")]
            if not listeners or others:
                problems.append(f"{cells[0]} is '{kind}' but its functions are not a listener and its removal")
        if kind in used:
            used[kind] |= set(names.values())

    # Every function that takes a callback belongs to a row of its kind.
    for function, signature in sorted(functions.items()):
        if is_listener(function, signature):
            if function not in used[EVENT] | used[REGISTRATION]:
                problems.append(f"{function} adds a listener but no event or registration row names it")
        elif takes_callback(signature) and function not in used[COMPLETION]:
            problems.append(f"{function} takes a completion callback but no completion row names it")

    kinds = {kind: sum(1 for cells in rows if len(cells) > 3 and cells[3] == kind)
             for kind in (SYNC, POSTED, COMPLETION, EVENT, REGISTRATION)}
    summary = ", ".join(f"{prefix} {count}" for prefix, count in by_prefix.items())
    derived = ", ".join(f"{kind} {count}" for kind, count in kinds.items())
    rep.check(not problems and rows, f"{name} ({summary}; {derived})", "; ".join(problems) or "chapter 10 is empty")


def check_values(design, values, sources, rep):
    problems = common.error_table_problems(design, values, ERROR_TABLES)
    rep.check(not problems, "values: the errors match the tables of chapter 11", "; ".join(problems))

    name = "values: 0 to 5 mean the same in every feature (AP-12)"
    problems = []
    shared = {}
    for cells in table_rows(design, "## 11."):
        if len(cells) >= 2 and cells[0].isdigit():
            for suffix in backticked(cells[1]):
                shared[suffix] = int(cells[0])
    if sorted(shared.values()) != list(range(6)):
        problems.append(f"the table of chapter 11 does not give 0 to 5 once each: {shared}")
    for prefix in SHARED_ERRORS:
        mine = {k[len(prefix):]: v for k, v in values.items() if k.startswith(prefix) and v < 6}
        if mine != shared:
            problems.append(f"{prefix}0..5 are {mine}, chapter 11 says {shared}")
    rep.check(not problems, name, "; ".join(problems))

    name = "values: 11.3 and 11.4 follow the Kotlin declaration order"
    problems = []
    for heading, (kotlin_name, elsewhere) in sorted(KOTLIN_ORDER.items()):
        order = kotlin_order(sources, kotlin_name, problems)
        if order is None:
            continue
        rows = [cells for cells in table_rows(design, heading) if len(cells) >= 3 and cells[0].isdigit()]
        cited = [m.group(1) for cells in sorted(rows, key=lambda c: int(c[0]))
                 for m in [re.search(re.escape(kotlin_name) + r"\.(\w+)", cells[2])] if m]
        wanted = [m for m in order if m not in elsewhere]
        if not wanted:
            problems.append(f"{kotlin_name} declares nothing this check could read")
        elif cited != wanted:
            problems.append(f"{heading} cites {cited}, {kotlin_name} declares {wanted}")
    rep.check(not problems, name, "; ".join(problems))


def check_ascii(texts, rep, label):
    problems = [] if texts else ["nothing was read"]
    for header, text in texts.items():
        problems.extend(common.non_ascii_lines(header, text.encode("utf-8")))
    rep.check(not problems, f"ascii: {label} are ASCII only", ", ".join(problems))


def check_common(android_common, rep):
    name = "common: the Android Common.h shares the Windows declarations (part 1, 5.2)"
    windows = read(WINDOWS_COMMON, rep, name)
    if windows is None:
        return
    if android_common is None:
        rep.check(False, name, "no Android Common.h")
        return
    problems = common.common_header_problems(windows, android_common, WINDOWS_ONLY)
    rep.check(not problems, name, "; ".join(problems))


def exported_symbols(output):
    """The names in llvm-nm output, without symbol versions (name@@VERSION)."""
    names = set()
    for line in output.splitlines():
        line = line.strip()
        if not line or line.endswith(":"):
            continue                      # a blank line or a file heading
        names.add(line.split()[-1].split("@")[0])
    return names


def check_symbols(library, nm, listed, rep):
    name = "symbols: libntk.so exports 8.2 and JNI_OnLoad only (AP-15)"
    if library is None:
        rep.skip(name, "no --library (run after the build)")
        return
    if not Path(library).exists():
        rep.check(False, name, f"cannot read {library}")
        return
    tool = find_ndk_tool("llvm-nm", nm)
    if tool is None:
        rep.check(False, name, "no llvm-nm (give --nm or set ANDROID_NDK_HOME)")
        return
    if not Path(tool).exists():
        rep.check(False, name, f"cannot run {tool}")
        return
    try:
        finished = subprocess.run([tool, "-D", "--defined-only", str(library)], capture_output=True, text=True)
    except OSError as error:
        rep.check(False, name, f"cannot run {tool}: {error}")
        return
    if finished.returncode != 0:
        rep.check(False, name, f"{tool} failed: {finished.stderr.strip()}")
        return
    exported = exported_symbols(finished.stdout)
    wanted = set(listed) | {"JNI_OnLoad"}
    problems = []
    if exported - wanted:
        problems.append(f"exported but not in 8.2: {', '.join(sorted(exported - wanted))}")
    if wanted - exported:
        problems.append(f"8.2 but not exported: {', '.join(sorted(wanted - exported))}")
    rep.check(not problems, f"{name} ({len(exported)} symbols)", "; ".join(problems))


def parse_arguments(argv):
    """{option: value} for the options with a value, and the flags; None on a usage error."""
    with_value = {"--root", "--library", "--nm"}
    flags = {"--design-only"}
    parsed, rest = {}, list(argv)
    while rest:
        argument = rest.pop(0)
        if argument in with_value:
            if not rest or rest[0].startswith("--"):
                print(f"{argument} needs a value\n{USAGE}", file=sys.stderr)
                return None
            parsed[argument] = rest.pop(0)
        elif argument in flags:
            parsed[argument] = True
        else:
            print(f"unknown argument {argument}\n{USAGE}", file=sys.stderr)
            return None
    return parsed


def main(argv):
    global ROOT
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parsed = parse_arguments(argv[1:])
    if parsed is None:
        return 2
    if "--root" in parsed:
        ROOT = Path(parsed["--root"]).resolve()
    library = parsed.get("--library")
    nm = parsed.get("--nm")
    design_only = parsed.get("--design-only", False)

    rep = Report("C ABI contract (Android)")
    design = read(DESIGN, rep, "the C ABI design")
    readme = read(README, rep, "the README")
    if design is None:
        return 0 if rep.dump() else 1
    appendix = appendix_headers(design)
    if not appendix:
        rep.check(False, "Appendix A", "no '### A.N `NativeToolkitC/X.h`' code blocks")
        return 0 if rep.dump() else 1
    expected = merged({h: declarations(code) for h, code in appendix.items()})
    if not at(KOTLIN).is_dir():
        rep.check(False, "the Kotlin sources", f"cannot read {KOTLIN}")

    texts = None
    if design_only:
        present = [label for label, fragment in HEADERS.items() if at(fragment).exists()]
        rep.check(not present, "design only: no public header exists yet",
                  f"{', '.join(present)} exist; drop --design-only so they are checked")
    else:
        texts = {}
        for label, fragment in HEADERS.items():
            text = read(fragment, rep, f"the public header {label}")
            if text is not None:
                texts[label] = text
    headers = {h: declarations(t) for h, t in texts.items()} if texts is not None else None

    listed = check_functions(design, expected, headers, rep)
    if headers is None:
        rep.skip("signatures: the headers declare what Appendix A does", "--design-only")
    else:
        problems = [p for label, text in texts.items() for p in common.directive_problems(label, text)]
        common.check_signatures(expected, merged(headers), rep, problems)
    check_operations(design, expected, rep)
    sources = kotlin_sources()
    check_kotlin(design, sources, rep)
    check_behaviours(design, readme, expected, rep)
    values = merged(headers)["value"] if headers is not None else expected["value"]
    check_values(design, values, sources, rep)
    named = headers if headers is not None else {h: declarations(c) for h, c in appendix.items()}
    common.check_names(named, FEATURE_OF, COMMON_FUNCTIONS, rep,
                       "names: every function, type and constant follows the naming rules")
    if texts is not None:
        check_ascii(texts, rep, "the public headers")
    else:
        check_ascii(appendix, rep, "the headers of Appendix A")
    check_common(texts.get("Common.h") if texts is not None else appendix.get("Common.h"), rep)
    check_symbols(library, nm, listed, rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
