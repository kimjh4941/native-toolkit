#!/usr/bin/env python3
"""Check the manual's Windows C examples against the C ABI they demonstrate.

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

What every OS checks the same way lives in manual_c_examples_common.py; this
file keeps what only Windows has: the .def, the prelude and MSBuild (Android
C ABI design part 2, 0.3).

Usage:
    python3 scripts/check_manual_c_examples_windows.py [<version>] [--root <tree>]
                                                       [--require-compile] [--keep]

<version> is a folder under manual/ (default: the highest one).
--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.
--keep leaves the generated C files behind, for looking at a compile failure.

Exit status is 1 when any check fails.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import manual_c_examples_common as common
from c_abi_contract_common import Report

ROOT = Path(__file__).resolve().parent.parent

DEF = "windows/WindowsLibraryCApi/WindowsLibraryCApi.def"
INCLUDE = "windows/WindowsLibraryCApi/include"
MANUAL = common.MANUAL
OS_NAME = "Windows"

# What the examples take as given: the handles and buffers a reader already
# has. Declared for the compile check so the fragments stand on their own.
PRELUDE = """/* Generated from the manual's C examples by check_manual_c_examples_windows.py. */
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
        sources, unwritable = common.write_sources(found, work, PRELUDE)
        if unwritable:
            rep.check(False, name, "; ".join(unwritable))
            return
        count = len(sources)

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

    version = arguments[0] if arguments else common.latest_version(ROOT)
    rep = Report()
    if version is None:
        rep.check(False, "the manual is readable", f"cannot read {MANUAL}")
        rep.title = "manual/? C examples"
        return 0 if rep.dump() else 1
    rep.title = f"manual/{version} C examples"

    found = common.pages(ROOT, version, rep, OS_NAME)
    if found is not None:
        exports = exported(rep)
        if exports is not None:
            common.check_coverage(found, exports, rep)
        declared = common.declared_names(ROOT, INCLUDE, rep)
        if declared is not None:
            common.check_symbols(found, declared, rep)
        common.check_parity(found, rep, OS_NAME)
        check_compile(found, rep, require, keep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
