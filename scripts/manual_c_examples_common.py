"""What the manual C example checkers of every OS share.

The checkers are one file per OS (check_manual_c_examples_<os>.py, Android C
ABI design part 2, 0.3). This module holds what does not depend on the OS:
finding the C blocks of one OS chapter's "C ABI" section in every language,
and the checks that read only those blocks and the headers - coverage,
symbols and parity - plus splitting a block into a compilable file. Where the
exported functions come from, the prelude and the compiler are the OS's.
"""

import re
from pathlib import Path

MANUAL = "manual"
LANGUAGES = ("", ".ja", ".ko")


def latest_version(root):
    """The highest manual/<version>, by its numeric parts."""
    folder = Path(root) / MANUAL
    if not folder.is_dir():
        return None
    versions = []
    for entry in folder.iterdir():
        if entry.is_dir() and re.fullmatch(r"\d+(\.\d+)*", entry.name):
            versions.append(entry.name)
    if not versions:
        return None
    return max(versions, key=lambda v: tuple(int(p) for p in v.split(".")))


def chapter(text, os_name):
    """The '## <os_name>' chapter, up to the next '## ' heading outside a code block."""
    heading = f"## {os_name}\n"
    if heading not in text:
        return None
    rest = text[text.index(heading) + len(heading):]
    fenced = False
    offset = 0
    for line in rest.splitlines(keepends=True):
        if line.startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("## "):
            return heading + rest[:offset]
        offset += len(line)
    return heading + rest


def c_blocks(text, os_name):
    """The C code blocks of the OS chapter's C ABI section."""
    found = chapter(text, os_name)
    if found is None or "### C ABI\n" not in found:
        return None
    section = found[found.index("### C ABI\n"):]
    end = section.find("\n---\n\n## ")
    if end != -1:
        section = section[:end]
    return re.findall(r"```c\n(.*?)```", section, re.S)


def near_misses(text, os_name):
    """Headings of the OS chapter that look like '### C ABI' but are not it:
    with them, a page would read as having no section and pass unchecked."""
    found = chapter(text, os_name)
    if found is None:
        return []
    return [line for line in found.splitlines()
            if re.match(r"^#{2,4}\s", line) and re.search(r"(?i)\bc[\s_-]*abi\b", line)
            and line != "### C ABI"]


def pages(root, version, rep, os_name, missing_is_failure=True):
    """{page name: {language: [block, ...]}}, or None when nothing was read.

    When no page has the section, missing_is_failure decides between a
    failure and a SKIP: an OS whose C ABI chapter is not written yet says so.
    A heading that nearly reads '### C ABI', or a translation with a section
    its English page lacks, is a failure either way: it would otherwise look
    like a page with nothing to check."""
    folder = Path(root) / f"{MANUAL}/{version}"
    if not folder.is_dir():
        rep.check(False, "the manual is readable", f"cannot read {MANUAL}/{version}")
        return None

    found, stray = {}, []
    for path in sorted(folder.glob("*.md")):
        name = path.name
        text = path.read_text(encoding="utf-8-sig")
        stray.extend(f"{name}: '{line}'" for line in near_misses(text, os_name))
        if any(name.endswith(f"{suffix}.md") for suffix in LANGUAGES if suffix):
            continue                      # a translation; reached through its English page
        stem = name[:-len(".md")]
        blocks = c_blocks(text, os_name)
        if blocks is None:
            for suffix in LANGUAGES:
                other = folder / f"{stem}{suffix}.md"
                if suffix and other.exists() and c_blocks(other.read_text(encoding="utf-8-sig"), os_name) is not None:
                    stray.append(f"{other.name} has a {os_name} C ABI section that {name} lacks")
            continue                      # a page with no C ABI section for this OS
        found[stem] = {"": blocks}
        for suffix in LANGUAGES:
            if not suffix:
                continue
            other = folder / f"{stem}{suffix}.md"
            if not other.exists():
                rep.check(False, "the manual is readable", f"cannot read {other.name}")
                continue
            found[stem][suffix] = c_blocks(other.read_text(encoding="utf-8-sig"), os_name)

    if stray:
        rep.check(False, "the manual is readable", "; ".join(stray))
    if not found:
        article = "an" if os_name[0] in "AEIOU" else "a"
        detail = f"no page under {MANUAL}/{version} has {article} {os_name} C ABI section"
        if missing_is_failure:
            rep.check(False, "the manual is readable", detail)
        else:
            rep.skip("the manual has C examples", detail)
        return None
    return found


def used_names(found):
    """The ntk_ names the English examples use."""
    names = set()
    for languages in found.values():
        for block in languages[""]:
            names |= set(re.findall(r"\bntk_[a-z_0-9]+", block))
    return names


def used_constants(found):
    """The NTK_ constants and macros the English examples use."""
    names = set()
    for languages in found.values():
        for block in languages[""]:
            names |= set(re.findall(r"\bNTK_[A-Z_0-9]+", block))
    return names


# --- 1. coverage -------------------------------------------------------------

def check_coverage(found, exports, rep):
    missing = sorted(exports - used_names(found))
    rep.check(not missing,
              f"coverage: every exported function appears in an example ({len(exports)})",
              f"never shown: {', '.join(missing)}")


# --- 2. symbols --------------------------------------------------------------

def declared_names(root, include, rep):
    """Every ntk_ and NTK_ name the public headers declare, or None.

    Functions, types and constants together: an example names all three, and a
    renamed one has to fail whichever kind it is.
    """
    folder = Path(root) / include
    headers = sorted(folder.glob("**/*.h")) if folder.is_dir() else []
    if not headers:
        rep.check(False, "symbols: every ntk_ and NTK_ name exists in the headers",
                  f"cannot read {include}")
        return None
    names = set()
    for header in headers:
        text = header.read_text(encoding="utf-8")
        names |= set(re.findall(r"\bntk_[a-z_0-9]+", text))
        names |= set(re.findall(r"\bNTK_[A-Z_0-9]+", text))
    return names


def check_symbols(found, declared, rep):
    used = used_names(found) | used_constants(found)
    unknown = sorted(name for name in used if name not in declared)
    rep.check(not unknown, "symbols: every ntk_ and NTK_ name exists in the headers",
              f"not declared: {', '.join(unknown)}")


# --- 3. parity ---------------------------------------------------------------

def code_only(block):
    """The block with its comments and blank lines removed."""
    block = re.sub(r"/\*.*?\*/", "", block, flags=re.S)
    return [line.rstrip() for line in block.split("\n") if line.strip()]


def check_parity(found, rep, os_name):
    problems = []
    for stem, languages in sorted(found.items()):
        english = languages[""]
        for suffix in LANGUAGES:
            if not suffix or suffix not in languages:
                continue
            other = languages[suffix]
            if other is None:
                problems.append(f"{stem}{suffix}: no {os_name} C ABI section")
                continue
            if len(other) != len(english):
                problems.append(f"{stem}{suffix}: {len(other)} blocks, en has {len(english)}")
                continue
            for index, (a, b) in enumerate(zip(english, other), start=1):
                first = next((x for x, y in zip(code_only(a), code_only(b)) if x != y), None)
                if code_only(a) != code_only(b):
                    where = f" (first at: {first})" if first else ""
                    problems.append(f"{stem}{suffix}: block {index} differs{where}")
                    break
    rep.check(not problems, "parity: the three languages carry the same code",
              "; ".join(problems))


# --- 4. compile: turning the blocks into files ------------------------------

def split_block(block):
    """(file scope, statements): every `static ...` definition, then the rest."""
    lines = block.split("\n")
    head, body = [], []
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith("static ") and "(" in line:
            if line.rstrip().endswith("}"):
                head.append(line)
                index += 1
                continue
            depth, started = 0, False
            while index < len(lines):
                head.append(lines[index])
                depth += lines[index].count("{") - lines[index].count("}")
                started = started or "{" in lines[index]
                index += 1
                if started and depth == 0:
                    break
            continue
        body.append(line)
        index += 1
    head += [line for line in body if line.startswith("#include")]
    body = [line for line in body if not line.startswith("#include")]
    return "\n".join(head), "\n".join(body)


def write_sources(found, work, prelude, encoding="ascii"):
    """One .c file per English block, each a function wrapped in the prelude.
    Returns the paths written and the blocks that could not be written in the
    given encoding (a compiler without /utf-8 reads source as its code page)."""
    written, problems = [], []
    for stem, languages in sorted(found.items()):
        for index, block in enumerate(languages[""], start=1):
            head, body = split_block(block)
            head = "\n".join(l for l in head.split("\n") if not l.startswith("#include"))
            path = Path(work) / f"{stem}_{index}.c"
            try:
                path.write_text(
                    f"{prelude}\n{head}\n\nstatic void example_{stem}_{index}(void)\n{{\n{body}\n}}\n",
                    encoding=encoding)
            except UnicodeEncodeError as error:
                problems.append(f"{stem} block {index} is not {encoding}: {error.reason} at {error.start}")
                continue
            written.append(path)
    return written, problems
