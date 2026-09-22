#!/usr/bin/env python3
"""Check the Windows C++ API design against the code and against what it cites.

check_design_consistency.py asks whether a document agrees with itself. This
asks whether it agrees with everything outside it, which is where a design that
has been implemented starts to rot:

  ops        the 47 operations of section 8.1 against the public headers, so
             neither list can drift without the other noticing. Whether the C
             ABI exports its half is check_c_abi_contract.py's to say: the C
             names of this section are the 1.x ones, which stage 5 retired.
  errors     every error enumeration against the value the C ABI gives it,
             and against the constant the implementation uses internally
             (src/<feature>/<Feature>Codes.h), one to one, all read from source.
  retvals    every @retval a public header promises against section 11.4.
  documented every operation has a comment, and every one that can fail a
             @retval - the completion condition of T-16, kept checked.
  citations  every line number section 10 cites, against the document it cites.

Each check reports OK or FAIL. A check that cannot find its subject fails
(stage 5 design 8.5, R-30): a silent vacuous pass hands out false confidence,
which is worse than having no check at all. A check whose subject is present
but which found nothing to compare also fails, for the same reason.

Usage:
    python3 scripts/check_cpp_api_contract.py [design.md] [--root <tree>]

--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.

Exit status is 1 when any check fails.
"""

import re
import sys
from pathlib import Path

# Every path is a fragment resolved against ROOT, so a test can aim the whole
# checker at a copy of the tree instead of editing the real one to see whether
# a check still fails when it should.
ROOT = Path(__file__).resolve().parent.parent

DEFAULT_DESIGN = "artifact/topics/windows-architecture/designs/2026-09-20-windows-architecture-cpp-api-design.md"

PUBLIC_HEADERS = [
    "windows/WindowsLibrary/include/NativeToolkit/Dialog.h",
    "windows/WindowsLibrary/include/NativeToolkit/Notification.h",
    "windows/WindowsLibrary/include/NativeToolkit/Clipboard.h",
]
ERROR_HEADER = "windows/WindowsLibrary/include/NativeToolkit/Error.h"
# enum in Error.h  ->  the C ABI header whose anonymous enum carries its values
# (stage 5 design E-8, 8.5).
ERROR_SOURCES = {
    "DialogError": ("windows/WindowsLibraryCApi/include/NativeToolkitC/Dialog.h",
                    "NTK_DIALOG_ERROR_"),
    "ClipboardError": ("windows/WindowsLibraryCApi/include/NativeToolkitC/Clipboard.h",
                       "NTK_CLIPBOARD_ERROR_"),
    "NotificationError": ("windows/WindowsLibraryCApi/include/NativeToolkitC/Notification.h",
                          "NTK_NOTIFICATION_ERROR_"),
}
# enum in Error.h  ->  the #define the implementation reports it with (8.5).
# DialogError has none: the dialogs report Win32 values, not codes of their own.
INTERNAL_SOURCES = {
    "ClipboardError": ("windows/WindowsLibrary/src/Clipboard/ClipboardCodes.h", "CLIPBOARD_ERROR_"),
    "NotificationError": ("windows/WindowsLibrary/src/Notification/NotificationCodes.h", "NOTIFICATION_ERROR_"),
}

# Which section of 10 cites which document.
CITED_DOCUMENTS = {
    "### 10.1": ("clipboard v2",
                 "artifact/features/clipboard/designs/2026-07-28-windows-clipboard-design-v2.md"),
    "### 10.2": ("notification v3",
                 "artifact/features/notification/designs/2026-05-30-windows-notification-design-v3.md"),
}
CITATION_WINDOW = 3  # lines either side, as T-13 specifies
# An anchor shorter than this matches too much to prove anything: "int" is in
# every other line of a design document.
ANCHOR_MIN = 5


def at(fragment):
    return ROOT / fragment


# Public member functions that are deliberately not operations of section 8.1.
# Every entry needs a reason, because this list is the one place the check can
# be silenced.
NOT_AN_OPERATION = {
    # Section 7.4: a move-only owner declares these, and they are lifetime, not
    # an operation the C ABI has a counterpart for.
    "Manager", "Session", "Runtime", "~Manager", "~Session", "~Runtime", "operator=",
    # N-10: exists so a C++ caller can do what a second initNotificationManager
    # does today. It is a design decision, not one of the 47.
    "SetInvokedHandler",
}


class Report:
    def __init__(self, title):
        self.title = title
        self.notes = []
        self.failures = []

    def ok(self, name, detail=""):
        self.notes.append(f"  OK   {name}" + (f": {detail}" if detail else ""))

    def skip(self, name, why):
        # Not being able to look is a failure, never a pass (8.5).
        self.failures.append(f"  FAIL {name}: cannot check: {why}")

    def check(self, condition, name, detail=""):
        if condition:
            self.ok(name)
        else:
            self.failures.append(f"  FAIL {name}: {detail}")

    def dump(self):
        print(f"== {self.title}")
        for line in self.notes + self.failures:
            print(line)
        return not self.failures


# ---------------------------------------------------------------------------
# Reading the document
# ---------------------------------------------------------------------------

def table_rows(text, heading):
    """The rows of the first table under a heading, as lists of cell strings."""
    start = text.find(heading)
    if start < 0:
        return []
    rows = []
    started = False
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
    return rows[1:] if rows else []  # drop the header row


def backticked(cell):
    return re.findall(r"`([^`]+)`", cell)


def outside_parentheses(cell):
    """The cell with every parenthesised aside removed.

    In 11.4 a row reads "`InvalidParameter`(no `displayName`), `HResultFailure`".
    The errors are the list; what is in the brackets explains them and names
    other things entirely, so reading every backtick as an error name would
    have the table promising a `CoInitializeEx` error.
    """
    kept = []
    depth = 0
    for character in cell:
        if character in "(（":
            depth += 1
        elif character in ")）":
            depth = max(0, depth - 1)
        elif depth == 0:
            kept.append(character)
    return "".join(kept)


def expand_op_key(cell):
    """"OP-02〜OP-06", "OP-10 / OP-11" and "OP-07" all name their operations."""
    ids = re.findall(r"OP-(\d+)", cell)
    if "〜" in cell or "~" in cell:
        if len(ids) >= 2:
            return [f"OP-{n:02d}" for n in range(int(ids[0]), int(ids[-1]) + 1)]
    return [f"OP-{int(n):02d}" for n in ids]


def operations(design):
    """OP id -> (C name, C++ function name, C++ class or None), from section 8.1."""
    table = {}
    for cells in table_rows(design, "### 8.1"):
        if len(cells) < 3 or not cells[0].startswith("OP-"):
            continue
        c_names = backticked(cells[1])
        signatures = backticked(cells[2])
        if not c_names or not signatures:
            continue
        # "Result<void> Session::CopyText(std::wstring_view, ...)"
        match = re.search(r"(?:(\w+)::)?(\w+)\s*\(", signatures[0])
        if not match:
            continue
        table[cells[0]] = (c_names[0], match.group(2), match.group(1))
    return table


# ---------------------------------------------------------------------------
# Reading the code
# ---------------------------------------------------------------------------

# A declaration ends at its semicolon and may span several lines, and its
# parameter list may contain braces, because a default argument can be "= {}".
DECLARATION = re.compile(
    r"^\s*(?:static\s+|virtual\s+)?[\w:<>,\s&*]+?\b(\w+)\s*\([^;]*\)\s*(?:const\s*)?(?:noexcept\s*)?;",
    re.S)


def header_declarations():
    """(class or None, function name) for every declaration in the public headers,
    together with the text of each header for finding doc comments."""
    found = set()
    texts = {}
    for header in (at(h) for h in PUBLIC_HEADERS):
        if not header.exists():
            continue
        text = header.read_text(encoding="utf-8")
        texts[header.name] = text

        # Track which class body each declaration falls in, and whether it is
        # public: a private member is not part of the promised surface.
        current_class = None
        access = "public"
        depth = 0
        pending = ""          # a declaration that has not reached its semicolon
        for line in text.splitlines():
            class_start = re.match(r"^class\s+(\w+)\s*\{?\s*$", line)
            if class_start:
                current_class, access, pending = class_start.group(1), "private", ""
                depth = line.count("{") - line.count("}")
                continue
            if current_class:
                # The class ends when the nesting drops back to nothing, not at
                # the first closing brace: a default argument of "= {}" opens
                # and closes one of its own on a line in the middle of the body.
                was_open = depth > 0
                depth += line.count("{") - line.count("}")
                if was_open and depth <= 0:
                    current_class, access, pending = None, "public", ""
                    continue
                if re.match(r"^\s*(public|private|protected)\s*:", line):
                    access = re.match(r"^\s*(\w+)\s*:", line).group(1)
                    continue
            if line.lstrip().startswith(("//", "*", "/*")):
                continue
            pending = (pending + " " + line).strip() if pending else line
            if ";" not in pending:
                continue
            if access == "public":
                for name in DECLARATION.findall(pending):
                    found.add((current_class, name))
            pending = ""
    return found, texts


def class_body(text, name):
    """The text of a class, from its opening brace to the matching one."""
    start = re.search(r"^class\s+" + re.escape(name) + r"\b", text, re.M)
    if not start:
        return None
    opening = text.find("{", start.start())
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[opening:index]
    return None


def doc_comment_of(texts, function_name, class_name):
    """The doc comment that introduces a declaration, or None.

    Scoped to the class the operation belongs to. Close is a member of both
    Manager and Session, and taking whichever came first in a concatenation
    would have compared one operation's documentation with another's row - a
    check that reads the wrong thing and agrees with it is worse than no check.

    Both /** */ blocks and runs of /// lines count.
    """
    for text in texts.values():
        scope = class_body(text, class_name) if class_name else text
        if scope is None:
            continue
        position = re.search(r"\b" + re.escape(function_name) + r"\s*\(", scope)
        if not position:
            continue
        before = scope[:position.start()]
        # Only the return type stands between the comment and the name.
        block = re.search(r"/\*\*(?:(?!\*/).)*\*/[\w:<>,\s&*]*$", before, re.S)
        if block:
            return block.group(0)
        lines = re.search(r"((?:[ \t]*///[^\n]*\n)+)[\w:<>,\s&*]*$", before)
        if lines:
            return lines.group(1)
        return None
    return None


def retvals_of(texts, function_name, class_name):
    """The @retval names of the doc comment that introduces a declaration."""
    comment = doc_comment_of(texts, function_name, class_name)
    return re.findall(r"@retval\s+(\w+)", comment) if comment else []


def enum_values(name):
    """The members of an enum class in Error.h, as name -> value."""
    if not at(ERROR_HEADER).exists():
        return {}
    text = at(ERROR_HEADER).read_text(encoding="utf-8")
    body = re.search(r"enum class\s+" + re.escape(name) + r"[^{]*\{(.*?)\}", text, re.S)
    if not body:
        return {}
    return {m.group(1): int(m.group(2))
            for m in re.finditer(r"(\w+)\s*=\s*(\d+)", body.group(1))}


def defined_values(path, prefix):
    """The C ABI's constants of one family, from its anonymous enums, as
    name -> value (NTK_CLIPBOARD_ERROR_BUSY = 3 reads as BUSY -> 3)."""
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    values = {}
    for body in re.findall(r"enum\s*\{(.*?)\};", text, re.S):
        for name, value in re.findall(r"(\w+)\s*=\s*(\d+)", body):
            if name.startswith(prefix):
                values[name[len(prefix):]] = int(value)
    return values


def internal_values(path, prefix):
    """The #define constants of one family, as name -> value. The family's
    success value is spelled <FAMILY>_SUCCESS in one of them and reads as NONE."""
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    values = {}
    family = prefix.rsplit("_ERROR_", 1)[0]
    for match in re.finditer(r"^#define\s+(\w+)\s+(\d+)", text, re.M):
        name, value = match.group(1), int(match.group(2))
        if name.startswith(prefix):
            values[name[len(prefix):]] = value
        elif name == f"{family}_SUCCESS":
            values["NONE"] = value
    return values


def flatten(name):
    return name.replace("_", "").lower()


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def check_operations(design, rep):
    ops = operations(design)
    if not ops:
        rep.skip("operations", "no OP table under section 8.1")
        return
    declared, _ = header_declarations()
    if not declared:
        rep.skip("operations", "no public headers to read")
        return

    names = {n for _, n in declared}
    undeclared = []
    for op, (_, cpp, klass) in sorted(ops.items()):
        if (klass, cpp) in declared or (klass is None and cpp in names):
            continue
        undeclared.append(f"{op} {klass + '::' if klass else ''}{cpp}")
    rep.check(not undeclared, "every C++ name in 8.1 is declared",
              f"not declared: {', '.join(undeclared)}")

    promised = {cpp for _, cpp, _ in ops.values()}
    extra = sorted(f"{k + '::' if k else ''}{n}" for k, n in declared
                   if n not in promised and n not in NOT_AN_OPERATION)
    rep.check(not extra, "the headers declare nothing 8.1 does not",
              f"declared but not an operation: {', '.join(extra)}")


def check_error_enums(rep):
    checked = 0
    sources = [(enum, path, prefix, defined_values, "the C ABI")
               for enum, (path, prefix) in sorted(ERROR_SOURCES.items())]
    sources += [(enum, path, prefix, internal_values, "its internal codes")
                for enum, (path, prefix) in sorted(INTERNAL_SOURCES.items())]
    for enum, path, prefix, read_values, against in sources:
        members = enum_values(enum)
        defines = read_values(at(path), prefix)
        if not members or not defines:
            rep.skip(f"{enum} matches {against}",
                     f"the enum or {against} could not be read")
            continue
        checked += 1

        by_flat = {flatten(k): v for k, v in defines.items()}
        problems = []
        for member, value in members.items():
            flat = flatten(member)
            if flat not in by_flat:
                problems.append(f"{member} has no value in {against}")
            elif by_flat[flat] != value:
                problems.append(f"{member}={value} but {against} says {by_flat[flat]}")
        for name in by_flat:
            if name not in {flatten(m) for m in members}:
                problems.append(f"{prefix}{name.upper()} has no enumerator")
        rep.check(not problems, f"{enum} matches {against} ({len(members)} values)",
                  "; ".join(problems))

    if checked == 0:
        rep.check(False, "error enumerations", "nothing was compared")


def check_retvals(design, rep):
    ops = operations(design)
    rows = {}
    for cells in table_rows(design, "### 11.4"):
        if len(cells) < 2:
            continue
        # An operation can have more than one row: OP-42..OP-46 list what the
        # call returns and, separately, what reaches the handler. Either is a
        # legitimate thing for a header to document, so the rows are joined.
        for op in expand_op_key(cells[0]):
            rows.setdefault(op, set()).update(backticked(outside_parentheses(cells[1])))
    if not ops or not rows:
        rep.skip("@retval agrees with 11.4", "no 8.1 or no 11.4 table")
        return

    _, texts = header_declarations()
    compared = 0
    problems = []
    for op, (_, cpp, klass) in sorted(ops.items()):
        promised = retvals_of(texts, cpp, klass)
        if not promised:
            continue  # this operation documents no @retval yet
        compared += 1
        listed = rows.get(op)
        if listed is None:
            problems.append(f"{op} has @retval but no row in 11.4")
            continue
        for name in promised:
            if name not in listed:
                problems.append(f"{op} promises @retval {name}, which 11.4 does not list")

    if compared == 0:
        rep.check(False, "@retval agrees with 11.4",
                  "no public header documents a @retval, so nothing was compared")
    else:
        rep.check(not problems, f"@retval agrees with 11.4 ({compared} of {len(ops)} operations "
                                f"document one)", "; ".join(problems))

    # Most operations document no @retval yet, so the check above sees only a
    # corner of 11.4. What can be checked for all of it is that every error it
    # names is an error that exists: a table naming an enumerator the code has
    # renamed is drift whether or not a header quotes it.
    known = set()
    for enum in ("DialogError", "NotificationError", "ClipboardError"):
        known |= set(enum_values(enum))
    if not known:
        rep.skip("11.4 names errors that exist", "no enumeration could be read")
        return
    unknown = sorted({name for names in rows.values() for name in names} - known)
    rep.check(not unknown, f"11.4 names errors that exist ({len(rows)} operations)",
              f"no such enumerator: {', '.join(unknown)}")


def check_documented(design, rep):
    """Every operation is documented, and every one that can fail says how.

    This is T-16's completion condition made into something that stays true:
    an operation added without a comment, or a @retval deleted from one that
    section 11.4 says can fail, fails here rather than being noticed in a
    review. An operation 11.4 lists as returning nothing - Manager::Close and
    Session::CanClose - needs a comment but no @retval.
    """
    ops = operations(design)
    rows = {}
    for cells in table_rows(design, "### 11.4"):
        if len(cells) < 2:
            continue
        for op in expand_op_key(cells[0]):
            rows.setdefault(op, set()).update(backticked(outside_parentheses(cells[1])))
    if not ops:
        rep.skip("every operation is documented", "no 8.1 table")
        return

    _, texts = header_declarations()
    undocumented = []
    unexplained = []
    for op, (_, cpp, klass) in sorted(ops.items()):
        comment = doc_comment_of(texts, cpp, klass)
        name = f"{op} {klass + '::' if klass else ''}{cpp}"
        if not comment:
            undocumented.append(name)
        elif rows.get(op) and not re.search(r"@retval\s+\w+", comment):
            unexplained.append(name)

    rep.check(not undocumented, f"every operation is documented ({len(ops)} operations)",
              f"no comment: {', '.join(undocumented)}")
    rep.check(not unexplained, "every operation that can fail documents how",
              f"11.4 lists errors but the header has no @retval: {', '.join(unexplained)}")


def check_citations(design, rep):
    """Every line number section 10 cites should still say what it is cited for.

    A row cites either a line of the earlier design document or a place in the
    implementation. Only the first can be checked from here: a row that cites
    "reserveDeferredFormats (:687)" names a symbol but not which file, and
    guessing would make the check less trustworthy than not making it.

    The anchor is whatever the promise puts in backticks, compared with
    underscores removed and case folded, because the promise usually names the
    C++ enumerator where the source it cites still names the C constant -
    PartialState against PARTIAL_STATE is agreement, not drift.
    """
    anchored = 0
    unanchored = 0
    implementation = 0
    problems = []
    read_a_table = False

    for heading, (label, path) in sorted(CITED_DOCUMENTS.items()):
        path = at(path)
        rows = table_rows(design, heading)
        if not rows or not path.exists():
            rep.skip(f"section 10 cites {label} correctly",
                     "the section or the cited document is missing")
            continue
        read_a_table = True
        lines = path.read_text(encoding="utf-8").splitlines()

        for cells in rows:
            if len(cells) < 3:
                continue
            source = cells[1]
            if "実装" in source:
                implementation += 1
                continue
            numbers = [int(n) for n in re.findall(r"\d+", source)]
            if not numbers:
                continue

            out_of_range = [n for n in numbers if not 1 <= n <= len(lines)]
            if out_of_range:
                problems.append(f"{cells[0]} cites line {out_of_range[0]}, "
                                f"past the end of {label}")
                continue

            anchors = [flatten(a) for a in backticked(cells[2])]
            anchors = [a for a in anchors if len(a) >= ANCHOR_MIN]
            if not anchors:
                unanchored += 1
                continue

            window = flatten("\n".join(lines[max(0, min(numbers) - 1 - CITATION_WINDOW):
                                             max(numbers) + CITATION_WINDOW]))
            if any(anchor in window for anchor in anchors):
                anchored += 1
            else:
                problems.append(f"{cells[0]} cites {numbers} in {label}, but none of "
                                f"{backticked(cells[2])} appears within "
                                f"{CITATION_WINDOW} lines")

    if not read_a_table:
        rep.skip("section 10 cites its sources correctly", "no citation table was read")
        return
    if anchored == 0:
        rep.check(False, "section 10 cites its sources correctly",
                  "no row had an anchor worth matching, so nothing was compared")
        return
    rep.check(not problems,
              f"section 10 cites its sources correctly ({anchored} checked, "
              f"{unanchored} without an anchor, {implementation} citing the implementation)",
              "; ".join(problems))


def main(argv):
    global ROOT

    arguments = list(argv[1:])
    if "--root" in arguments:
        index = arguments.index("--root")
        ROOT = Path(arguments[index + 1]).resolve()
        del arguments[index:index + 2]

    path = Path(arguments[0]) if arguments else at(DEFAULT_DESIGN)
    if not path.exists():
        print(f"no such document: {path}", file=sys.stderr)
        return 2

    design = path.read_text(encoding="utf-8")
    rep = Report(path)
    check_operations(design, rep)
    check_error_enums(rep)
    check_retvals(design, rep)
    check_documented(design, rep)
    check_citations(design, rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
