#!/usr/bin/env python3
"""Check the iOS C ABI against its design (iOS C ABI design part 2, 12.3).

Both sides of every comparison are read from source, never from a list kept
here, so neither can drift without the other noticing:

  functions   the public headers, the table of section 8.2 and Appendix A
              all name the same functions, as many as 8.2 says.
  signatures  every declaration in the headers - function, callback type,
              struct, enum value and typedef - against Appendix A, nothing
              this reading cannot place, no preprocessor line a header may not
              have (an #if would hide a declaration from this reading), the
              same preprocessor lines and #define values as Appendix A, and
              the two ways a feature header includes Common.h (part 1, 5.2).
  shape       Appendix A itself: the same rules for its preprocessor lines and
              nothing unread, so that the headers TB-1 writes from it can pass.
  operations  the rows of 8.1 run without gaps, as many as 8.2 says, and each
              names its own C function, which Appendix A declares.
  swift       the Swift entry each row of 8.1 calls exists in the
              swiftinterface of TB-0, with its labels, and is static, async
              and throwing where the row says so (P2-1, P2-12). Only the rows
              8.1 lists as the receiver's own may name no entry, and each of
              those adds or removes a listener.
  behaviours  every behaviour of chapter 10 has operations of 8.1, its kind
              agrees with its functions (a completion callback, a listener or
              its removal, or neither), and the operations of each kind are
              exactly those whose functions have that shape, so that the
              counts of the kinds are read from both sides. The operations,
              the events and the functions of the bridge are as many as README
              chapter 6 counts, and every row of 8.3 has a behaviour.
  values      the error enumerations against the tables of chapter 11, and the
              shared meanings of 0 to 5 (AP-12).
  cases       every case of ClipboardError, ShareError, DialogError and
              NotificationError in the swiftinterface is in the table of
              chapter 11 of its own enumeration, the table names no case that
              is not, and the sources declare the same cases as the
              swiftinterface. Their order is not compared (P2-9 (7)).
  numbers     the errors of the iOS and the Android headers against the table
              of numbers the OSes share, and no name in it that neither
              declares (P1-7, part 1, 5.5).
  names       every function, type and constant follows the naming rules, and
              a function ends in _async exactly when it takes a completion
              (P2-3).
  ascii       the public headers are ASCII only.
  common      the Common.h of iOS, Android and Windows (part 1, 5.2).
  entries     H = E of part 1, 5.5: every function of the headers has a
              @c @implementation public func in the capi's Swift sources, or is
              in NOT_IMPLEMENTED_YET, never both and never neither, and nothing
              else has an entry.
  complete    NOT_IMPLEMENTED_YET is empty, so that H = E itself holds. This is
              what stops a function hiding in the list: entries takes a name
              added to it. A SKIP until --require-complete, which TB-10, TB-11
              and TB-12 ask for.
  public      E = P of part 1, 5.5: the capi declares nothing public or open
              but its entries (P1-1).
  modulemap   the module map has the form of part 1, 5.1 and names exactly the
              headers of include/NativeToolkitC (part 1, 5.5).
  compile     every public header compiles alone as C99, C11, C++ and
              Objective-C with -Wall -Wextra -Werror -pedantic (12.3), through
              both branches of its include of Common.h: as a framework and as
              the loose copy.
  layout      every struct and field of the headers has its row in the layout
              test, the rows are the _Static_assert they are written as and no
              #if hides them, every size is a multiple of 8 (rule 5 of part 1, 1.1),
              and the target does not leave the file out (12.1). compile compiles it
              for the three slices, which holds the sizes to the compiler.
  settings    the framework target has the settings of part 1, 5.4 in Release;
              Debug differs in the two that @testable import needs and nothing
              else; archiving takes Release.
  install     every case of NotificationDelegateInstallResult has its line in
              the receiver (part 1, 1.4): the compiler only warns, and a new
              case would come out as UNKNOWN.
  symbols     after a build, the symbols the library exports are the _ntk_* of
              8.2 less NOT_IMPLEMENTED_YET and nothing else, in every
              architecture it has, and it has those --architectures names
              (AP-15, part 1, 5.5).

A file that cannot be read fails its check (R-30). Four checks run only when
they can, and say so: --design-only reads Appendix A in place of the headers
(and fails once a header exists; those that need the headers or the capi's
sources do not run); symbols needs a built library; compile needs Xcode, whose
absence --require-compile makes a failure, and a --clang that does not exist
always fails; complete needs --require-complete. An argument this script does
not know is a usage error, so a misspelt option cannot turn a check into a SKIP.

Not checked here: what part 1, 5.5 compares with the distributable and the
capi's C sources (TB-11); which behaviour names which of two operations of one
shape; the argument names 8.1 writes after a C function.

What every OS checks the same way lives in c_abi_contract_common.py.

Usage:
    python3 scripts/check_c_abi_contract_ios.py [--root <tree>] [--design-only]
                                                [--require-compile] [--require-complete]
                                                [--clang <clang>]
                                                [--library <binary> [--nm <nm>]
                                                 [--architectures <a,b>]]

--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.
--library takes one binary, so one slice of the xcframework per run;
--architectures says which architectures that slice must have, because a slice
that lost one has nothing left to compare.

Exit status is 1 when any check fails.
"""

import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import c_abi_contract_common as common
from c_abi_contract_common import Report, appendix_headers, backticked, declarations, merged, op_range, table_rows

ROOT = Path(__file__).resolve().parent.parent

DESIGN = "artifact/topics/ios-c-abi/designs/2026-11-03-ios-c-abi-c-abi-design-part2.md"
README = "artifact/topics/ios-c-abi/README.md"
# The public API after TB-0, the baseline part 2 cites (12.3).
SWIFT_INTERFACE = "artifact/topics/ios-c-abi/results/swiftinterface/IosLibrary-after-tb0.swiftinterface"
CAPI = "ios/IosLibraryCApi"
INCLUDE = f"{CAPI}/include/NativeToolkitC"
ANDROID_INCLUDE = "android/android_library_capi/src/main/cpp/include/NativeToolkitC"
WINDOWS_COMMON = "windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h"
MODULE_MAP = f"{CAPI}/IosLibraryCApi/module.modulemap"
LAYOUT_TEST = "ios/IosLibraryCApiTests/StructLayoutTests.m"
PROJECT = f"{CAPI}/IosLibraryCApi.xcodeproj"
PBXPROJ = f"{PROJECT}/project.pbxproj"
SCHEME = f"{PROJECT}/xcshareddata/xcschemes/IosLibraryCApi.xcscheme"
RECEIVER = f"{CAPI}/IosLibraryCApi/Notification/NotificationReceiver.swift"
INSTALL_RESULT = "ios/IosLibrary/IosLibrary/Notification/Domain/Model/NotificationDelegateInstallResult.swift"

# The prefix every function of a header starts with. Common.h holds what
# belongs to no feature.
FEATURE_OF = {"Clipboard.h": "clipboard", "Dialog.h": "dialog", "Notification.h": "notification", "Share.h": "share"}
COMMON_FUNCTIONS = re.compile(r"^ntk_(version|last_system_code|string_\w+|bytes_\w+|string_list_\w+)$")
# How a feature header includes Common.h: the first branch inside the
# framework, the second in the copy under dist/include (part 1, 5.2).
COMMON_INCLUDE = (
    "#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)",
    "#include <IosLibraryCApi/NativeToolkitC/Common.h>",
    "#else",
    '#include "Common.h"',
    "#endif",
)
# Each error enumeration: its chapter 11 table, the Swift enumeration that
# table's third column cites, and the source declaring it.
ERRORS = {
    "NTK_DIALOG_ERROR_": ("### 11.1", "DialogError", "Dialog"),
    "NTK_NOTIFICATION_ERROR_": ("### 11.2", "NotificationError", "Notification"),
    "NTK_CLIPBOARD_ERROR_": ("### 11.3", "ClipboardError", "Clipboard"),
    "NTK_SHARE_ERROR_": ("### 11.4", "ShareError", "Share"),
}
ERROR_TABLES = {prefix: heading for prefix, (heading, _, _) in ERRORS.items()}
SWIFT_SOURCES = "ios/IosLibrary/IosLibrary"
# What the third column cites like a case and is not one of the enumeration:
# the other half of Result, and the PresenterSelection the entry never takes.
NOT_ERROR_CASES = {"success", "firstActiveScene"}
# The architectures of the thin binaries --architectures can be asked about:
# nm prints no heading for one, so its Mach-O header names it.
MACH_O_MAGIC = b"\xcf\xfa\xed\xfe"
MACH_O_CPU_TYPES = {0x0100000C: "arm64", 0x01000007: "x86_64"}
# The kinds of chapter 10, and which kinds each ID allows. Nothing only
# accepts: an operation that needs main completes through a callback (P2-2).
SYNC, COMPLETION, EVENT, REGISTRATION = ("同期の結果", "受け付けた後の完了", "イベント", "登録と解除")
KINDS_OF = {
    "BH": {COMPLETION},
    "EV": {EVENT},
    "RG": {REGISTRATION, COMPLETION, SYNC},
    "PR": {SYNC, EVENT, COMPLETION},
}
# The row of 8.1 whose function the receiver answers from its own ledger, with
# no Swift entry to call.
LEDGER = "受け口の帳簿"

# The functions of the headers that have no entry yet (H = E can only hold at
# TB-10, part 2, chapter 13). `entries` fails when a function here gets an entry
# or leaves the headers, so the list shrinks as the entries come. Nothing but
# --require-complete stops a name being added: it must be empty at TB-10.
NOT_IMPLEMENTED_YET = (
    # Notification.h
    "ntk_notification_show_async",
    "ntk_notification_update_async",
    "ntk_notification_schedule_async",
    "ntk_notification_remove_async",
    "ntk_notification_remove_all_async",
    "ntk_notification_cancel_scheduled_async",
    "ntk_notification_cancel_all_scheduled_async",
    "ntk_notification_get_scheduled_async",
    "ntk_notification_get_delivered_async",
    "ntk_notification_request_permission_async",
    "ntk_notification_get_authorization_status_async",
    "ntk_notification_has_permission_async",
    "ntk_notification_open_settings_async",
    "ntk_notification_set_badge_count_async",
    "ntk_notification_register_category_async",
    "ntk_notification_remove_category_async",
    "ntk_notification_add_interaction_listener",
    "ntk_notification_add_settings_request_listener",
    "ntk_notification_get_launch_response_async",
    "ntk_notification_listener_remove",
    "ntk_notification_content_create",
    "ntk_notification_content_free",
    "ntk_notification_content_set_subtitle",
    "ntk_notification_content_set_body",
    "ntk_notification_content_set_badge",
    "ntk_notification_content_set_sound",
    "ntk_notification_content_set_category",
    "ntk_notification_content_set_interruption_level",
    "ntk_notification_content_set_thread",
    "ntk_notification_content_set_target_content",
    "ntk_notification_content_set_relevance_score",
    "ntk_notification_content_set_filter_criteria",
    "ntk_notification_content_set_user_info_json",
    "ntk_notification_content_add_attachment",
    "ntk_notification_interaction_kind",
    "ntk_notification_interaction_notification_id",
    "ntk_notification_interaction_action_id",
    "ntk_notification_interaction_category_id",
    "ntk_notification_interaction_user_text",
    "ntk_notification_interaction_user_info_json",
    "ntk_notification_interaction_is_launch",
    "ntk_notification_interaction_free",
    "ntk_notification_settings_request_notification_id",
    "ntk_notification_settings_request_free",
    "ntk_notification_list_count",
    "ntk_notification_list_identifier_at",
    "ntk_notification_list_title_at",
    "ntk_notification_list_subtitle_at",
    "ntk_notification_list_body_at",
    "ntk_notification_list_category_at",
    "ntk_notification_list_date_millis_at",
    "ntk_notification_list_free",
    # Share.h
    "ntk_share_content_async",
    "ntk_share_result_completed",
    "ntk_share_result_activity_type",
    "ntk_share_result_free",
)

# How each language compiles the headers (12.3). -pedantic is what makes -std=c99
# mean something to clang.
HEADER_LANGUAGES = (("C99", "c", "-std=c99"), ("C11", "c", "-std=c11"),
                    ("C++", "c++", "-std=c++11"), ("Objective-C", "objective-c", "-std=gnu11"))
HEADER_WARNINGS = ("-Wall", "-Wextra", "-Werror", "-pedantic")
# The lowest iOS the library supports (README D-15).
CLANG_TARGET = "arm64-apple-ios18.0"
# The slices the layout test is compiled for, with their SDKs (D-11).
LAYOUT_SLICES = ((CLANG_TARGET, "iphoneos"), ("arm64-apple-ios18.0-simulator", "iphonesimulator"),
                 ("x86_64-apple-ios18.0-simulator", "iphonesimulator"))
# Every preprocessor line the layout test may have, so that nothing can make its
# rows do nothing (#if 0, another #define).
LAYOUT_DIRECTIVES = (
    "#include <stddef.h>",
    "#include <IosLibraryCApi/NativeToolkitC/Clipboard.h>",
    "#include <IosLibraryCApi/NativeToolkitC/Dialog.h>",
    "#include <IosLibraryCApi/NativeToolkitC/Notification.h>",
    "#include <IosLibraryCApi/NativeToolkitC/Share.h>",
    '#define LAYOUT_SIZE(type, size) _Static_assert(sizeof(type) == (size), "sizeof(" #type ")")',
    '#define LAYOUT_FIELD(type, field, offset) _Static_assert(offsetof(type, field) == (offset), "offsetof(" #type ", " #field ")")',
)
# Part 1, 5.4, as the project writes it. The deployment target and the strict
# concurrency come from the project's own settings, which the target inherits.
FRAMEWORK_SETTINGS = {
    "BUILD_LIBRARY_FOR_DISTRIBUTION": "NO",
    "DEFINES_MODULE": "YES",
    "ENABLE_MODULE_VERIFIER": "YES",
    "EXPORTED_SYMBOLS_FILE": "IosLibraryCApi/IosLibraryCApi.exp",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "MACH_O_TYPE": "mh_dylib",
    "MODULEMAP_FILE": "IosLibraryCApi/module.modulemap",
    "MODULE_VERIFIER_SUPPORTED_LANGUAGES": "c c++ objective-c objective-c++",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.jonghyunkim.nativetoolkit.IosLibraryCApi",
    "PUBLIC_HEADERS_FOLDER_PATH": "$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC",
    "SWIFT_INSTALL_MODULE": "NO",
    "SWIFT_INSTALL_OBJC_HEADER": "NO",
    "SWIFT_VERSION": "6.0",
}
# All that Debug may change, and to what, for @testable import (part 1, 5.4).
DEBUG_ONLY = {
    "OTHER_LDFLAGS": ("$(inherited)", "-Wl,-exported_symbol,_$$s14IosLibraryCApi*"),
    "SWIFT_INSTALL_MODULE": "YES",
}

USAGE = ("usage: check_c_abi_contract_ios.py [--root <tree>] [--design-only] "
         "[--require-compile] [--require-complete] [--clang <clang>] "
         "[--library <binary> [--nm <nm>] [--architectures <a,b>]]")


def at(fragment):
    return ROOT / fragment


def read(fragment, rep, check_name):
    return common.read(ROOT, fragment, rep, check_name)


# ---------------------------------------------------------------------------
# Reading the swiftinterface
# ---------------------------------------------------------------------------

def swift_code(text):
    """The text with comments and string literals gone: a brace in a default
    value would throw the counting off, and a declaration in a comment is not
    one."""
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def body_at(code, start):
    """The text at the top level of the body opening at code[start], with every
    nested body removed."""
    depth, kept = 0, []
    for char in code[start:]:
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


def swift_bodies(code, name):
    """The top level of the type declared as name and of every extension of it, together."""
    pattern = (r"^[^\n]*\b(?:class|struct|enum|actor|protocol)\s+" + re.escape(name) + r"\b[^{\n]*\{"
               r"|^extension\s+(?:\w+\.)?" + re.escape(name) + r"\b[^{\n]*\{")
    return "\n".join(body_at(code, match.end() - 1) for match in re.finditer(pattern, code, re.M))


def enum_cases(code, name):
    """The cases of a Swift enumeration, however many a line declares."""
    cases = []
    declaration = r"^\s*(?:@\w+(?:\([^)\n]*\))?\s+)*(?:indirect\s+)?case\s+(.+)$"
    for line in re.findall(declaration, swift_bodies(code, name), re.M):
        depth, current, items = 0, [], []
        for char in line:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            elif char == "," and depth == 0:
                items.append("".join(current))
                current = []
                continue
            if depth == 0 and char != ")":
                current.append(char)
        items.append("".join(current))
        cases.extend(m.group(0) for item in items for m in [re.match(r"\s*\w+", item)] if m)
    return [case.strip() for case in cases]


def top_level_split(text):
    """text split at its commas outside any bracket; -> is not a bracket."""
    depth, current, items = 0, [], []
    for char in text.replace("->", "→"):
        if char in "([<":
            depth += 1
        elif char in ")]>":
            depth -= 1
        elif char == "," and depth == 0:
            items.append("".join(current))
            current = []
            continue
        current.append(char)
    if "".join(current).strip():
        items.append("".join(current))
    return items


def swift_functions(body):
    """Every function of a type's top level: (selector, modifiers, what follows its parameters)."""
    found = []
    for match in re.finditer(r"^([^\n]*?)\bfunc\s+(\w+)\s*(?:<[^(\n]*>)?\(", body, re.M):
        index, depth = match.end(), 1
        while index < len(body) and depth:
            depth += {"(": 1, ")": -1}.get(body[index], 0)
            index += 1
        labels = [item.split(":")[0].split()[0] for item in top_level_split(body[match.end():index - 1])]
        rest = body[index:body.find("\n", index) if "\n" in body[index:] else len(body)]
        found.append((f"{match.group(2)}({''.join(label + ':' for label in labels)})", match.group(1), rest))
    return found


def swift_property_type(body, name):
    """The type a property is declared with, without its module and arguments, or None."""
    match = re.search(r"\b(?:var|let)\s+" + re.escape(name) + r"\s*:\s*(?:\w+\.)*(\w+)", body)
    return match.group(1) if match else None


# ---------------------------------------------------------------------------
# Reading the design
# ---------------------------------------------------------------------------

def swift_entries(design, problems):
    """OP -> (type, property or None, selector, the traits its cell asks for),
    or None for a row the receiver answers by itself. A row without a type
    belongs to the one last named; 同上 is the row above."""
    entries, owner, previous = {}, None, None
    for cells in table_rows(design, "### 8.1"):
        if len(cells) < 3 or not cells[0].startswith("OP-"):
            continue
        op, cell = cells[0], cells[1]
        written = backticked(cell)
        if cell == "同上" and previous is not None:
            entries[op] = previous
            continue
        if not written:
            if LEDGER not in cell:
                problems.append(f"{op}: '{cell}' names no Swift entry")
            entries[op] = previous = None
            continue
        match = re.fullmatch(r"(?:(Ios\w+Manager)\.)?(?:(\w+)\.)?(\w+\((?:\w+:)*\))((?: \w+)*)", written[0])
        if not match:
            problems.append(f"{op}: '{written[0]}' is not [Manager.][property.]name(labels:)")
            continue
        owner = match.group(1) or owner
        if owner is None:
            problems.append(f"{op}: no row above names a Manager for {written[0]}")
            continue
        traits = set(match.group(4).split())
        if "static" in written[1:]:
            traits.add("static")
        previous = entries[op] = (owner, match.group(2), match.group(3), traits)
    return entries


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def check_operations(design, expected, rep):
    name = "operations: 8.1 runs without gaps and names what Appendix A declares"
    ops = common.c_functions_of_ops(design, 2)
    problems = []
    numbers = sorted(int(op[3:]) for op in ops)
    if numbers != list(range(1, len(numbers) + 1)):
        problems.append("the operations of 8.1 are not OP-01 to OP-N without gaps")
    claimed = re.search(r"8\.1 の (\d+) 操作", design)
    if claimed is None:
        problems.append("8.2 does not say how many operations 8.1 has")
    elif int(claimed.group(1)) != len(ops):
        problems.append(f"8.2 says '8.1 の {claimed.group(1)} 操作', 8.1 has {len(ops)}")
    named = list(ops.values())
    for function in sorted({f for f in named if named.count(f) > 1}):
        problems.append(f"8.1 names {function} twice")
    for op, function in sorted(ops.items()):
        if function not in expected["function"]:
            problems.append(f"{op} names {function}, which Appendix A does not declare")
    rep.check(not problems and ops, f"{name} ({len(ops)} operations)", "; ".join(problems) or "8.1 is empty")


def check_swift(design, functions, rep):
    name = "swift: every Swift entry of 8.1 exists in the swiftinterface"
    text = read(SWIFT_INTERFACE, rep, name)
    if text is None:
        return
    code = swift_code(text)
    problems = []
    entries = swift_entries(design, problems)
    # The rows with no entry: 8.1 lists them, and each adds or removes a
    # listener. Anything else could leave the check by writing that it has none.
    ops = common.c_functions_of_ops(design, 2)
    own = {op for op, entry in entries.items() if entry is None}
    listed = re.search(rf"「（{LEDGER}）」の行は ((?:、?OP-\d+)+)", design)
    if listed is None:
        problems.append(f"8.1 does not list its rows of {LEDGER}")
    elif own != set(op_range(listed.group(1))):
        problems.append(f"8.1 lists {listed.group(1)} as rows of {LEDGER}, its table has {', '.join(sorted(own))}")
    compared = 0
    for op, entry in sorted(entries.items()):
        if entry is None:
            if function_shape(ops.get(op, ""), functions.get(ops.get(op, ""), "")) != REGISTRATION:
                problems.append(f"{op} says {LEDGER} but its function neither adds nor removes a listener")
            continue
        owner, member, selector, traits = entry
        body = swift_bodies(code, owner)
        if not body:
            problems.append(f"{op}: the swiftinterface declares no {owner}")
            continue
        where = owner
        if member:
            where = swift_property_type(body, member)
            if where is None:
                problems.append(f"{op}: {owner} has no property {member}")
                continue
            body = swift_bodies(code, where)
        overloads = [f for f in swift_functions(body) if f[0] == selector]
        if not overloads:
            problems.append(f"{op}: {where} has no {selector}")
            continue
        wanted = [f for f in overloads
                  if ("static" not in traits or re.search(r"\bstatic\b", f[1]))
                  and all(re.search(rf"\b{t}\b", f[2]) for t in traits - {"static"})]
        if not wanted:
            problems.append(f"{op}: {where}.{selector} is not {' '.join(sorted(traits))}")
            continue
        compared += 1
    rep.check(not problems and compared > 0, f"{name} ({compared} entries)", "; ".join(problems) or "nothing was compared")


def function_shape(function, signature):
    """The kind a function's declaration says it has; a removal is a registration's other half."""
    if common.is_listener(function, signature) or function.endswith("_listener_remove"):
        return REGISTRATION
    return COMPLETION if common.takes_callback(signature) else SYNC


def check_behaviours(design, readme, expected, rep):
    name = "behaviours: chapter 10 maps every behaviour to operations of 8.1"
    ops = common.c_functions_of_ops(design, 2)
    functions = expected["function"]
    rows = [cells for cells in table_rows(design, "## 10.") if cells and re.match(r"^[A-Z]+-\d+$", cells[0])]
    problems, by_prefix = [], {}
    for prefix in KINDS_OF:
        numbers = [int(cells[0].split("-")[1]) for cells in rows if cells[0].startswith(prefix + "-")]
        by_prefix[prefix] = len(numbers)
        if not numbers or numbers != list(range(1, len(numbers) + 1)):
            problems.append(f"the {prefix} rows are not {prefix}-01 to {prefix}-N without gaps")

    # What README chapter 6 counts: the operations of its total row, and the
    # events its row lists.
    total = re.search(r"^\| 計 \| (\d+) \| (\d+) \|", readme or "", re.M)
    if total is None:
        problems.append("README chapter 6 has no total row")
    elif by_prefix.get("BH") != int(total.group(2)):
        problems.append(f"chapter 10 has {by_prefix.get('BH')} operations, README chapter 6 counts {total.group(2)}")
    # The bridge: README's number of functions, the rows of 8.3, and that every
    # one of them has a behaviour.
    bridge = {cells[0] for cells in table_rows(design, "### 8.3") if re.fullmatch(r"[A-Z]{2}-\d+", cells[0])}
    if total is not None and len(bridge) != int(total.group(1)):
        problems.append(f"8.3 has {len(bridge)} functions of the bridge, README chapter 6 counts {total.group(1)}")
    behaved = {b for cells in rows if len(cells) > 4 for b in re.split(r"、", cells[4]) if b != "-"}
    if behaved != bridge:
        problems.append(f"column B of chapter 10 and 8.3 differ in {', '.join(sorted(behaved ^ bridge))}")
    events = re.search(r"^\| 自発のイベント \| ([^|]+) \|", readme or "", re.M)
    if events is None:
        problems.append("README chapter 6 does not list the events")
    elif by_prefix.get("EV") != len(events.group(1).split("、")):
        problems.append(f"chapter 10 has {by_prefix.get('EV')} events, README chapter 6 lists {events.group(1).strip()}")

    named = {SYNC: set(), COMPLETION: set(), REGISTRATION: set()}
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
        operations = op_range(cells[5])
        if not operations:
            problems.append(f"{cells[0]} names no operation")
            continue
        missing = [op for op in operations if op not in ops]
        if missing:
            problems.append(f"{cells[0]} names {', '.join(missing)}, which 8.1 lacks")
            continue
        # An event names its listener and at most its removal, as a
        # registration does; a row of either must add a listener. A function of
        # another shape is caught below, when the kinds are counted.
        wanted = REGISTRATION if kind == EVENT else kind
        if wanted == REGISTRATION and not any(
                common.is_listener(ops[op], functions.get(ops[op], "")) for op in operations):
            problems.append(f"{cells[0]} is '{kind}' but adds no listener")
        named[wanted] |= set(operations)

    # The counts of the kinds, from both sides: the operations each kind names
    # are the operations whose functions have that shape, every one of 8.1
    # included.
    for kind, operations in named.items():
        shaped = {op for op, f in ops.items() if function_shape(f, functions.get(f, "")) == kind}
        if operations != shaped:
            problems.append(f"chapter 10 names {len(operations)} operations as '{kind}', 8.1 has {len(shaped)} of "
                            f"that shape; they differ in {', '.join(sorted(operations ^ shaped))}")

    kinds = {kind: sum(1 for cells in rows if len(cells) > 3 and cells[3] == kind)
             for kind in (SYNC, COMPLETION, EVENT, REGISTRATION)}
    summary = ", ".join(f"{prefix} {count}" for prefix, count in by_prefix.items())
    derived = ", ".join(f"{kind} {count}" for kind, count in kinds.items())
    rep.check(not problems and rows, f"{name} ({summary}; {derived})", "; ".join(problems) or "chapter 10 is empty")


def check_values(design, values, rep):
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
    for prefix in ERROR_TABLES:
        mine = {k[len(prefix):]: v for k, v in values.items() if k.startswith(prefix) and v < 6}
        if mine != shared:
            problems.append(f"{prefix}0..5 are {mine}, chapter 11 says {shared}")
    rep.check(not problems, name, "; ".join(problems))


def check_cases(design, rep):
    """Every case of the Swift errors against the table of its own enumeration.
    IosLibrary's enumerations are not @frozen from another module, so the
    compiler does not stop a case the receiver has not mapped (P2-13)."""
    name = "cases: every case of the Swift errors is in chapter 11 (P2-13)"
    text = read(SWIFT_INTERFACE, rep, name)
    if text is None:
        return
    code = swift_code(text)
    problems, compared = [], 0
    for heading, enumeration, feature in sorted(ERRORS.values()):
        cases = enum_cases(code, enumeration)
        if not cases:
            problems.append(f"the swiftinterface declares no cases of {enumeration}")
            continue
        # The swiftinterface is a baseline somebody retakes: a case added to
        # the source must not wait for that.
        source = read(f"{SWIFT_SOURCES}/{feature}/Domain/Model/{enumeration}.swift", rep, name)
        if source is not None:
            declared = set(enum_cases(swift_code(source), enumeration))
            if declared != set(cases):
                problems.append(f"the source and the swiftinterface differ in {enumeration}: "
                                f"{', '.join(sorted(declared ^ set(cases)))}; retake the baseline")
        # `.case`, `case` or `Enumeration.case`; another type's case is not one.
        cited = {token.removeprefix(f"{enumeration}.").lstrip(".") for cells in table_rows(design, heading)
                 if len(cells) >= 3 and cells[0].isdigit() for token in backticked(cells[2])}
        missing = [case for case in cases if case not in cited]
        if missing:
            problems.append(f"{heading} does not name {enumeration}.{', .'.join(missing)}")
        # The other way: a name written as a case is one. Names with _ or digits
        # (struct_size, CLIPBOARD_..., a commit) and other types are not written so.
        stale = sorted(token for token in cited - set(cases) - NOT_ERROR_CASES if re.fullmatch(r"[a-z][A-Za-z]*", token))
        if stale:
            problems.append(f"{heading} names .{', .'.join(stale)}, which {enumeration} does not have")
        compared += len(cases)
    rep.check(not problems and compared > 0, f"{name} ({compared} cases)", "; ".join(problems) or "nothing was compared")


def android_values(rep):
    """The constants of the Android headers. A header that is missing leaves
    its feature without an error, which fails the check on the table. What
    cannot be read fails here: this run has no Appendix A to compare them with,
    and a value it cannot read would be absent from the table's comparison."""
    folder = at(ANDROID_INCLUDE)
    values, unread = {}, []
    for path in sorted(folder.glob("*.h")) if folder.is_dir() else []:
        found = declarations(path.read_text(encoding="utf-8"))
        values.update(found["value"])
        unread += [f"{path.name}: '{item}'" for item in found["unread"]]
    rep.check(not unread, "numbers: the Android headers read whole", "; ".join(unread))
    return values


def check_async_names(functions, rep):
    name = "names: a function ends in _async exactly when it takes a completion (P2-3)"
    problems = []
    for function, signature in sorted(functions.items()):
        completes = function_shape(function, signature) == COMPLETION
        if function.endswith("_async") != completes:
            problems.append(f"{function} {'takes' if completes else 'does not take'} a completion")
    rep.check(not problems and functions, name, "; ".join(problems) or "nothing was read")


def preprocessor_lines(text):
    return [line for _, _, line in common.directive_lines(common.strip_comments(text))]


def include_problems(label, text):
    """The feature header includes Common.h the way of part 1, 5.2, once."""
    lines = preprocessor_lines(text)
    size = len(COMMON_INCLUDE)
    found = sum(1 for index in range(len(lines) - size + 1) if tuple(lines[index:index + size]) == COMMON_INCLUDE)
    if found != 1 or lines.count(COMMON_INCLUDE[3]) != 1:
        return [f"{label} does not include Common.h in the form of part 1, 5.2"]
    return []


def shape_problems(label, text):
    """What a public header and its text in Appendix A must both hold to."""
    blocks = (COMMON_INCLUDE,) if label in FEATURE_OF else ()
    problems = common.directive_problems(label, text, blocks)
    return problems + (include_problems(label, text) if label in FEATURE_OF else [])


def against_appendix_problems(label, text, appendix):
    """The preprocessor of a header against Appendix A: a #include or a version
    (a #define with its value) the declarations do not show."""
    wanted = appendix.get(label)
    if wanted is None:
        return []
    if preprocessor_lines(text) != preprocessor_lines(wanted):
        return [f"{label} and Appendix A differ in their preprocessor lines"]
    return []


def check_appendix_shape(appendix, rep):
    name = "shape: the headers of Appendix A have the form of part 1, 5.2"
    problems = [p for label, text in appendix.items() for p in shape_problems(label, text)]
    for label, text in appendix.items():
        problems += [f"{label}: cannot read '{item}'" for item in declarations(text)["unread"]]
    rep.check(not problems, name, "; ".join(problems))


def check_common(ios_common, rep):
    name = "common: the Common.h of iOS, Android and Windows share their declarations (part 1, 5.2)"
    windows = read(WINDOWS_COMMON, rep, name)
    android = read(f"{ANDROID_INCLUDE}/Common.h", rep, name)
    if windows is None or android is None:
        return
    if ios_common is None:
        rep.check(False, name, "no iOS Common.h")
        return
    problems = common.common_header_problems({"Windows": windows, "Android": android, "iOS": ios_common})
    rep.check(not problems, name, "; ".join(problems))


def capi_swift_code(rep, check_name):
    """{relative path: code without comments and strings} of the capi's Swift
    sources, anywhere under the module, or None and a failure when there are none."""
    paths = sorted(at(CAPI).rglob("*.swift"))
    if not paths:
        rep.check(False, check_name, f"no Swift sources under {CAPI}")
        return None
    return {str(p.relative_to(ROOT)): swift_code(p.read_text(encoding="utf-8")) for p in paths}


ENTRY = re.compile(r"@c\s+@implementation\s+public\s+func\s+(\w+)\s*\(")
# `open` also names methods (UIApplication.open), so only a declaration counts.
PUBLIC = re.compile(r"\bpublic\b|\bopen\s+(?:[\w@]+\s+)*?(?:class|func|var|let|subscript|init)\b")


def entry_names(sources):
    """The functions the sources define as entries of the C ABI."""
    return {name for code in sources.values() for name in ENTRY.findall(code)}


def check_entries(sources, functions, rep):
    """H = E of part 1, 5.5, less what is not implemented yet."""
    name = "entries: every function of the headers has its entry or is listed as not implemented yet"
    entries = entry_names(sources)
    listed, declared = set(NOT_IMPLEMENTED_YET), set(functions)
    problems = []
    if len(listed) != len(NOT_IMPLEMENTED_YET):
        problems.append("NOT_IMPLEMENTED_YET names a function twice")
    for label, names in (("has an entry but is not in the headers", entries - declared),
                         ("has an entry and is still in NOT_IMPLEMENTED_YET; take it out", entries & listed),
                         ("is in the headers, with no entry and not in NOT_IMPLEMENTED_YET", declared - entries - listed),
                         ("is in NOT_IMPLEMENTED_YET but not in the headers", listed - declared)):
        problems += [f"{function} {label}" for function in sorted(names)]
    rep.check(not problems and entries,
              f"{name} ({len(entries)} of {len(declared)}, {len(listed)} not implemented yet)",
              "; ".join(problems) or "no entries")


def check_complete(require, rep):
    """H = E itself: what TB-10, TB-11 and TB-12 ask for with --require-complete.
    Apart from the file, `entries` accepts any name added to the list."""
    name = "complete: every function of the headers has its entry"
    missing = len(NOT_IMPLEMENTED_YET)
    if missing and not require:
        rep.skip(name, f"{missing} functions are not implemented yet; --require-complete makes that a failure")
    else:
        rep.check(not missing, name, f"{missing} functions are not implemented yet, such as {', '.join(NOT_IMPLEMENTED_YET[:3])}")


def check_public(sources, rep):
    """E = P of part 1, 5.5: every public declaration of the capi is an entry."""
    name = "public: the capi declares nothing public but its entries (P1-1)"
    problems = []
    for path, code in sorted(sources.items()):
        spans = [match.span() for match in ENTRY.finditer(code)]
        for match in PUBLIC.finditer(code):
            if not any(start <= match.start() < end for start, end in spans):
                line = code[match.start():].split("\n", 1)[0].strip()
                problems.append(f"{path}: '{line}' is public and not an entry")
    rep.check(not problems, name, "; ".join(problems))


def check_module_map(text, header_names, rep):
    """The module map names the headers there are, in the one form of part 1, 5.1."""
    name = "modulemap: the module map names the headers of include/NativeToolkitC (part 1, 5.5)"
    code = re.sub(r"\s+", " ", common.strip_comments(text)).strip()
    match = re.fullmatch(r'framework module IosLibraryCApi \{((?: header "NativeToolkitC/[\w.]+")+) export \* \}', code)
    if match is None:
        rep.check(False, name, f"not the form of part 1, 5.1: {code}")
        return
    named = re.findall(r'header "NativeToolkitC/([\w.]+)"', match.group(1))
    problems = []
    for label, names in (("the module map names twice", {n for n in named if named.count(n) > 1}),
                         ("is in the module map but not in include/NativeToolkitC", set(named) - set(header_names)),
                         ("is in include/NativeToolkitC but not in the module map", set(header_names) - set(named))):
        problems += [f"{header} {label}" for header in sorted(names)]
    rep.check(not problems, f"{name} ({len(named)} headers)", "; ".join(problems))


def xcrun(*arguments):
    """What xcrun prints, or None without Xcode."""
    tool = shutil.which("xcrun")
    if tool is None:
        return None
    result = subprocess.run([tool, *arguments], capture_output=True, text=True)
    return result.stdout.strip() or None if result.returncode == 0 else None


def compile_problems(clang, sdks, names):
    """Every public header alone, in every language, through both branches of its
    include of Common.h, and the layout test for every slice. The first error of
    each that fails."""
    source = at(INCLUDE)
    with tempfile.TemporaryDirectory(prefix="c-abi-headers-ios-") as directory:
        work = Path(directory)
        headers = work / "IosLibraryCApi.framework" / "Headers" / "NativeToolkitC"
        headers.mkdir(parents=True)
        runs = []
        for header in names:
            shutil.copy(source / header, headers / header)
            as_framework = work / f"framework-{header}.tu"
            as_framework.write_text(f"#include <IosLibraryCApi/NativeToolkitC/{header}>\n", encoding="utf-8")
            as_copy = work / f"copy-{header}.tu"
            as_copy.write_text(f'#include "{header}"\n', encoding="utf-8")
            runs += [(header, "framework", as_framework, ("-F", str(work))), (header, "copy", as_copy, ("-I", str(source)))]

        def run(item):
            what, target, sdk, language, standard, search, unit = item
            result = subprocess.run([clang, "-target", target, "-isysroot", sdks[sdk], "-x", language, standard,
                                     *HEADER_WARNINGS, "-fsyntax-only", *search, str(unit)],
                                    capture_output=True, text=True)
            if result.returncode == 0:
                return None
            errors = [line for line in result.stderr.splitlines() if "error:" in line]
            first = errors[0].replace(directory, "") if errors else result.stderr.strip()
            return f"{what}: {first}"

        items = [(f"{header} ({layout}) as {label}", CLANG_TARGET, "iphoneos", language, standard, search, unit)
                 for header, layout, unit, search in runs for label, language, standard in HEADER_LANGUAGES]
        # A missing layout test is the layout check's to report.
        if at(LAYOUT_TEST).exists():
            items += [(f"{Path(LAYOUT_TEST).name} for {target}", target, sdk, "objective-c", "-std=gnu11",
                       ("-F", str(work)), at(LAYOUT_TEST)) for target, sdk in LAYOUT_SLICES]
        with ThreadPoolExecutor(max_workers=8) as pool:
            return len(items), [problem for problem in pool.map(run, items) if problem]


def check_compile(names, clang, require, rep):
    name = "compile: the public headers compile alone in every language (12.3)"
    if clang and not Path(clang).exists():
        rep.check(False, name, f"cannot run {clang}")
        return
    compiler = clang or xcrun("--find", "clang")
    sdks = {sdk: xcrun("--sdk", sdk, "--show-sdk-path") for sdk in ("iphoneos", "iphonesimulator")}
    if compiler is None or None in sdks.values():
        if require:
            rep.check(False, name, "Xcode's clang and iOS SDK were not found and --require-compile was given")
        else:
            rep.skip(name, "Xcode's clang and iOS SDK were not found; install Xcode")
        return
    if not names:
        rep.check(False, name, f"no headers under {INCLUDE}")
        return
    count, problems = compile_problems(compiler, sdks, names)
    rep.check(not problems, f"{name} ({count} compiles)", "; ".join(problems))


def check_layout(structs, rep):
    """The layout test against the struct declarations of the headers. The numbers
    are the test's to compare with the compiler: a row that is not there compares nothing."""
    name = "layout: every struct and field of the headers is in the layout test, with a size that is a multiple of 8 (12.1)"
    text = read(LAYOUT_TEST, rep, name)
    if text is None:
        return
    code = common.strip_comments(text)
    rows = re.findall(r"^\s*LAYOUT_SIZE\((\w+), (\d+)\);", code, re.M)
    sizes = [struct for struct, _ in rows]
    fields = re.findall(r"^\s*LAYOUT_FIELD\((\w+), (\w+), \d+\);", code, re.M)
    problems, wanted = [], set()
    # Rule 5 of part 1, 1.1: `compile` holds the numbers to the compiler, so this holds the structs.
    problems += [f"{struct}: sizeof {size} is not a multiple of 8" for struct, size in rows if int(size) % 8]
    for struct, body in structs.items():
        for field in body.split("; "):
            match = re.search(r"(\w+)(?:\[\w*\])?$", field)
            if match:
                wanted.add((struct, match.group(1)))
            else:
                problems.append(f"{struct}: cannot read the field '{field}'")
    allowed = [re.sub(r"^#\s*", "#", common.normalise(line)) for line in LAYOUT_DIRECTIVES]
    if preprocessor_lines(text) != allowed:
        problems.append(f"the preprocessor lines of the layout test are not {', '.join(LAYOUT_DIRECTIVES)}")
    project = read(PBXPROJ, rep, name)
    if project is not None and Path(LAYOUT_TEST).name in project:
        problems.append(f"the project names {Path(LAYOUT_TEST).name}: it must not leave it out of the target")
    for label, names in (("has no LAYOUT_SIZE row", set(structs) - set(sizes)),
                         ("has a LAYOUT_SIZE row and is not in the headers", set(sizes) - set(structs)),
                         ("has more than one LAYOUT_SIZE row", {s for s in sizes if sizes.count(s) > 1})):
        problems += [f"{struct} {label}" for struct in sorted(names)]
    for label, names in (("has no LAYOUT_FIELD row", wanted - set(fields)),
                         ("has a LAYOUT_FIELD row and is not in the headers", set(fields) - wanted),
                         ("has more than one LAYOUT_FIELD row", {f for f in fields if fields.count(f) > 1})):
        problems += [f"{struct}.{field} {label}" for struct, field in sorted(names)]
    rep.check(not problems and structs, f"{name} ({len(structs)} structs, {len(wanted)} fields)",
              "; ".join(problems) or "the headers declare no structs")


def build_settings(body):
    """The settings of a buildSettings block: KEY -> text, or a tuple for a list."""
    settings = {}
    for key, value in re.findall(r'^\s*("[^"\n]+"|[^\s=]+) = (\(.*?\)|[^;\n]*);', body, re.M | re.S):
        key = key.strip('"')
        if value.startswith("("):
            settings[key] = tuple(item.strip('"') for item in re.findall(r'"[^"]*"|[^\s,]+', value[1:-1]))
        else:
            settings[key] = value.strip('"')
    return settings


def project_configurations(text):
    """(kind, name) of each configuration list -> {configuration: settings}."""
    blocks = {identifier: (name, build_settings(body)) for identifier, body, name in re.findall(
        r"(\w{24}) /\* \w+ \*/ = \{\s*isa = XCBuildConfiguration;\s*buildSettings = \{(.*?)\n\t\t\t\};\s*name = (\w+);",
        text, re.S)}
    lists = {}
    for kind, name, members in re.findall(
            r'/\* Build configuration list for (\w+) "(\w+)" \*/ = \{\s*isa = XCConfigurationList;\s*buildConfigurations = \((.*?)\);',
            text, re.S):
        lists[(kind, name)] = dict(blocks[i] for i in re.findall(r"\b\w{24}\b", members) if i in blocks)
    return lists


def check_settings(rep):
    """The Debug difference of part 1, 5.4 is safe only while it stays in Debug."""
    name = "settings: the framework target has part 1, 5.4 in Release and Debug differs only for @testable (part 1, 5.4)"
    text, scheme = read(PBXPROJ, rep, name), read(SCHEME, rep, name)
    if text is None or scheme is None:
        return
    # A configuration with an xcconfig is not one this reading finds, so it fails below.
    lists = project_configurations(text)
    target = lists.get(("PBXNativeTarget", "IosLibraryCApi"), {})
    project = lists.get(("PBXProject", "IosLibraryCApi"), {})
    if not {"Debug", "Release"} <= set(target) or not {"Debug", "Release"} <= set(project):
        rep.check(False, name, "the project does not have Debug and Release for the framework target and itself")
        return
    problems = []
    release, debug = target["Release"], target["Debug"]
    effective = {**project["Release"], **release}
    for key, value in FRAMEWORK_SETTINGS.items():
        if effective.get(key) != value:
            problems.append(f"Release has {key} = {effective.get(key)}, part 1, 5.4 says {value}")
    conditional = sorted(key for key in {*release, *debug} if "[" in key)
    if conditional:
        problems.append(f"settings by condition cannot be compared: {', '.join(conditional)}")
    differing = {key for key in {*release, *debug} if release.get(key) != debug.get(key)}
    for key in sorted(differing - set(DEBUG_ONLY)):
        problems.append(f"{key} differs between Debug and Release")
    for key, value in DEBUG_ONLY.items():
        if debug.get(key) != value:
            problems.append(f"Debug has {key} = {debug.get(key)}, not {value}")
        if key not in FRAMEWORK_SETTINGS and key in release:
            problems.append(f"Release has {key}, which is for Debug")
    if not re.search(r'<ArchiveAction\s+buildConfiguration = "Release"', scheme):
        problems.append("the scheme does not archive Release")
    rep.check(not problems, name, "; ".join(problems))


def check_install_result(rep):
    """Every case of the library's result has a line of its own in the receiver."""
    name = "install: every case of NotificationDelegateInstallResult is mapped (part 1, 1.4)"
    source, receiver = read(INSTALL_RESULT, rep, name), read(RECEIVER, rep, name)
    if source is None or receiver is None:
        return
    cases = enum_cases(swift_code(source), "NotificationDelegateInstallResult")
    missing = [case for case in cases if not re.search(rf"\bcase \.{case}\s*:", swift_code(receiver))]
    rep.check(cases and not missing, f"{name} ({len(cases)} cases)",
              f"the receiver has no case for {', '.join(missing)}" if cases else "no cases were read")


def exported_symbols(output):
    """architecture -> the names in nm output. A fat binary has a heading per
    architecture; any other has one section, named after nothing."""
    sections, current = {}, ""
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.endswith(":"):
            heading = re.search(r"\(for architecture (\w+)\):$", line)
            current = heading.group(1) if heading else ""
            # The heading alone is a section: an architecture that exports
            # nothing prints no line after it.
            if heading:
                sections.setdefault(current, set())
            continue
        sections.setdefault(current, set()).add(line.split()[-1])
    return sections


def thin_architecture(library):
    """The architecture in the Mach-O header of a binary with one, or None."""
    with open(library, "rb") as binary:
        header = binary.read(8)
    if header[:4] != MACH_O_MAGIC:
        return None
    return MACH_O_CPU_TYPES.get(int.from_bytes(header[4:8], "little"))


def check_symbols(library, nm, architectures, implemented, rep):
    name = "symbols: the library exports the _ntk_* of 8.2 less what is not implemented yet, and nothing else (AP-15)"
    if library is None:
        rep.skip(name, "no --library (run after the build)")
        return
    if not Path(library).exists():
        rep.check(False, name, f"cannot read {library}")
        return
    tool = nm or shutil.which("nm")
    if tool is None:
        rep.check(False, name, "no nm (give --nm)")
        return
    if not Path(tool).exists():
        rep.check(False, name, f"cannot run {tool}")
        return
    try:
        # -arch all: without it, nm lists only the host's slice of a fat binary.
        finished = subprocess.run([tool, "-arch", "all", "-gU", str(library)], capture_output=True, text=True)
    except OSError as error:
        rep.check(False, name, f"cannot run {tool}: {error}")
        return
    if finished.returncode != 0:
        rep.check(False, name, f"{tool} failed: {finished.stderr.strip()}")
        return
    sections = exported_symbols(finished.stdout)
    wanted = {f"_{function}" for function in implemented}
    problems = [] if sections else ["nm listed nothing"]
    if architectures is not None:
        has = {thin_architecture(library) if a == "" else a for a in sections}
        if has != set(architectures.split(",")):
            problems.append(f"the library has the architectures {sorted(map(str, has))}, not {architectures}")
    for architecture, exported in sorted(sections.items()):
        where = f"{architecture}: " if architecture else ""
        if exported - wanted:
            problems.append(f"{where}exported but not an implemented function of 8.2: {', '.join(sorted(exported - wanted))}")
        if wanted - exported:
            problems.append(f"{where}implemented but not exported: {', '.join(sorted(wanted - exported))}")
    rep.check(not problems, f"{name} ({len(wanted)} symbols, {len(sections)} architectures)", "; ".join(problems))


def parse_arguments(argv):
    """{option: value} for the options with a value, and the flags; None on a usage error."""
    with_value = {"--root", "--library", "--nm", "--architectures", "--clang"}
    flags = {"--design-only", "--require-compile", "--require-complete"}
    parsed, rest = {}, list(argv)
    while rest:
        argument = rest.pop(0)
        if argument in with_value:
            if argument in parsed:
                print(f"{argument} given twice\n{USAGE}", file=sys.stderr)
                return None
            if not rest or rest[0].startswith("--"):
                print(f"{argument} needs a value\n{USAGE}", file=sys.stderr)
                return None
            parsed[argument] = rest.pop(0)
        elif argument in flags:
            parsed[argument] = True
        else:
            print(f"unknown argument {argument}\n{USAGE}", file=sys.stderr)
            return None
    for option in ("--nm", "--architectures"):
        if option in parsed and "--library" not in parsed:
            print(f"{option} needs --library\n{USAGE}", file=sys.stderr)
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

    rep = Report("C ABI contract (iOS)")
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
    if design_only:
        # Anywhere under the module, not only where 5.1 puts them: a header
        # written elsewhere must not leave this mode reading the appendix.
        present = sorted(str(p.relative_to(ROOT)) for p in at(CAPI).rglob("*.h"))
        rep.check(not present, "design only: no public header exists yet",
                  f"{', '.join(present)} exist; drop --design-only so they are checked")
    else:
        texts = {}
        for label in appendix:
            text = read(f"{INCLUDE}/{label}", rep, f"the public header {label}")
            if text is not None:
                texts[label] = text
        for path in sorted(at(INCLUDE).glob("*.h")):
            rep.check(path.name in appendix, f"the public header {path.name}", "Appendix A does not have it")
    headers = {h: declarations(t) for h, t in texts.items()} if texts is not None else None

    ops = common.c_functions_of_ops(design, 2)
    listed = common.check_functions(design, ops, expected, headers, rep)
    if headers is None:
        rep.skip("signatures: the headers declare what Appendix A does", "--design-only")
    else:
        problems = [p for label, text in texts.items() for p in shape_problems(label, text)]
        problems += [p for label, text in texts.items() for p in against_appendix_problems(label, text, appendix)]
        common.check_signatures(expected, merged(headers), rep, problems)
    check_appendix_shape(appendix, rep)
    check_operations(design, expected, rep)
    check_swift(design, expected["function"], rep)
    check_behaviours(design, readme, expected, rep)
    values = merged(headers)["value"] if headers is not None else expected["value"]
    check_values(design, values, rep)
    check_cases(design, rep)
    common.check_error_numbers(ROOT, {"iOS": values, "Android": android_values(rep)}, rep,
                               other_features=("android",), every_os=True)
    named = headers if headers is not None else {h: declarations(c) for h, c in appendix.items()}
    common.check_names(named, FEATURE_OF, COMMON_FUNCTIONS, rep,
                       "names: every function, type and constant follows the naming rules")
    check_async_names(merged(named)["function"], rep)
    if texts is not None:
        common.check_ascii(texts, rep, "the public headers")
    else:
        common.check_ascii(appendix, rep, "the headers of Appendix A")
    check_common(texts.get("Common.h") if texts is not None else appendix.get("Common.h"), rep)
    if headers is None:
        for check in ("entries", "public", "modulemap", "compile", "layout", "settings", "install"):
            rep.skip(f"{check}: needs the headers and the capi's sources", "--design-only")
    else:
        sources = capi_swift_code(rep, "entries and public: the capi's Swift sources")
        if sources is not None:
            check_entries(sources, merged(headers)["function"], rep)
            check_public(sources, rep)
        present = sorted(path.name for path in at(INCLUDE).glob("*.h"))
        module_map = read(MODULE_MAP, rep, "modulemap: the module map")
        if module_map is not None:
            check_module_map(module_map, present, rep)
        check_compile(present, parsed.get("--clang"), parsed.get("--require-compile", False), rep)
        check_layout(merged(headers)["struct"], rep)
        check_settings(rep)
        check_install_result(rep)
    check_complete(parsed.get("--require-complete", False), rep)
    check_symbols(library, nm, parsed.get("--architectures"), listed - set(NOT_IMPLEMENTED_YET), rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
