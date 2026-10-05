#!/usr/bin/env python3
"""Check the Windows C ABI against its design (stage 5 design, section 12.3).

Both sides of every comparison are read from source, never from a list kept
here, so neither can drift without the other noticing:

  functions   the exported set: the .def, the public headers, the table of
              section 8.2 and Appendix A all name the same functions, and there
              are as many as 8.2 says.
  signatures  every declaration in the headers - function, callback type,
              struct, enum value and typedef - against Appendix A.
  operations  the 47 rows of 8.1 against the 47 of chapter 9, and the C++
              function each names against the C++ API design's 8.1.
  values      every enumeration of the C ABI against the C++ enum class it
              mirrors, and the error enumerations against the tables of
              chapter 11.
  names       every function, type and constant follows the rules of 1.1.
  ascii       the public headers are ASCII only (CT-03).

A file that cannot be read fails its check (R-30): a check that skips because
its subject is missing reports agreement it never checked.

What every OS checks the same way lives in c_abi_contract_common.py; this file
keeps what only Windows has, the .def and the C++ API the C ABI mirrors
(Android C ABI design part 2, 0.3).

Usage:
    python3 scripts/check_c_abi_contract_windows.py [--root <tree>]

--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.

Exit status is 1 when any check fails.
"""

import re
import sys
from pathlib import Path

import c_abi_contract_common as common
from c_abi_contract_common import Report, appendix_code, backticked, declarations, merged, table_rows

ROOT = Path(__file__).resolve().parent.parent

DESIGN = "artifact/topics/windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md"
CPP_DESIGN = "artifact/topics/windows-architecture/designs/2026-09-20-windows-architecture-cpp-api-design.md"
DEF = "windows/WindowsLibraryCApi/WindowsLibraryCApi.def"
HEADERS = {
    "Common.h": "windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h",
    "Dialog.h": "windows/WindowsLibraryCApi/include/NativeToolkitC/Dialog.h",
    "Notification.h": "windows/WindowsLibraryCApi/include/NativeToolkitC/Notification.h",
    "Clipboard.h": "windows/WindowsLibraryCApi/include/NativeToolkitC/Clipboard.h",
}
CPP_HEADERS = {
    "Error.h": "windows/WindowsLibrary/include/NativeToolkit/Error.h",
    "Dialog.h": "windows/WindowsLibrary/include/NativeToolkit/Dialog.h",
    "Notification.h": "windows/WindowsLibrary/include/NativeToolkit/Notification.h",
}

# Which C++ enum class each C enumeration mirrors (design E-8, 8.4). The C
# value is the C++ declaration order, so the two must agree name for name.
MIRRORS = {
    "NTK_DIALOG_ERROR_": ("Error.h", "DialogError"),
    "NTK_NOTIFICATION_ERROR_": ("Error.h", "NotificationError"),
    "NTK_CLIPBOARD_ERROR_": ("Error.h", "ClipboardError"),
    "NTK_DIALOG_ALERT_BUTTONS_": ("Dialog.h", "AlertButtons"),
    "NTK_DIALOG_ALERT_ICON_": ("Dialog.h", "AlertIcon"),
    "NTK_DIALOG_ALERT_DEFAULT_BUTTON_": ("Dialog.h", "AlertDefaultButton"),
    "NTK_DIALOG_ALERT_RESULT_": ("Dialog.h", "AlertResult"),
    "NTK_NOTIFICATION_SETTING_": ("Notification.h", "NotificationSetting"),
    "NTK_NOTIFICATION_SCENARIO_": ("Notification.h", "Scenario"),
    "NTK_NOTIFICATION_AUDIO_KIND_": ("Notification.h", "AudioKind"),
    "NTK_NOTIFICATION_DURATION_": ("Notification.h", "Duration"),
    "NTK_NOTIFICATION_LOGO_CROP_": ("Notification.h", "LogoCrop"),
}
# C enumerations with no C++ enum class to mirror. Every entry needs a reason:
# this is the one place the check can be silenced.
NOT_MIRRORED = {
    # The copy flags are bits; C++ has WriteOptions, a struct of two bools
    # (8.4.3). Checked below as bits instead.
    "NTK_CLIPBOARD_WRITE_",
}
# Where the chapter 11 table of each error enumeration is.
ERROR_TABLES = {
    "NTK_DIALOG_ERROR_": "### 11.1",
    "NTK_NOTIFICATION_ERROR_": "### 11.2",
    "NTK_CLIPBOARD_ERROR_": "### 11.3",
}
# The prefix every function of a header starts with (1.1). Common.h holds what
# belongs to no feature.
FEATURE_OF = {"Dialog.h": "dialog", "Notification.h": "notification", "Clipboard.h": "clipboard"}
COMMON_FUNCTIONS = re.compile(r"^ntk_(version|last_system_code|string_\w+|bytes_\w+|string_list_\w+)$")


def at(fragment):
    return ROOT / fragment


def read(fragment, rep, check_name):
    """The file's text, or None and a failure of the check that needed it."""
    return common.read(ROOT, fragment, rep, check_name)


# ---------------------------------------------------------------------------
# Reading the design's tables
# ---------------------------------------------------------------------------

def c_operations(design):
    """OP -> (C function, C++ function) from the C ABI design's 8.1."""
    table = {}
    for cells in table_rows(design, "### 8.1"):
        if len(cells) < 3 or not cells[0].startswith("OP-"):
            continue
        cpp = backticked(cells[1])
        c = backticked(cells[2])
        if cpp and c:
            table[cells[0]] = (c[0].split("(")[0].strip(), cpp[0])
    return table


def cpp_operations(cpp_design):
    """OP -> 'Class::Function' or 'Function', from the C++ API design's 8.1."""
    table = {}
    for cells in table_rows(cpp_design, "### 8.1"):
        if len(cells) < 3 or not cells[0].startswith("OP-"):
            continue
        signatures = backticked(cells[2])
        if not signatures:
            continue
        match = re.search(r"(?:(\w+)::)?(\w+)\s*\(", signatures[0])
        if match:
            table[cells[0]] = f"{match.group(1)}::{match.group(2)}" if match.group(1) else match.group(2)
    return table


def section_8_2(design, ops):
    """The functions of 8.2 and the count each row and the total claim."""
    return common.section_8_2(design, {op: functions[0] for op, functions in ops.items()})


# ---------------------------------------------------------------------------
# Reading the C++ enum classes
# ---------------------------------------------------------------------------

def cpp_enum(text, name):
    """name -> value of an enum class, counting implicit values in order."""
    body = re.search(r"enum class\s+" + re.escape(name) + r"\b[^{]*\{(.*?)\};", text, re.S)
    if not body:
        return None
    members, next_value = {}, 0
    for item in common.strip_comments(body.group(1)).split(","):
        match = re.match(r"\s*(\w+)\s*(?:=\s*(\d+))?\s*$", item)
        if not match:
            continue
        value = int(match.group(2)) if match.group(2) else next_value
        members[match.group(1)] = value
        next_value = value + 1
    return members


def flatten(name):
    return name.replace("_", "").lower()


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def check_functions(design, headers, rep):
    name = "functions: .def, headers, 8.2 and Appendix A agree"
    text = read(DEF, rep, name)
    appendix = appendix_code(design)
    if text is None or appendix is None or not headers:
        if appendix is None:
            rep.check(False, name, "no Appendix A")
        return
    exported = set()
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith((";", "LIBRARY", "EXPORTS")):
            exported.add(line)
    declared = set()
    for decl in headers.values():
        declared |= set(decl["function"])
    in_appendix = set(declarations(appendix)["function"])
    in_8_2, total, problems = section_8_2(design, c_operations(design))
    listed = set(in_8_2)
    if len(in_8_2) != len(listed):
        problems.append("8.2 names a function twice")
    for label, other in (("the headers", declared), ("8.2", listed), ("Appendix A", in_appendix)):
        if other - exported:
            problems.append(f"{label} but not the .def: {', '.join(sorted(other - exported))}")
        if exported - other:
            problems.append(f"the .def but not {label}: {', '.join(sorted(exported - other))}")
    if total is None:
        problems.append("8.2 has no total")
    elif total != len(exported):
        problems.append(f"8.2 says {total} in all, the .def exports {len(exported)}")
    if not exported:
        problems.append("the .def exports nothing")
    rep.check(not problems, f"{name} ({len(exported)} functions)", "; ".join(problems))


def check_signatures(design, headers, texts, rep):
    appendix = appendix_code(design)
    if appendix is None or not headers:
        rep.check(False, "signatures: the headers declare what Appendix A does", "no Appendix A or no headers")
        return
    problems = [p for label, text in texts.items() for p in common.directive_problems(label, text)]
    common.check_signatures(declarations(appendix), merged(headers), rep, problems)


def check_operations(design, rep):
    name = "operations: 8.1, chapter 9 and the C++ design's 8.1 agree"
    cpp_design = read(CPP_DESIGN, rep, name)
    if cpp_design is None:
        return
    ops = c_operations(design)
    chapter_9 = {}
    for cells in table_rows(design, "## 9."):
        if len(cells) >= 2 and cells[0].startswith("OP-"):
            functions = backticked(cells[1])
            if functions:
                chapter_9[cells[0]] = functions[0]
    cpp = cpp_operations(cpp_design)
    problems = []
    if len(ops) != 47:
        problems.append(f"8.1 has {len(ops)} operations, not 47")
    if set(ops) != set(chapter_9):
        problems.append(f"8.1 and chapter 9 list different operations: "
                        f"{', '.join(sorted(set(ops) ^ set(chapter_9)))}")
    if set(ops) != set(cpp):
        problems.append(f"8.1 and the C++ design list different operations: "
                        f"{', '.join(sorted(set(ops) ^ set(cpp)))}")
    for op in sorted(set(ops) & set(chapter_9)):
        if ops[op][0] != chapter_9[op]:
            problems.append(f"{op} is {ops[op][0]} in 8.1 but {chapter_9[op]} in chapter 9")
    for op in sorted(set(ops) & set(cpp)):
        if ops[op][1] != cpp[op]:
            problems.append(f"{op} wraps {ops[op][1]} in 8.1 but the C++ design names {cpp[op]}")
    rep.check(not problems, f"{name} ({len(ops)} operations)", "; ".join(problems))


def check_values(design, headers, rep):
    values = {}
    for decl in headers.values():
        values.update(decl["value"])

    # Every C enumeration against the C++ enum class it mirrors.
    name = "values: every C enumeration matches its C++ enum class"
    cpp_texts = {}
    for label, fragment in CPP_HEADERS.items():
        text = read(fragment, rep, name)
        if text is None:
            return
        cpp_texts[label] = text
    problems, compared = [], 0
    prefixes = {prefix for prefix in MIRRORS} | NOT_MIRRORED
    for constant in values:
        if not any(constant.startswith(p) for p in prefixes):
            problems.append(f"{constant} belongs to no enumeration this check knows")
    for prefix, (header, enum) in sorted(MIRRORS.items()):
        mine = {k[len(prefix):]: v for k, v in values.items() if k.startswith(prefix)}
        theirs = cpp_enum(cpp_texts[header], enum)
        if not mine or theirs is None:
            problems.append(f"{prefix}* or {enum} could not be read")
            continue
        compared += 1
        theirs_flat = {flatten(k): v for k, v in theirs.items()}
        for member, value in mine.items():
            flat = flatten(member)
            if flat not in theirs_flat:
                problems.append(f"{prefix}{member} has no {enum} counterpart")
            elif theirs_flat[flat] != value:
                problems.append(f"{prefix}{member}={value} but {enum} says {theirs_flat[flat]}")
        for member in theirs_flat:
            if member not in {flatten(m) for m in mine}:
                problems.append(f"{enum} has {member}, which the C ABI lacks")
    rep.check(not problems and compared > 0, f"{name} ({compared} enumerations)", "; ".join(problems))

    # The copy flags are bits of the two WriteOptions fields.
    flags = {k: v for k, v in values.items() if k.startswith("NTK_CLIPBOARD_WRITE_")}
    rep.check(flags == {"NTK_CLIPBOARD_WRITE_DEFAULT": 0, "NTK_CLIPBOARD_WRITE_EXCLUDE_HISTORY": 1,
                        "NTK_CLIPBOARD_WRITE_EXCLUDE_ROAMING": 2, "NTK_CLIPBOARD_WRITE_SENSITIVE": 3},
              "values: the copy flags are the two WriteOptions bits and both", str(flags))

    # The error enumerations against the tables of chapter 11.
    problems = common.error_table_problems(design, values, ERROR_TABLES)
    rep.check(not problems, "values: the errors match the tables of chapter 11", "; ".join(problems))


def check_names(headers, rep):
    common.check_names(headers, FEATURE_OF, COMMON_FUNCTIONS, rep)


def check_ascii(rep):
    problems = []
    for label, fragment in HEADERS.items():
        path = at(fragment)
        if not path.exists():
            problems.append(f"cannot read {fragment}")
            continue
        problems.extend(common.non_ascii_lines(label, path.read_bytes()))
    rep.check(not problems, "ascii: the public headers are ASCII only (CT-03)", ", ".join(problems))


def main(argv):
    global ROOT
    # The messages quote the design, which is Japanese; the console's code
    # page would mangle it, and a caller reading the output expects UTF-8.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    arguments = list(argv[1:])
    if "--root" in arguments:
        index = arguments.index("--root")
        ROOT = Path(arguments[index + 1]).resolve()
        del arguments[index:index + 2]

    rep = Report()
    design = read(DESIGN, rep, "the C ABI design")
    headers, texts = {}, {}
    for label, fragment in HEADERS.items():
        text = read(fragment, rep, f"the public header {label}")
        if text is not None:
            texts[label] = text
            headers[label] = declarations(text)
    if design is not None:
        check_functions(design, headers, rep)
        check_signatures(design, headers, texts, rep)
        check_operations(design, rep)
        check_values(design, headers, rep)
    check_names(headers, rep)
    check_ascii(rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
