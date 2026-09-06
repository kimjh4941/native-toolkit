#!/usr/bin/env bash
set -euo pipefail

# Verify the consistency of a hand-written manual under manual/<version>/.
#
# Usage:
#   ./scripts/verify_manual.sh <version> [--strict] [--quiet]
#
# Examples:
#   ./scripts/verify_manual.sh 1.9.0
#   ./scripts/verify_manual.sh 1.9.0 --strict
#
# Checks (blocking ones decide the exit code):
#   1. image references     BLOCKING  every images/... path resolves to a real file
#   2. sample conformance   warning   code examples use the sample app's literals
#   3. anchors              BLOCKING  every [](#anchor) resolves to a heading
#   4. artifact filenames   BLOCKING  named artifacts exist under dist/<version>/
#   5. prose style          warning   ja is です・ます体, ko is 합니다体
#   6. language parity      warning   the three languages carry the same images/headings
#
# Exit codes:
#   0  no blocking failure (warnings may still be present)
#   1  at least one blocking failure
#   2  bad usage / missing input
#
# Known-intentional exceptions for check 2 live in:
#   agent-rules/workflows/verify-manual/SAMPLE_CONFORMANCE_IGNORE.txt

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/verify_manual.sh <version> [--strict] [--quiet]

  <version>   Manual version to verify (e.g. 1.9.0). Reads manual/<version>/.
  --strict    Treat warnings as blocking too.
  --quiet     Print the summary only; suppress per-finding detail.

Checks 1, 3 and 4 are blocking; 2, 5 and 6 are warnings unless --strict is given.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

VERSION=${1:-}
STRICT=false
QUIET=false

if [[ -z $VERSION ]]; then
  echo "error: <version> is required" >&2
  usage >&2
  exit 2
fi
shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --strict) STRICT=true ;;
    --quiet)  QUIET=true ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

if [[ ! -d "manual/$VERSION" ]]; then
  echo "error: manual/$VERSION not found" >&2
  exit 2
fi

VERSION="$VERSION" STRICT="$STRICT" QUIET="$QUIET" python3 - <<'PYTHON'
import os
import re
import sys
from pathlib import Path

VERSION = os.environ["VERSION"]
STRICT = os.environ["STRICT"] == "true"
QUIET = os.environ["QUIET"] == "true"

MANUAL = Path("manual") / VERSION
DIST = Path("dist") / VERSION
IGNORE_FILE = Path("agent-rules/workflows/verify-manual/SAMPLE_CONFORMANCE_IGNORE.txt")

# Where each platform section's sample app screen lives. `{feature}` is the
# capitalized feature name taken from the manual's filename.
#
# A screen may keep its fixtures in a companion file, and a literal the manual
# quotes can live there rather than in the view. Scanning only the view reported
# `public.url` and `public.rtf` as absent when both are declared next door
# (R-SA29): the subject is the sample screen, not one file of it.
SAMPLE_SOURCES = {
    "iOS": [
        "ios/IosLibraryExample/IosLibraryExample/{feature}SampleView.swift",
        "ios/IosLibraryExample/IosLibraryExample/{feature}SampleSupport.swift",
    ],
    "macOS": [
        "mac/MacLibraryExample/MacLibraryExample/{feature}SampleView.swift",
        "mac/MacLibraryExample/MacLibraryExample/{feature}SampleSupport.swift",
    ],
    "Android": [
        "android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/"
        "android/nativetoolkit/example/{feature}SampleScreen.kt"
    ],
    "Windows": ["windows/WindowsLibraryExample/{feature}Page.xaml.cpp"],
}

# Localized platform headings map back to the canonical key above.
PLATFORM_ALIASES = {"mac": "macOS", "macos": "macOS", "ios": "iOS",
                    "android": "Android", "windows": "Windows"}


def feature_files():
    """Manual pages that document a feature, grouped by feature name."""
    groups = {}
    for p in sorted(MANUAL.glob("*.md")):
        stem = p.name[: -len(".md")]
        for suffix in (".ja", ".ko"):
            if stem.endswith(suffix):
                stem = stem[: -len(suffix)]
                break
        if stem == "index":
            continue
        groups.setdefault(stem, []).append(p)
    return groups


def strip_code_blocks(text):
    """Yield (line, in_code) for every line, tracking ``` fences."""
    in_code = False
    for line in text.split("\n"):
        if line.startswith("```"):
            in_code = not in_code
            yield line, True
            continue
        yield line, in_code


def code_blocks(text):
    """Yield (language, body) for every fenced block."""
    lang, buf, in_code = None, [], False
    for line in text.split("\n"):
        if line.startswith("```"):
            if in_code:
                yield lang, "\n".join(buf)
                lang, buf, in_code = None, [], False
            else:
                lang, in_code = line[3:].strip() or None, True
            continue
        if in_code:
            buf.append(line)


def anchor_of(title, counts):
    """GitHub's heading-anchor algorithm, including the -1/-2 duplicate suffix."""
    a = re.sub(r"[^\w\s-]", "", title.strip().lower(), flags=re.UNICODE).replace(" ", "-")
    n = counts.get(a, 0)
    counts[a] = n + 1
    return a if n == 0 else f"{a}-{n}"


# --- 1. image references (BLOCKING) ------------------------------------------

def check_images():
    findings = []
    for p in sorted(MANUAL.glob("*.md")):
        text = p.read_text()
        for ref in sorted(set(re.findall(r"images/[A-Za-z0-9_/.-]+\.(?:png|jpg|jpeg|gif|svg)", text))):
            if not (MANUAL / ref).is_file():
                findings.append(f"{p.name} -> {ref}")
    return findings


# --- 2. sample app conformance (warning) -------------------------------------
#
# Only the values that must match something real are compared, because manual
# code examples legitimately invent display strings the sample app never uses:
#
#   a. identifier-shaped literals  "public.png", "com.example.app.custom"
#   b. resource-name arguments     forResource: "app-icon-attachment"
#   c. argument labels             onPartialFailure:
#
# Comparison is limited to code fences whose language matches the platform, so
# manifest XML and Gradle snippets are not treated as sample app code.

FENCE_LANGUAGES = {"iOS": {"swift"}, "macOS": {"swift"},
                   "Android": {"kotlin"}, "Windows": {"cpp", "c++"}}

IDENTIFIER_LITERAL = re.compile(r'^"[A-Za-z0-9_][A-Za-z0-9_.-]*\.[A-Za-z0-9_.-]+"$')
RESOURCE_ARGUMENT = re.compile(
    r'\b(?:forResource|withExtension|ofType|named|imageNamed):\s*("[^"\n]+")'
)


def load_ignores():
    if not IGNORE_FILE.is_file():
        return set()
    out = set()
    for line in IGNORE_FILE.read_text().split("\n"):
        line = line.split("#", 1)[0].strip()
        if line:
            out.add(line)
            out.add(line.strip('"'))
    return out


def platform_sections(text):
    """Split a manual page into (canonical platform, body) by its `## ` headings."""
    sections, current, buf = [], None, []
    for line in text.split("\n"):
        m = re.match(r"^## (.+)$", line)
        if m:
            if current:
                sections.append((current, "\n".join(buf)))
            key = re.sub(r"[^a-z]", "", m.group(1).strip().lower())
            current, buf = PLATFORM_ALIASES.get(key), []
            continue
        if current:
            buf.append(line)
    if current:
        sections.append((current, "\n".join(buf)))
    return [(p, b) for p, b in sections if p]


def check_sample_conformance():
    findings, notes = [], []
    ignores = load_ignores()
    for feature in sorted(feature_files()):
        # The English page is the source of truth; translations reuse its code.
        page = MANUAL / f"{feature}.md"
        if not page.is_file():
            continue
        for platform, body in platform_sections(page.read_text()):
            candidates = [Path(t.format(feature=feature.capitalize()))
                          for t in SAMPLE_SOURCES.get(platform, [])]
            sources = [c for c in candidates if c.is_file()]
            if not sources:
                notes.append(f"{page.name} [{platform}] no sample screen found "
                             f"({', '.join(str(c) for c in candidates) or 'no mapping'})")
                continue
            # Every file of the screen, not the first that exists: taking only
            # the first made a literal declared in the companion file look absent
            # (R-SA29).
            sample = "\n".join(c.read_text() for c in sources)
            source = sources[0] if len(sources) == 1 else Path(
                " / ".join(c.name for c in sources))
            where = f"{page.name} [{platform}]"
            for lang, block in code_blocks(body):
                if lang not in FENCE_LANGUAGES.get(platform, set()):
                    continue
                checked = set()
                for lit in sorted(set(IDENTIFIER_LITERAL.findall(block) or [])):
                    checked.add(lit)
                for lit in sorted({m for m in re.findall(r'"[^"\n]+"', block)
                                   if IDENTIFIER_LITERAL.match(m)}):
                    checked.add(lit)
                checked |= set(RESOURCE_ARGUMENT.findall(block))
                for lit in sorted(checked):
                    if lit in ignores or lit.strip('"') in ignores:
                        continue
                    if lit not in sample:
                        findings.append(f"{where} literal not in {source.name}: {lit}")
                for label in sorted(set(re.findall(r"^\s+([a-zA-Z][a-zA-Z0-9]*):",
                                                   block, flags=re.M))):
                    if f"{label}:" in ignores or label in ignores:
                        continue
                    if f"{label}:" not in sample:
                        findings.append(f"{where} argument label not in "
                                        f"{source.name}: {label}:")
    return findings, notes


# --- 3. table-of-contents anchors (BLOCKING) ---------------------------------

def check_anchors():
    findings = []
    for p in sorted(MANUAL.glob("*.md")):
        text = p.read_text()
        counts, anchors = {}, set()
        for line, in_code in strip_code_blocks(text):
            if in_code:
                continue
            m = re.match(r"^(#{1,6}) (.+)$", line)
            if m:
                anchors.add(anchor_of(m.group(2), counts))
        for link in re.findall(r"\]\((#[^)]+)\)", text):
            if link[1:] not in anchors:
                findings.append(f"{p.name} -> {link}")
    return findings


# --- 4. artifact filenames (BLOCKING) ----------------------------------------

def check_artifacts():
    findings = []
    if not DIST.is_dir():
        return [f"dist/{VERSION} does not exist, so artifact names cannot be verified"]
    actual = {p.name for p in DIST.rglob("*") if p.is_file() or p.suffix == ".xcframework"}
    actual |= {p.name for p in DIST.glob("*/*")}
    pattern = re.compile(
        r"(?:unity-)?(?:android|ios|mac|windows)-native-toolkit-[0-9]+\.[0-9]+\.[0-9]+"
        r"\.(?:aar|xcframework|nupkg|dll|lib)"
    )
    for p in sorted(MANUAL.glob("*.md")):
        text = p.read_text()
        for name in sorted(set(pattern.findall(text))):
            if name not in actual:
                findings.append(f"{p.name} names {name}, which is not in dist/{VERSION}/")
    # A manual must not point at another version's dist directory either.
    for p in sorted(MANUAL.glob("*.md")):
        for other in sorted(set(re.findall(r"dist/([0-9]+\.[0-9]+\.[0-9]+)/", p.read_text()))):
            if other != VERSION:
                findings.append(f"{p.name} references dist/{other}/ instead of dist/{VERSION}/")
    return findings


# --- 5. prose style (warning) ------------------------------------------------

JA_PLAIN = re.compile(r"(?:する|できる|なる|ある|ない|行う|返す|持つ|使う|扱う|示す)。")
JA_POLITE = re.compile(r"(?:ます|です|ません|でした|ましょう|ください|下さい)。")
KO_PLAIN = re.compile(r"(?:한다|된다|없다|있다|아니다|같다|한다)\.")
KO_POLITE = re.compile(r"(?:니다|시오)\.")


def check_prose_style():
    findings = []
    for p in sorted(MANUAL.glob("*.ja.md")):
        for i, (line, in_code) in enumerate(strip_code_blocks(p.read_text()), start=1):
            if in_code or line.lstrip().startswith(("//", "#", "|")):
                continue
            for seg in re.findall(r"[^。]{0,20}。", line):
                if JA_PLAIN.search(seg) and not JA_POLITE.search(seg):
                    findings.append(f"{p.name}:{i} plain form: {seg.strip()}")
    for p in sorted(MANUAL.glob("*.ko.md")):
        for i, (line, in_code) in enumerate(strip_code_blocks(p.read_text()), start=1):
            if in_code or line.lstrip().startswith(("//", "#", "|")):
                continue
            for seg in re.findall(r"[^.]{0,20}\.", line):
                if KO_PLAIN.search(seg) and not KO_POLITE.search(seg):
                    findings.append(f"{p.name}:{i} plain form: {seg.strip()}")
    return findings


# --- 6. language parity (warning) --------------------------------------------

def check_language_parity():
    findings = []
    for feature, pages in sorted(feature_files().items()):
        variants = {}
        for suffix in ("", ".ja", ".ko"):
            p = MANUAL / f"{feature}{suffix}.md"
            if p.is_file():
                variants[suffix or "en"] = p
        if len(variants) < 2:
            continue
        stats = {}
        for lang, p in variants.items():
            text = p.read_text()
            imgs = set(re.findall(r"images/[A-Za-z0-9_/.-]+\.(?:png|jpg|jpeg|gif|svg)", text))
            heads = sum(1 for line, in_code in strip_code_blocks(text)
                        if not in_code and re.match(r"^#{2,6} ", line))
            stats[lang] = (imgs, heads)
        base_lang, (base_imgs, base_heads) = next(iter(stats.items()))
        for lang, (imgs, heads) in stats.items():
            if lang == base_lang:
                continue
            for missing in sorted(base_imgs - imgs):
                findings.append(f"{feature}: {lang} is missing an image {base_lang} has: {missing}")
            for extra in sorted(imgs - base_imgs):
                findings.append(f"{feature}: {lang} has an image {base_lang} lacks: {extra}")
            if heads != base_heads:
                findings.append(f"{feature}: {lang} has {heads} headings, {base_lang} has {base_heads}")
    return findings


# --- runner -------------------------------------------------------------------

CHECKS = [
    ("image references", "BLOCKING", lambda: (check_images(), [])),
    ("sample conformance", "warning", check_sample_conformance),
    ("anchors", "BLOCKING", lambda: (check_anchors(), [])),
    ("artifact filenames", "BLOCKING", lambda: (check_artifacts(), [])),
    ("prose style (ja/ko)", "warning", lambda: (check_prose_style(), [])),
    ("language parity", "warning", lambda: (check_language_parity(), [])),
]

print(f"Verifying manual/{VERSION}\n")

blocking, warned = [], []
for index, (name, level, fn) in enumerate(CHECKS, start=1):
    findings, notes = fn()
    findings = list(dict.fromkeys(findings))  # same value can appear in several fences
    notes = list(dict.fromkeys(notes))
    is_blocking = level == "BLOCKING" or STRICT
    if findings:
        status = "FAIL" if is_blocking else "WARN"
        (blocking if is_blocking else warned).append(name)
    else:
        status = "OK"
    print(f"[{index}/{len(CHECKS)}] {name:<22} {status}"
          + (f" ({len(findings)})" if findings else ""))
    if not QUIET:
        for f in findings:
            print(f"          {f}")
        for n in notes:
            print(f"          note: {n}")

print()
print(f"Blocking failures: {len(blocking)}" + (f" ({', '.join(blocking)})" if blocking else ""))
print(f"Warnings:          {len(warned)}" + (f" ({', '.join(warned)})" if warned else ""))

sys.exit(1 if blocking else 0)
PYTHON
