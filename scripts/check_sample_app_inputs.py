#!/usr/bin/env python3
"""Check that the native sample apps declare no text input fields.

The rule is in agent-rules/coding-rules/common.md ("サンプルアプリの入力欄"):
sample apps drive every operation from buttons and supply values from fixed
constants, internal state, or one button per representative value.

This is checked mechanically rather than by review because of how the defect
looks. A screen carrying an input field reads perfectly well on its own; it is
only wrong relative to the other screens. Upstream, four review rounds across
nine reviewers failed to see exactly this, so review is the wrong instrument.

An exception is allowed when the feature genuinely needs one. Put

    sample-app-input-approved: artifact/designs/<feature>/<plan>.md

in the file that declares the field. The marker must name the plan document
that carries the reason, so the exception stays traceable from the code; a
marker naming nothing is not an approval.

Usage:
    python3 scripts/check_sample_app_inputs.py [root ...]

Exit status is 1 when an unapproved input field is found, 2 on bad usage.
"""

import re
import sys
from pathlib import Path

# Sample apps only. The library and test projects are out of scope: the rule is
# about how a sample presents operations, not about what the toolkit supports.
SAMPLE_ROOTS = [
    "android/AndroidLibraryExample",
    "ios/IosLibraryExample",
    "mac/MacLibraryExample",
    "windows/WindowsLibraryExample",
]

# Directories that hold generated or vendored code rather than authored UI.
SKIP_DIRS = {
    ".git", ".vs", "build", "Build", "bin", "obj", "x64", "x86",
    "Generated Files", "DerivedData", "packages", "node_modules",
    ".gradle", ".idea", "Pods",
}

SUFFIXES = {".xaml", ".xml", ".kt", ".java", ".swift", ".xib", ".storyboard"}

# The reference must name the plan document that carries the reason, so it has
# to end in .md. Without that, a bare marker inside an XML comment approves
# itself: the next token is "-->".
APPROVAL = re.compile(r"sample-app-input-approved:\s*(\S+\.md)")

# Markup: an input element is a tag, so the '<' is what separates a real
# declaration from the same word sitting inside a caption.
MARKUP_TAGS = (
    "TextBox", "PasswordBox", "AutoSuggestBox", "RichEditBox", "NumberBox",
    "EditText", "AutoCompleteTextView", "MultiAutoCompleteTextView",
    "textField", "secureTextField", "searchField",
)
MARKUP = re.compile(r"<\s*(" + "|".join(MARKUP_TAGS) + r")\b")

# Code: a constructor call or a stored type. Anchored on a word boundary so
# `.textFieldStyle(` and similar modifiers do not match.
CODE_TYPES = (
    "TextField", "OutlinedTextField", "BasicTextField",
    "SecureField", "TextEditor",
    "UITextField", "UISearchBar",
    "NSTextField", "NSSecureTextField", "NSSearchField",
)
CODE = re.compile(r"\b(" + "|".join(CODE_TYPES) + r")\s*[(:]")

BLOCK_COMMENT = re.compile(r"/\*.*?\*/|<!--.*?-->", re.S)
LINE_COMMENT = re.compile(r"//.*?$", re.M)
# Attribute values and string literals. A caption such as
# Content="ShowWithInput (TextBox + ComboBox)" names an input control without
# declaring one, so the text has to go before the patterns are applied.
QUOTED = re.compile(r'"[^"\n]*"' + r"|'[^'\n]*'")


def strip_noncode(text):
    """Blank out comments and quoted text, keeping line numbers intact."""

    def blank(match):
        return re.sub(r"[^\n]", " ", match.group(0))

    text = BLOCK_COMMENT.sub(blank, text)
    text = LINE_COMMENT.sub(blank, text)
    return QUOTED.sub(blank, text)


def iter_files(root):
    for path in sorted(root.rglob("*")):
        if path.suffix not in SUFFIXES or not path.is_file():
            continue
        if SKIP_DIRS.intersection(path.parts):
            continue
        yield path


def scan_file(path):
    """Return (findings, approval) for one file."""
    try:
        raw = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return [], None

    approval = APPROVAL.search(raw)
    stripped = strip_noncode(raw)

    findings = []
    for number, line in enumerate(stripped.splitlines(), start=1):
        for pattern in (MARKUP, CODE):
            match = pattern.search(line)
            if match:
                findings.append((number, match.group(1)))
                break
    return findings, (approval.group(1) if approval else None)


def display(path, repo):
    """Repo-relative when possible; tests point the checker outside the tree."""
    try:
        return path.relative_to(repo)
    except ValueError:
        return path


def scan_root(repo, relative):
    """Return (violations, approved, checked) for one sample app."""
    root = repo / relative
    if not root.is_dir():
        return [], [], 0

    violations, approved, checked = [], [], 0
    for path in iter_files(root):
        checked += 1
        findings, approval = scan_file(path)
        if not findings:
            continue
        target = approved if approval else violations
        for number, name in findings:
            target.append((display(path, repo), number, name, approval))
    return violations, approved, checked


def main(argv):
    repo = Path(__file__).resolve().parents[1]
    roots = argv[1:] or SAMPLE_ROOTS

    violations, approved, checked, missing = [], [], 0, []
    for relative in roots:
        if not (repo / relative).is_dir():
            missing.append(relative)
            continue
        found, allowed, count = scan_root(repo, relative)
        violations.extend(found)
        approved.extend(allowed)
        checked += count

    # A run that inspected nothing must not look like a clean run.
    if checked == 0:
        print("SKIP  no sample app source found; nothing was checked")
        for relative in missing:
            print(f"      missing root: {relative}")
        return 2

    for path, number, name, reference in approved:
        print(f"ALLOW {path}:{number}  {name}  (approved by {reference})")

    for path, number, name, _ in violations:
        print(f"FAIL  {path}:{number}  {name} declared in a sample app")

    if violations:
        print()
        print(f"{len(violations)} input field(s) in {checked} files checked.")
        print("Sample apps drive operations from buttons: see")
        print('  agent-rules/coding-rules/common.md "サンプルアプリの入力欄"')
        print("To allow one, state the reason in the plan document and add")
        print("  sample-app-input-approved: <plan document path>")
        print("to the declaring file.")
        return 1

    print(f"OK    no unapproved input field in {checked} files checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
