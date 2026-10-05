#!/usr/bin/env python3
"""Check the Android C ABI against its design (Android C ABI design part 2, 12.3).

Both sides of every comparison are read from source, never from a list kept
here, so neither can drift without the other noticing:

  functions   the public headers, the table of section 8.2 and Appendix A
              all name the same functions, as many as 8.2 says.
  signatures  every declaration in the headers - function, callback type,
              struct, enum value and typedef - against Appendix A.
  operations  the rows of 8.1 against those of chapter 9, and the C function
              each names against Appendix A.
  kotlin      the Kotlin entry each row of 8.1 calls exists in
              android_library (AP-1).
  behaviours  every behaviour of chapter 10 has operations of 8.1, as many
              operations as README chapter 6 counts, and each row's kind
              agrees with whether its functions take a callback.
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
Appendix A in their place until then; symbols needs a built library.

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
# The kinds of chapter 10 (part 1, chapter 8), and whether a row of that kind
# has a function that takes a callback and a release.
KINDS = {
    "同期の結果": False,
    "受け付けだけ（main に積む）": False,
    "受け付けた後の完了": True,
    "イベント": True,
    "登録と解除": True,
}
BEHAVIOUR_IDS = ("BH", "EV", "RG", "PR")
# Constants only the Windows Common.h may define (part 1, 5.2).
WINDOWS_ONLY = r"^NTK_SYSTEM_CODE_\w+$"


def at(fragment):
    return ROOT / fragment


def read(fragment, rep, check_name):
    return common.read(ROOT, fragment, rep, check_name)


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


def kotlin_sources():
    return {path: path.read_text(encoding="utf-8") for path in sorted(at(KOTLIN).rglob("*.kt"))}


def kotlin_type(sources, name):
    """The text of the file that declares the class, object or interface name."""
    pattern = re.compile(r"^\s*(?:\w+\s+)*(?:class|object|interface)\s+" + re.escape(name) + r"\b", re.M)
    for text in sources.values():
        if pattern.search(text):
            return text
    return None


def kotlin_order(sources, name, rep, check_name):
    """The members of an enum class, or the direct subclasses of a sealed
    class, in declaration order."""
    text = kotlin_type(sources, name)
    if text is None:
        rep.check(False, check_name, f"no Kotlin declares {name}")
        return None
    text = common.strip_comments(text)
    enum = re.search(r"enum class\s+" + re.escape(name) + r"\b[^{]*\{(.*?);", text, re.S)
    if enum:
        return [m for m in re.findall(r"^\s*([A-Z][A-Z0-9_]*)\s*[,(]?\s*$", enum.group(1), re.M)]
    return re.findall(r"^\s*(?:data\s+)?(?:class|object)\s+(\w+)\b[^\n]*:\s*" + re.escape(name) + r"\(\)",
                      text, re.M)


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
    chapter_9 = {cells[0] for cells in table_rows(design, "## 9.") if cells and cells[0].startswith("OP-")}
    problems = []
    numbers = sorted(int(op[3:]) for op in ops)
    if numbers != list(range(1, len(numbers) + 1)):
        problems.append("the operations of 8.1 are not OP-01 to OP-N without gaps")
    if set(ops) != chapter_9:
        problems.append(f"8.1 and chapter 9 list different operations: {', '.join(sorted(set(ops) ^ chapter_9))}")
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
        text = kotlin_type(sources, parts[-2])
        if text is None:
            problems.append(f"{op}: no Kotlin declares {parts[-2]}")
            continue
        member = re.escape(parts[-1])
        if not re.search(r"\b(?:fun(?:\s+<[^>]*>)?|val|var)\s+(?:\w+\.)?" + member + r"\b", text):
            problems.append(f"{op}: {parts[-2]} has no member {parts[-1]}")
            continue
        compared += 1
    rep.check(not problems and compared > 0, f"{name} ({compared} entries)", "; ".join(problems) or "nothing was compared")


def check_behaviours(design, readme, expected, rep):
    name = "behaviours: chapter 10 maps every behaviour to operations of 8.1"
    ops = operations(design)
    rows = [cells for cells in table_rows(design, "## 10.") if cells and re.match(r"^[A-Z]+-\d+$", cells[0])]
    problems, by_kind = [], {}
    for prefix in BEHAVIOUR_IDS:
        numbers = [int(cells[0].split("-")[1]) for cells in rows if cells[0].startswith(prefix + "-")]
        by_kind[prefix] = len(numbers)
        if numbers != list(range(1, len(numbers) + 1)):
            problems.append(f"the {prefix} rows are not {prefix}-01 to {prefix}-N without gaps")
    for cells in rows:
        if cells[0].split("-")[0] not in BEHAVIOUR_IDS:
            problems.append(f"{cells[0]} is not one of {', '.join(BEHAVIOUR_IDS)}")
            continue
        if len(cells) < 6:
            problems.append(f"{cells[0]} has {len(cells)} columns, not 6")
            continue
        named = op_range(cells[5])
        if not named:
            problems.append(f"{cells[0]} names no operation")
        missing = [op for op in named if op not in ops]
        if missing:
            problems.append(f"{cells[0]} names {', '.join(missing)}, which 8.1 lacks")
        kind = cells[3]
        if kind not in KINDS:
            problems.append(f"{cells[0]}: '{kind}' is none of {', '.join(KINDS)}")
            continue
        takes = [op for op in named if op in ops and takes_callback(expected["function"].get(ops[op][1], ""))]
        if KINDS[kind] and not takes:
            problems.append(f"{cells[0]} is '{kind}' but none of its functions takes a callback and a release")
        if not KINDS[kind] and takes:
            problems.append(f"{cells[0]} is '{kind}' but {', '.join(takes)} takes a callback")
    total = re.search(r"^\| 計 \| (\d+) \| (\d+) \|", readme or "", re.M)
    if total is None:
        problems.append("README chapter 6 has no total row")
    elif by_kind.get("BH") != int(total.group(2)):
        problems.append(f"chapter 10 has {by_kind.get('BH')} operations, README chapter 6 counts {total.group(2)}")
    kinds = {kind: sum(1 for cells in rows if len(cells) > 3 and cells[3] == kind) for kind in KINDS}
    summary = ", ".join(f"{prefix} {count}" for prefix, count in by_kind.items())
    derived = ", ".join(f"{kind} {count}" for kind, count in kinds.items())
    rep.check(not problems and rows, f"{name} ({summary}; {derived})", "; ".join(problems) or "chapter 10 is empty")


def takes_callback(signature):
    """Whether a declaration takes a callback of its own and a release."""
    callbacks = set(re.findall(r"\bntk_\w+_fn\b", signature))
    return "ntk_release_fn" in callbacks and len(callbacks) > 1


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
        order = kotlin_order(sources, kotlin_name, rep, name)
        if order is None:
            return
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
    problems = []
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


def find_nm(given):
    if given:
        return given
    found = shutil.which("llvm-nm")
    if found:
        return found
    for home in (os.environ.get("ANDROID_NDK_HOME"), os.environ.get("ANDROID_NDK_ROOT")):
        if home:
            matches = sorted(glob.glob(f"{home}/toolchains/llvm/prebuilt/*/bin/llvm-nm"))
            if matches:
                return matches[-1]
    sdk = os.environ.get("ANDROID_HOME") or os.path.expanduser("~/Library/Android/sdk")
    matches = sorted(glob.glob(f"{sdk}/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-nm"))
    return matches[-1] if matches else None


def check_symbols(library, nm, listed, rep):
    name = "symbols: libntk.so exports 8.2 and JNI_OnLoad only (AP-15)"
    if library is None:
        rep.skip(name, "no --library (run after the build)")
        return
    if not Path(library).exists():
        rep.check(False, name, f"cannot read {library}")
        return
    tool = find_nm(nm)
    if tool is None:
        rep.check(False, name, "no llvm-nm (give --nm or set ANDROID_NDK_HOME)")
        return
    finished = subprocess.run([tool, "-D", "--defined-only", str(library)], capture_output=True, text=True)
    if finished.returncode != 0:
        rep.check(False, name, f"{tool} failed: {finished.stderr.strip()}")
        return
    exported = {line.split()[-1] for line in finished.stdout.splitlines() if line.strip()}
    wanted = set(listed) | {"JNI_OnLoad"}
    problems = []
    if exported - wanted:
        problems.append(f"exported but not in 8.2: {', '.join(sorted(exported - wanted))}")
    if wanted - exported:
        problems.append(f"8.2 but not exported: {', '.join(sorted(wanted - exported))}")
    rep.check(not problems, f"{name} ({len(exported)} symbols)", "; ".join(problems))


def main(argv):
    global ROOT
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    arguments = list(argv[1:])

    def option(flag):
        if flag not in arguments:
            return None
        index = arguments.index(flag)
        value = arguments[index + 1]
        del arguments[index:index + 2]
        return value

    root = option("--root")
    if root:
        ROOT = Path(root).resolve()
    library = option("--library")
    nm = option("--nm")
    design_only = "--design-only" in arguments

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

    texts = None
    if not design_only:
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
        common.check_signatures(expected, merged(headers), rep)
    check_operations(design, expected, rep)
    sources = kotlin_sources()
    check_kotlin(design, sources, rep)
    check_behaviours(design, readme, expected, rep)
    values = merged(headers)["value"] if headers is not None else expected["value"]
    check_values(design, values, sources, rep)
    named = headers if headers is not None else {h: declarations(c) for h, c in appendix.items()}
    common.check_names(named, FEATURE_OF, COMMON_FUNCTIONS, rep)
    if texts is not None:
        check_ascii(texts, rep, "the public headers")
    else:
        check_ascii(appendix, rep, "the headers of Appendix A")
    check_common(texts.get("Common.h") if texts is not None else appendix.get("Common.h"), rep)
    check_symbols(library, nm, listed, rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
