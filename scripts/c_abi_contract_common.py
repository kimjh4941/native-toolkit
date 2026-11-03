"""What the C ABI contract checkers of every OS share.

The checkers are one file per OS (check_c_abi_contract_<os>.py, Android C ABI
design part 2, 0.3). This module holds what does not depend on the OS:

  reading     the report, reading a file so that a missing one fails the check
              that needed it (R-30), C declarations, the design's tables and
              Appendix A.
  checks      the ones every OS runs the same way: the functions of 8.2, the
              headers against Appendix A, the error enumerations against the
              tables of chapter 11 and against the table of numbers the OSes
              share (iOS C ABI design part 1, P1-7), the naming rules, ASCII,
              and the Common.h of any number of OSes against each other
              (Android C ABI design part 1, 5.2).

Every function takes the paths it reads; nothing here knows where an OS keeps
its files.
"""

import json
import re
from pathlib import Path

# One table of numbers per feature, across the OSes that use it (P1-7).
ERROR_NUMBERS = "scripts/c_abi_error_numbers.json"
# Constants only one OS's Common.h may define (Android C ABI design part 1, 5.2),
# as a regular expression per OS. An OS that is not named may define none.
OS_ONLY_CONSTANTS = {"Windows": r"^NTK_SYSTEM_CODE_\w+$"}
# The initializers a public header may give an enum value: a number, or a bit
# written as 1u << N. Anything else is not guessed at: it is left unread.
ENUM_VALUE = re.compile(r"(NTK_\w+)\s*=\s*(-?(?:0[xX][0-9A-Fa-f]+|\d+))[uU]?(?:\s*<<\s*(\d+))?")


class Report:
    def __init__(self, title="C ABI contract"):
        self.title = title
        self.lines = []
        self.failed = False

    def check(self, condition, name, detail=""):
        if condition:
            self.lines.append(f"  OK   {name}")
        else:
            self.lines.append(f"  FAIL {name}: {detail}")
            self.failed = True

    def skip(self, name, reason):
        """A check the caller chose not to run. Never used for a missing file."""
        self.lines.append(f"  SKIP {name}: {reason}")

    def dump(self):
        print(f"== {self.title}")
        for line in self.lines:
            print(line)
        return not self.failed


def read(root, fragment, rep, check_name):
    """The file's text, or None and a failure of the check that needed it."""
    path = Path(root) / fragment
    if not path.exists():
        rep.check(False, check_name, f"cannot read {fragment}")
        return None
    return path.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Reading C declarations: the headers and Appendix A are parsed the same way
# ---------------------------------------------------------------------------

def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def normalise(text):
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"\s*\*\s*", "* ", text)
    text = re.sub(r"\s*,\s*", ", ", text)
    text = re.sub(r"\(\s*", "(", text)
    text = re.sub(r"\s*\)", ")", text)
    return text.replace("* )", "*)").replace("* ,", "*,").strip()


def declarations(text):
    """Everything a header declares, by kind and name, as normalised text.

    What fits no kind goes to "unread", so that a declaration this reading
    does not know cannot pass for one that is not there."""
    text = strip_comments(text)
    text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    text = text.replace('extern "C" {', " ")

    found = {"function": {}, "callback": {}, "struct": {}, "value": {}, "typedef": {}, "unread": {}}
    for name, body in re.findall(r"typedef struct (\w+) \{(.*?)\} \1;", text, re.S):
        fields = [normalise(f) for f in body.split(";") if f.strip()]
        found["struct"][name] = "; ".join(fields)
    text = re.sub(r"typedef struct (\w+) \{.*?\} \1;", " ", text, flags=re.S)
    for body in re.findall(r"enum \{(.*?)\};", text, re.S):
        for item in (part.strip() for part in body.split(",")):
            match = ENUM_VALUE.fullmatch(item)
            if match:
                found["value"][match.group(1)] = int(match.group(2), 0) << int(match.group(3) or 0)
            elif item:
                found["unread"][normalise(item)] = "enum"
    text = re.sub(r"enum \{.*?\};", " ", text, flags=re.S)

    for statement in text.split(";"):
        statement = normalise(statement.replace("{", " ").replace("}", " "))
        if not statement:
            continue
        callback = re.match(r"^typedef (.+?)\(NTK_CALL\* (\w+)\)\((.*)\)$", statement)
        if callback:
            found["callback"][callback.group(2)] = f"{callback.group(1).strip()} ({callback.group(3)})"
            continue
        function = re.match(r"^(.+?) NTK_CALL (ntk_\w+)\((.*)\)$", statement)
        if function:
            found["function"][function.group(2)] = f"{function.group(1)} ({function.group(3)})"
            continue
        typedef = re.match(r"^typedef (.+) (\w+)$", statement)
        if typedef:
            found["typedef"][typedef.group(2)] = typedef.group(1)
            continue
        found["unread"][statement] = "statement"
    return found


def merged(headers):
    """The declarations of several headers as one, by kind."""
    every = {"function": {}, "callback": {}, "struct": {}, "value": {}, "typedef": {}, "unread": {}}
    for decl in headers.values():
        for kind, items in decl.items():
            every[kind].update(items)
    return every


def macros(text):
    """NAME -> value of every #define, the include guard aside. A name defined
    twice (the two sides of an #if) keeps every value, in order."""
    found = {}
    for line in strip_comments(text).splitlines():
        match = re.match(r"^\s*#\s*define\s+(\w+)(?:\s+(.*?))?\s*$", line)
        if match and not match.group(1).endswith("_H"):
            found.setdefault(match.group(1), []).append(match.group(2) or "")
    return found


NTK_CALL_BLOCK = ["#if defined(_MSC_VER)", "#define NTK_CALL __cdecl", "#else", "#define NTK_CALL", "#endif"]
PACK_PUSH, PACK_POP = "#pragma pack(push, 8)", "#pragma pack(pop)"


def directive_lines(code):
    """(start, end, normalised line) of every preprocessor line of code without comments."""
    found = []
    for match in re.finditer(r"^[ \t]*#.*$", code, re.M):
        found.append((match.start(), match.end(), re.sub(r"^#\s*", "#", normalise(match.group(0)))))
    return found


def directive_problems(label, text, include_blocks=()):
    """Preprocessor lines a public header may not have, and the shape they
    must give it.

    The declarations are read with every # line dropped, so a declaration
    inside an #if would read as unconditional, and a header that lost its
    extern "C" or its include guard would read the same. A header may only
    have: its include guard, opened first and closed last; #includes; the two
    #ifdef __cplusplus blocks that open and close extern "C" around every
    declaration; in Common.h, the NTK_CALL block and #defines; and, when it
    has structs, one #pragma pack(push, 8) before the first and one
    #pragma pack(pop) after the last, with no # line inside any struct.

    include_blocks: conditional includes an OS's headers may have besides these
    (iOS's two ways of including Common.h, iOS C ABI design part 1, 5.2). Each
    must stand before extern "C", with nothing but its own lines in it: a
    declaration inside would be seen by one branch only."""
    problems = []
    code = strip_comments(text)
    directives = directive_lines(code)
    lines = [line for _, _, line in directives]

    allowed = set()
    if label == "Common.h":
        for index in range(len(lines) - len(NTK_CALL_BLOCK) + 1):
            if lines[index:index + len(NTK_CALL_BLOCK)] == NTK_CALL_BLOCK:
                allowed = set(range(index, index + len(NTK_CALL_BLOCK)))
                break
    for block in include_blocks:
        for index in range(len(lines) - len(block) + 1):
            if lines[index:index + len(block)] != list(block):
                continue
            allowed |= set(range(index, index + len(block)))
            span = code[directives[index][0]:directives[index + len(block) - 1][1]]
            if re.sub(r"^[ \t]*#.*$", "", span, flags=re.M).strip():
                problems.append(f"{label} has more than its #include lines inside '{block[0]}'")
            if "#ifdef __cplusplus" in lines[:index]:
                problems.append(f"{label} has '{block[0]}' inside extern \"C\"")

    # The include guard: the first two lines, and its #endif the last.
    guard = re.fullmatch(r"#ifndef (NATIVETOOLKITC_\w+_H)", lines[0]) if lines else None
    if not guard or len(lines) < 2 or lines[1] != f"#define {guard.group(1)}":
        problems.append(f"{label} does not open with its include guard")
    stack = []
    for index, line in enumerate(lines):
        if index in allowed:
            continue
        if line.startswith(("#ifndef", "#ifdef", "#if ")):
            stack.append((index, line))
            if line not in ("#ifdef __cplusplus",) and index != 0:
                problems.append(f"{label} has '{line}'")
        elif line == "#endif":
            if not stack:
                problems.append(f"{label} has an #endif that closes nothing")
                continue
            opened, _ = stack.pop()
            if opened == 0 and index != len(lines) - 1:
                problems.append(f"{label} closes its include guard before its last line")
        elif index == 1 and guard:
            continue
        elif re.fullmatch(r"#include [<\"][\w/.]+[>\"]", line) or line in (PACK_PUSH, PACK_POP):
            continue
        elif label == "Common.h" and re.fullmatch(r"#define NTK_\w+ \S+", line):
            continue
        else:
            problems.append(f"{label} has '{line}'")
    if stack:
        problems.append(f"{label} leaves {', '.join(line for _, line in stack)} open")

    # extern "C": two #ifdef __cplusplus blocks, the opening and the closing,
    # with every declaration between them.
    blocks = list(re.finditer(r"^[ \t]*#\s*ifdef\s+__cplusplus\s*\n(.*?)^[ \t]*#\s*endif", code, re.S | re.M))
    if [normalise(b.group(1)) for b in blocks] != ['extern "C" {', "}"]:
        problems.append(f"{label} does not open and close extern \"C\" in two #ifdef __cplusplus blocks")
    else:
        outside = list(code)
        for start, end, _ in directives:
            outside[start:end] = " " * (end - start)
        for block in blocks:
            outside[block.start():block.end()] = " " * (block.end() - block.start())
        stray = [m.start() for m in re.finditer(r"\S", "".join(outside))]
        if stray and (stray[0] < blocks[0].end() or stray[-1] > blocks[1].start()):
            problems.append(f"{label} declares something outside extern \"C\"")

    # #pragma pack around the structs, and no # line inside one.
    structs = [m.span() for m in re.finditer(r"typedef struct (\w+) \{.*?\} \1;", code, re.S)]
    pushes = [start for start, _, line in directives if line == PACK_PUSH]
    pops = [start for start, _, line in directives if line == PACK_POP]
    if structs:
        if len(pushes) != 1 or len(pops) != 1:
            problems.append(f"{label} has {len(pushes)} {PACK_PUSH} and {len(pops)} {PACK_POP} around its structs")
        elif not pushes[0] < structs[0][0] or not pops[0] > structs[-1][1]:
            problems.append(f"{label} declares a struct outside {PACK_PUSH} ... (pop)")
        for start, _, line in directives:
            if any(a < start < b for a, b in structs):
                problems.append(f"{label} has '{line}' inside a struct")
    elif len(pushes) != len(pops) or len(pushes) > 1:
        problems.append(f"{label} has {len(pushes)} {PACK_PUSH} and {len(pops)} {PACK_POP}")
    return problems


def appendix_code(design):
    """The C of Appendix A, all code blocks together."""
    start = design.find("## 付録 A")
    if start < 0:
        return None
    return "\n".join(re.findall(r"```c\n(.*?)```", design[start:], re.S))


def appendix_headers(design):
    """Header name -> its C, for an Appendix A with one '### A.N `NativeToolkitC/X.h`' per header."""
    start = design.find("## 付録 A")
    if start < 0:
        return None
    found = {}
    for name, code in re.findall(r"### A\.\d+ `NativeToolkitC/(\w+\.h)`.*?```c\n(.*?)```", design[start:], re.S):
        found[name] = code
    return found


# ---------------------------------------------------------------------------
# Reading the design's tables
# ---------------------------------------------------------------------------

def table_rows(text, heading):
    start = text.find(heading)
    if start < 0:
        return []
    rows, started = [], False
    for line in text[start:].splitlines()[1:]:
        if line.startswith("#") and started:
            break
        if not line.startswith("|"):
            if started:
                break
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if all(set(c) <= set("-: ") for c in cells):
            continue
        started = True
        rows.append(cells)
    return rows[1:] if rows else []


def backticked(cell):
    return re.findall(r"`([^`]+)`", cell)


def op_range(cell):
    """The operations a cell names; each part between 、 is an ID or a range."""
    ids = []
    for part in re.split(r"[、,]", cell):
        numbers = [int(n) for n in re.findall(r"OP-(\d+)", part)]
        if any(mark in part for mark in ("〜", "～", "~")) and len(numbers) >= 2:
            ids.extend(range(numbers[0], numbers[-1] + 1))
        else:
            ids.extend(numbers)
    return [f"OP-{n:02d}" for n in ids]


def c_functions_of_ops(design, column):
    """OP -> the C function named first in the given column of 8.1."""
    table = {}
    for cells in table_rows(design, "### 8.1"):
        if len(cells) <= column or not cells[0].startswith("OP-"):
            continue
        c = backticked(cells[column])
        if c:
            table[cells[0]] = c[0].split("(")[0].strip()
    return table


def section_8_2(design, ops):
    """The functions of 8.2 and the count each row and the total claim.

    ops maps OP -> C function, for the rows that say '8.1 の N 関数'."""
    names, problems, total = [], [], None
    for cells in table_rows(design, "### 8.2"):
        if len(cells) < 4:
            continue
        count = re.search(r"\d+", cells[3])
        count = int(count.group(0)) if count else None
        if cells[0] == "合計":
            total = count
            continue
        listed = backticked(cells[2])
        from_ops = re.search(r"8\.1 の (\d+) 関数", cells[2])
        if from_ops:
            row = [ops[op] for op in op_range(cells[1]) if op in ops]
            if int(from_ops.group(1)) != len(row):
                problems.append(f"the row '{cells[1]}' says '8.1 の {from_ops.group(1)} 関数' but 8.1 has {len(row)}")
        elif any(t.startswith("_") for t in listed):
            # "_create, _free, ... (each follows ntk_notification_content)"
            prefix = [t for t in listed if t.startswith("ntk_")]
            row = [prefix[0] + t for t in listed if t.startswith("_")] if prefix else []
        else:
            row = [t for t in listed if t.startswith("ntk_")]
        if count is not None and count != len(row):
            problems.append(f"the row '{cells[1]}' says {count} but names {len(row)}")
        names.extend(row)
    return names, total, problems


def error_table(design, heading):
    """NAME -> value from a chapter 11 table, the name as the table writes it."""
    return dict(error_table_rows(design, heading))


def error_table_rows(design, heading):
    """(NAME, value) of every row of a chapter 11 table, a name named twice included."""
    rows = []
    for cells in table_rows(design, heading):
        if len(cells) >= 2 and cells[0].isdigit():
            for name in backticked(cells[1]):
                rows.append((name, int(cells[0])))
    return rows


# ---------------------------------------------------------------------------
# The checks every OS runs the same way
# ---------------------------------------------------------------------------

def check_functions(design, ops, expected, headers, rep):
    """The functions of 8.2 against Appendix A and, unless headers is None, the
    headers. ops maps OP -> C function. Returns the functions of 8.2."""
    name = "functions: headers, 8.2 and Appendix A agree"
    in_8_2, total, problems = section_8_2(design, ops)
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


def takes_callback(signature):
    """Whether a declaration takes a callback of its own and a release."""
    callbacks = set(re.findall(r"\bntk_\w+_fn\b", signature))
    return "ntk_release_fn" in callbacks and len(callbacks) > 1


def is_listener(function, signature):
    return bool(re.fullmatch(r"ntk_\w+_add_\w+_listener", function)) and takes_callback(signature)


def check_signatures(expected, actual, rep, problems=None):
    """expected: the declarations of Appendix A; actual: those of the headers,
    merged. problems: what the caller already found (directive_problems)."""
    name = "signatures: the headers declare what Appendix A does"
    problems = list(problems or [])
    for item in sorted(set(expected["unread"]) | set(actual["unread"])):
        problems.append(f"'{item}' is not a declaration or an initializer this check can read")
    for kind in ("function", "callback", "struct", "value", "typedef"):
        for item in sorted(set(expected[kind]) | set(actual[kind])):
            want, got = expected[kind].get(item), actual[kind].get(item)
            if want is None:
                problems.append(f"{kind} {item} is not in Appendix A")
            elif got is None:
                problems.append(f"{kind} {item} is not declared")
            elif want != got:
                problems.append(f"{kind} {item}: Appendix A has '{want}', the header '{got}'")
    compared = sum(len(v) for v in expected.values())
    rep.check(not problems and compared > 0, f"{name} ({compared} declarations)",
              "; ".join(problems) or "nothing was compared")


def error_table_problems(design, values, error_tables):
    """Where the error enumerations and the tables of chapter 11 differ.

    error_tables maps a constant prefix to its heading. A table may write the
    whole name or only what follows the prefix."""
    problems = []
    for prefix, heading in sorted(error_tables.items()):
        table = {}
        for written, value in error_table_rows(design, heading):
            key = written[len(prefix):] if written.startswith(prefix) else written
            if key in table:
                problems.append(f"{heading} names {key} twice")
            table[key] = value
        mine = {k[len(prefix):]: v for k, v in values.items() if k.startswith(prefix)}
        if not table:
            problems.append(f"no table under {heading}")
            continue
        if table != mine:
            differ = sorted(set(table.items()) ^ set(mine.items()))
            problems.append(f"{heading} and {prefix}* differ in {differ}")
    return problems


def error_numbers(text, problems):
    """feature -> {NAME: number} from the text of the table, its problems added.

    The table holds to P1-7 by its shape: a name appears once in a feature, so
    it has one number; a number belongs to one name, so no OS can use it for
    another; and the numbers run from 0 without a hole, because a number no OS
    ever used belongs to nobody and a later value would not know it was free."""
    def no_repeats(pairs):
        names = [name for name, _ in pairs]
        for name in sorted({n for n in names if names.count(n) > 1}):
            problems.append(f"the table names {name} twice in one object")
        return dict(pairs)
    try:
        table = json.loads(text, object_pairs_hook=no_repeats)
    except ValueError as error:
        problems.append(f"the table is not JSON: {error}")
        return {}
    if not isinstance(table, dict) or not table:
        problems.append("the table has no features")
        return {}
    for feature, numbers in table.items():
        if not re.fullmatch(r"[a-z]+", feature) or not isinstance(numbers, dict) or not numbers:
            problems.append(f"{feature} is not a feature with names and numbers")
            table[feature] = {}
            continue
        seen = {}
        for name, number in numbers.items():
            # bool is an int in Python, and true would read as 1.
            if not re.fullmatch(r"[A-Z][A-Z0-9_]*", name) or type(number) is not int or number < 0:
                problems.append(f"{feature}: {name} = {number!r} is not a NAME and a number")
                continue
            if number in seen:
                problems.append(f"{feature}: {number} is both {seen[number]} and {name}")
            seen[number] = name
        holes = sorted(set(range(max(seen, default=-1) + 1)) - set(seen))
        if holes:
            problems.append(f"{feature}: no name has {', '.join(map(str, holes))}")
    return table


def error_number_problems(table, values_by_os, other_features=(), every_os=False):
    """Where the headers of the OSes and the table of numbers differ.

    values_by_os maps an OS to its NTK_ constants. Every error of a header must
    be in the table with the same number; a name of the table an OS lacks is a
    gap there. every_os says values_by_os holds all the OSes the table is for,
    so a name none of them declares is stale. other_features are enumerations
    one OS has by itself (Android.h), which the table is not for."""
    problems = []
    declared = {}
    for os_name, values in values_by_os.items():
        for constant, number in sorted(values.items()):
            # The feature is whatever stands before _ERROR_, so that a prefix
            # the table does not know is reported rather than passed over.
            match = re.fullmatch(r"NTK_(\w+?)_ERROR_(\w+)", constant)
            if not match or match.group(1).lower() in other_features:
                continue
            feature, name = match.group(1).lower(), match.group(2)
            declared.setdefault((os_name, feature), set()).add(name)
            if feature not in table:
                problems.append(f"{os_name}: {constant} belongs to no feature of the table")
            elif name not in table[feature]:
                problems.append(f"{os_name}: {constant} = {number} is not in the table")
            elif table[feature][name] != number:
                problems.append(f"{os_name}: {constant} = {number}, the table says {table[feature][name]}")
        for feature in sorted(table):
            if (os_name, feature) not in declared:
                problems.append(f"{os_name}: no header declares an error of {feature}")
    if every_os:
        for feature, numbers in sorted(table.items()):
            everywhere = set().union(*(declared.get((o, feature), set()) for o in values_by_os))
            for name in sorted(set(numbers) - everywhere):
                problems.append(f"{feature}: no OS declares {name}, which the table has")
    return problems


def check_error_numbers(root, values_by_os, rep, other_features=(), every_os=False):
    oses = " and ".join(values_by_os)
    name = f"numbers: the {oses} errors match {ERROR_NUMBERS} (P1-7)"
    text = read(root, ERROR_NUMBERS, rep, name)
    if text is None:
        return
    problems = []
    table = error_numbers(text, problems)
    problems += error_number_problems(table, values_by_os, other_features, every_os)
    count = sum(len(numbers) for numbers in table.values())
    rep.check(not problems and count > 0, f"{name} ({count} names)", "; ".join(problems) or "the table is empty")


def check_names(headers, feature_of, common_functions, rep,
                name="names: every function, type and constant follows 1.1"):
    problems = [] if headers else ["no header was read"]
    for header, decl in headers.items():
        feature = feature_of.get(header)
        for function in decl["function"]:
            if not re.match(r"^ntk_[a-z0-9]+(_[a-z0-9]+)*$", function):
                problems.append(f"{function} is not lower case words joined by one underscore")
            elif feature and not function.startswith(f"ntk_{feature}_"):
                problems.append(f"{function} in {header} does not start with ntk_{feature}_")
            elif not feature and not common_functions.match(function):
                problems.append(f"{function} in {header} names no feature and is not a common handle")
        for kind in ("callback", "struct", "typedef"):
            for type_name in decl[kind]:
                if feature and not type_name.startswith(f"ntk_{feature}_"):
                    problems.append(f"{kind} {type_name} in {header} does not start with ntk_{feature}_")
                if not type_name.startswith("ntk_"):
                    problems.append(f"{kind} {type_name} in {header} does not start with ntk_")
        for callback in decl["callback"]:
            if not callback.endswith("_fn"):
                problems.append(f"callback {callback} does not end in _fn")
        for constant in decl["value"]:
            if feature and not constant.startswith(f"NTK_{feature.upper()}_"):
                problems.append(f"{constant} in {header} does not start with NTK_{feature.upper()}_")
    rep.check(not problems, name, "; ".join(problems))


def non_ascii_lines(label, data):
    return [f"{label}:{number}" for number, line in enumerate(data.splitlines(), 1)
            if any(byte > 127 for byte in line)]


def check_ascii(texts, rep, label):
    problems = [] if texts else ["nothing was read"]
    for header, text in texts.items():
        problems.extend(non_ascii_lines(header, text.encode("utf-8")))
    rep.check(not problems, f"ascii: {label} are ASCII only", ", ".join(problems))


def common_header_problems(headers, os_only=OS_ONLY_CONSTANTS):
    """Where the Common.h of several OSes break the rules of Android C ABI
    design part 1, 5.2.

    headers maps an OS to its header text, in any number of two or more;
    os_only maps an OS to the regular expression of the constants only it may
    define."""
    problems = []
    if len(headers) < 2:
        problems.append(f"{len(headers)} Common.h cannot be compared")
    decls = {label: declarations(text) for label, text in headers.items()}
    # One: the incomplete types, ntk_release_fn and the common functions,
    # the same once whitespace and comments are gone.
    for kind in ("function", "callback", "typedef"):
        for item in sorted(set().union(*(set(decl[kind]) for decl in decls.values()))):
            having = {label: decl[kind][item] for label, decl in decls.items() if item in decl[kind]}
            lacking = [label for label in decls if label not in having]
            if len(having) == 1:
                problems.append(f"{kind} {item} is only in the {next(iter(having))} Common.h")
            elif lacking:
                problems.append(f"{kind} {item} is not in the {' and '.join(lacking)} Common.h")
            if len(set(having.values())) > 1:
                written = ", ".join(f"{label} has '{text}'" for label, text in having.items())
                problems.append(f"{kind} {item}: {written}")
    for kind in ("struct", "value"):
        for label, decl in decls.items():
            if decl[kind]:
                problems.append(f"the {label} Common.h declares {kind}s: {', '.join(sorted(decl[kind]))}")
    if not all(decl["function"] for decl in decls.values()):
        problems.append("no common function was compared")

    # Two: NTK_CALL is __cdecl only under MSVC, and empty everywhere else.
    for label, text in headers.items():
        guarded = re.search(r"#if defined\(_MSC_VER\)\s*#define NTK_CALL __cdecl\s*#else\s*#define NTK_CALL[ \t]*\n\s*#endif",
                            strip_comments(text))
        if not guarded:
            problems.append(f"the {label} Common.h does not define NTK_CALL as __cdecl under MSVC and empty otherwise")

    # Three: the version names, and NTK_VERSION computed from the three parts.
    version_names = ("NTK_VERSION_MAJOR", "NTK_VERSION_MINOR", "NTK_VERSION_PATCH", "NTK_VERSION")
    for label, text in headers.items():
        defined = macros(text)
        if defined.get("NTK_CALL") != ["__cdecl", ""]:
            problems.append(f"the {label} Common.h defines NTK_CALL as {defined.get('NTK_CALL')}, "
                            "not __cdecl under MSVC and empty otherwise, once each")
        for twice in version_names:
            if len(defined.get(twice, [])) > 1:
                problems.append(f"the {label} Common.h defines {twice} {len(defined[twice])} times")
        try:
            major, minor, patch, whole = (int(defined[n][0], 0) for n in version_names)
        except (KeyError, ValueError):
            problems.append(f"the {label} Common.h lacks one of {', '.join(version_names)} as a number")
            continue
        if whole != (major << 16) | (minor << 8) | patch:
            problems.append(f"the {label} NTK_VERSION {whole:#08x} is not {major}.{minor}.{patch}")
        # Four: any other constant must be one only this OS may have.
        for macro in sorted(set(defined) - set(version_names) - {"NTK_CALL"}):
            if label not in os_only or not re.match(os_only[label], macro):
                problems.append(f"{macro} in the {label} Common.h is neither shared nor allowed for {label} alone")
    return problems
