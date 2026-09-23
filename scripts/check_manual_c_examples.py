#!/usr/bin/env python3
"""Check the manual's C examples against the C ABI they demonstrate.

The manual's Windows chapters document the C++ API in prose and the C ABI in a
"C ABI" section whose code blocks are plain C. Nothing else checks those
blocks: verify_manual.sh compares code examples against the sample app, and the
sample app is C++, so a renamed or dropped C function would leave the examples
wrong and silent.

  coverage   every function the .def exports appears in at least one example
  symbols    every ntk_ and NTK_ name an example uses exists in the headers
  parity     the three languages carry the same code, comments aside
  compile    the examples compile as plain C (/TC, /W4, warnings as errors)

A file that cannot be read fails its check: a check that skips because its
subject is missing reports agreement it never checked. The compile check is
the one exception - it needs MSVC, which only exists on Windows, and says so
rather than failing elsewhere. Pass --require-compile to make its absence a
failure, which is what a Windows CI should do.

Usage:
    python3 scripts/check_manual_c_examples.py [<version>] [--root <tree>]
                                               [--require-compile] [--keep]

<version> is a folder under manual/ (default: the highest one).
--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.
--keep leaves the generated C files behind, for looking at a compile failure.

Exit status is 1 when any check fails.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DEF = "windows/WindowsLibraryCApi/WindowsLibraryCApi.def"
INCLUDE = "windows/WindowsLibraryCApi/include"
MANUAL = "manual"
LANGUAGES = ("", ".ja", ".ko")

# What the examples take as given: the handles and buffers a reader already
# has. Declared for the compile check so the fragments stand on their own.
PRELUDE = """/* Generated from the manual's C examples by check_manual_c_examples.py. */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Clipboard.h>
#include <NativeToolkitC/Dialog.h>
#include <NativeToolkitC/Notification.h>

extern ntk_clipboard_session* session;
extern ntk_notification_manager* manager;
extern const uint8_t* dib_bytes;
extern size_t dib_size;
extern const uint8_t* payload_bytes;
extern size_t payload_size;
extern void* payloads;
extern const char* item_id;
extern int lookup_payload(void* user_data, const char* format_name,
                          const uint8_t** out_bytes, size_t* out_size);
"""

# 4189/4100: the examples leave results and parameters unused on purpose.
# 4459: the prelude above declares globals that an example shadows locally.
IGNORED_WARNINGS = ("4189", "4100", "4459")


def at(fragment):
    return ROOT / fragment


class Report:
    def __init__(self):
        self.lines = []
        self.failed = False

    def check(self, condition, name, detail=""):
        if condition:
            self.lines.append(f"  OK   {name}")
        else:
            self.lines.append(f"  FAIL {name}: {detail}")
            self.failed = True

    def skip(self, name, detail):
        self.lines.append(f"  SKIP {name}: {detail}")

    def dump(self, version):
        print(f"== manual/{version} C examples")
        for line in self.lines:
            print(line)
        return not self.failed


def latest_version():
    """The highest manual/<version>, by its numeric parts."""
    folder = at(MANUAL)
    if not folder.is_dir():
        return None
    versions = []
    for entry in folder.iterdir():
        if entry.is_dir() and re.fullmatch(r"\d+(\.\d+)*", entry.name):
            versions.append(entry.name)
    if not versions:
        return None
    return max(versions, key=lambda v: tuple(int(p) for p in v.split(".")))


def c_blocks(text):
    """The C code blocks of the Windows chapter's C ABI section."""
    if "## Windows\n" not in text:
        return None
    windows = text[text.index("## Windows\n"):]
    if "### C ABI\n" not in windows:
        return None
    section = windows[windows.index("### C ABI\n"):]
    end = section.find("\n---\n\n## ")
    if end != -1:
        section = section[:end]
    return re.findall(r"```c\n(.*?)```", section, re.S)


def pages(version, rep):
    """{page name: {language: [block, ...]}}, or None when nothing was read."""
    folder = at(f"{MANUAL}/{version}")
    if not folder.is_dir():
        rep.check(False, "the manual is readable", f"cannot read {MANUAL}/{version}")
        return None

    found = {}
    for path in sorted(folder.glob("*.md")):
        name = path.name
        if any(name.endswith(f"{suffix}.md") for suffix in LANGUAGES if suffix):
            continue                      # a translation; reached through its English page
        stem = name[:-len(".md")]
        blocks = c_blocks(path.read_text(encoding="utf-8-sig"))
        if blocks is None:
            continue                      # a page with no Windows C ABI section
        found[stem] = {"": blocks}
        for suffix in LANGUAGES:
            if not suffix:
                continue
            other = folder / f"{stem}{suffix}.md"
            if not other.exists():
                rep.check(False, "the manual is readable", f"cannot read {other.name}")
                continue
            found[stem][suffix] = c_blocks(other.read_text(encoding="utf-8-sig"))

    if not found:
        rep.check(False, "the manual is readable",
                  f"no page under {MANUAL}/{version} has a Windows C ABI section")
        return None
    return found


def exported(rep):
    """The functions the .def exports, or None."""
    path = at(DEF)
    if not path.exists():
        rep.check(False, "coverage: every exported function appears in an example",
                  f"cannot read {DEF}")
        return None
    names = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("ntk_"):
            names.add(line.split()[0])
    return names


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

def declared_names(rep):
    """Every ntk_ and NTK_ name the public headers declare, or None.

    Functions, types and constants together: an example names all three, and a
    renamed one has to fail whichever kind it is.
    """
    folder = at(INCLUDE)
    headers = sorted(folder.glob("**/*.h")) if folder.is_dir() else []
    if not headers:
        rep.check(False, "symbols: every ntk_ and NTK_ name exists in the headers",
                  f"cannot read {INCLUDE}")
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


def check_parity(found, rep):
    problems = []
    for stem, languages in sorted(found.items()):
        english = languages[""]
        for suffix in LANGUAGES:
            if not suffix or suffix not in languages:
                continue
            other = languages[suffix]
            if other is None:
                problems.append(f"{stem}{suffix}: no Windows C ABI section")
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


# --- 4. compile --------------------------------------------------------------

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


def find_msbuild():
    """MSBuild from the newest Visual Studio, or None.

    MSBuild rather than cl.exe directly: cl needs the developer environment
    for the Windows SDK headers, and a project file sets that up itself, the
    way the rest of the repository builds.
    """
    program_files = os.environ.get("ProgramFiles(x86)")
    if not program_files:
        return None
    vswhere = Path(program_files) / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not vswhere.exists():
        return None
    try:
        found = subprocess.run(
            [str(vswhere), "-latest", "-requires", "Microsoft.Component.MSBuild",
             "-find", r"MSBuild\**\Bin\MSBuild.exe"],
            capture_output=True, text=True, timeout=60).stdout.split("\n")
    except (OSError, subprocess.SubprocessError):
        return None
    found = [line.strip() for line in found if line.strip()]
    return found[0] if found else None


PROJECT = """<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Label="ProjectConfigurations">
    <ProjectConfiguration Include="Release|x64">
      <Configuration>Release</Configuration>
      <Platform>x64</Platform>
    </ProjectConfiguration>
  </ItemGroup>
  <PropertyGroup Label="Globals">
    <ProjectGuid>{0D1B9F26-7A4E-4C0B-9B51-4E9A1C7D2F63}</ProjectGuid>
    <WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>
  </PropertyGroup>
  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.Default.props" />
  <PropertyGroup Label="Configuration">
    <!-- A static library: the examples are fragments, so there is no main. -->
    <ConfigurationType>StaticLibrary</ConfigurationType>
    <PlatformToolset>v143</PlatformToolset>
    <UseDebugLibraries>false</UseDebugLibraries>
  </PropertyGroup>
  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.props" />
  <ItemDefinitionGroup>
    <ClCompile>
      <CompileAs>CompileAsC</CompileAs>
      <WarningLevel>Level4</WarningLevel>
      <TreatWarningAsError>true</TreatWarningAsError>
      <PrecompiledHeader>NotUsing</PrecompiledHeader>
      <AdditionalIncludeDirectories>__INCLUDE__;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
      <DisableSpecificWarnings>__IGNORED__</DisableSpecificWarnings>
    </ClCompile>
  </ItemDefinitionGroup>
  <ItemGroup>
    <ClCompile Include="*.c" />
  </ItemGroup>
  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />
</Project>
"""


def check_compile(found, rep, require, keep):
    msbuild = find_msbuild()
    name = "compile: the examples compile as plain C"
    if msbuild is None:
        if require:
            rep.check(False, name, "MSBuild was not found and --require-compile was given")
        else:
            rep.skip(name, "MSBuild was not found; run this on Windows with Visual Studio")
        return

    include = at(INCLUDE)
    if not include.is_dir():
        rep.check(False, name, f"cannot read {INCLUDE}")
        return

    work = Path(tempfile.mkdtemp(prefix="manual-c-examples-"))
    try:
        count = 0
        for stem, languages in sorted(found.items()):
            for index, block in enumerate(languages[""], start=1):
                head, body = split_block(block)
                head = "\n".join(l for l in head.split("\n") if not l.startswith("#include"))
                (work / f"{stem}_{index}.c").write_text(
                    f"{PRELUDE}\n{head}\n\nstatic void example_{stem}_{index}(void)\n{{\n{body}\n}}\n",
                    encoding="ascii")
                count += 1

        project = work / "manual-c-examples.vcxproj"
        project.write_text(
            PROJECT.replace("__INCLUDE__", str(include)).replace("__IGNORED__", ";".join(IGNORED_WARNINGS)),
            encoding="utf-8")

        # MSBuild writes in the console's code page, which is not always
        # decodable; the detail is only quoted back, so replace what is not.
        result = subprocess.run(
            [msbuild, str(project), "/t:Build", "/p:Configuration=Release", "/p:Platform=x64",
             "/nologo", "/v:minimal"],
            capture_output=True, cwd=work)
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        problems = [line.strip() for line in output.splitlines()
                    if "error" in line or "warning" in line]
        rep.check(result.returncode == 0, f"{name} ({count} examples)",
                  " | ".join(problems)[:2000] or f"MSBuild exited {result.returncode}")
        if keep:
            print(f"  note: the generated files are in {work}")
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)


def main(argv):
    global ROOT
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    arguments = list(argv[1:])
    if "--root" in arguments:
        index = arguments.index("--root")
        ROOT = Path(arguments[index + 1]).resolve()
        del arguments[index:index + 2]
    require = "--require-compile" in arguments
    if require:
        arguments.remove("--require-compile")
    keep = "--keep" in arguments
    if keep:
        arguments.remove("--keep")

    version = arguments[0] if arguments else latest_version()
    rep = Report()
    if version is None:
        rep.check(False, "the manual is readable", f"cannot read {MANUAL}")
        return 0 if rep.dump("?") else 1

    found = pages(version, rep)
    if found is not None:
        exports = exported(rep)
        if exports is not None:
            check_coverage(found, exports, rep)
        declared = declared_names(rep)
        if declared is not None:
            check_symbols(found, declared, rep)
        check_parity(found, rep)
        check_compile(found, rep, require, keep)
    return 0 if rep.dump(version) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
