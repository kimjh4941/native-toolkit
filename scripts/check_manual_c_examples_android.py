#!/usr/bin/env python3
"""Check the manual's Android C examples against the C ABI they demonstrate.

The manual's Android chapters will document the C ABI in a "C ABI" section
whose code blocks are plain C (README stage 4). Until a page has one, this
says SKIP and passes: there is nothing to check yet, and the checks below are
ready for when there is. --require-examples makes that absence a failure,
which is what a manual that should have the section (2.0.0 on) asks for. A
heading that nearly reads "### C ABI" fails either way.

  coverage   every function the public headers declare appears in an example
  symbols    every ntk_ and NTK_ name an example uses exists in the headers
  parity     the three languages carry the same code, comments aside
  compile    the examples compile as plain C99 with the NDK's clang
             (-Wall -Wextra -Werror)

A file that cannot be read fails its check. The compile check needs the NDK
and says SKIP without it; --require-compile makes its absence a failure, and a
--clang that does not exist always fails. An argument this script does not
know is a usage error.

What every OS checks the same way lives in manual_c_examples_common.py.

Usage:
    python3 scripts/check_manual_c_examples_android.py [<version>] [--root <tree>]
                                                       [--require-examples] [--require-compile]
                                                       [--keep] [--clang <clang>]

<version> is a folder under manual/ (default: the highest one).
--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.
--keep leaves the generated C files behind, for looking at a compile failure.

Exit status is 1 when any check fails.
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import manual_c_examples_common as common
from c_abi_contract_common import Report, declarations
from check_c_abi_contract_android import find_ndk_tool

ROOT = Path(__file__).resolve().parent.parent

INCLUDE = "android/android_library_capi/src/main/cpp/include"
# Every public header: coverage asks for each function of each, so a header
# that is missing has to fail rather than shrink what is asked for.
HEADERS = ("Common.h", "Android.h", "Clipboard.h", "Dialog.h", "Notification.h", "Share.h")
MANUAL = common.MANUAL
OS_NAME = "Android"
# The lowest API level the library supports (README: Android 12).
TARGET = "aarch64-linux-android31"

# What the examples take as given: the handles and buffers a reader already
# has. Declared for the compile check so the fragments stand on their own.
# Stage 4 adds what its examples assume.
PRELUDE = """/* Generated from the manual's C examples by check_manual_c_examples_android.py. */
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Clipboard.h>
#include <NativeToolkitC/Dialog.h>
#include <NativeToolkitC/Notification.h>
#include <NativeToolkitC/Share.h>
"""

# The examples leave results, parameters and helpers unused on purpose, and
# each block becomes a static function nothing calls.
IGNORED_WARNINGS = ("-Wno-unused-variable", "-Wno-unused-parameter", "-Wno-unused-function",
                    "-Wno-unused-but-set-variable")


def at(fragment):
    return ROOT / fragment


def exported(rep):
    """The functions the public headers declare, or None. Android has no .def:
    the version script exports ntk_* (AP-15), so the headers are the list. The
    library's real exports are check_c_abi_contract_android.py --library's to
    compare with them."""
    missing = [h for h in HEADERS if not at(f"{INCLUDE}/NativeToolkitC/{h}").exists()]
    if missing:
        rep.check(False, "coverage: every exported function appears in an example",
                  f"cannot read {', '.join(f'{INCLUDE}/NativeToolkitC/{h}' for h in missing)}")
        return None
    names = set()
    for header in HEADERS:
        names |= set(declarations(at(f"{INCLUDE}/NativeToolkitC/{header}").read_text(encoding="utf-8"))["function"])
    return names


def find_clang(given):
    """The NDK's clang, or None; never the host's, which has no Android
    sysroot. An explicit path is returned as given."""
    return find_ndk_tool("clang", given, search_path=False)


def check_compile(found, rep, require, keep, clang):
    name = "compile: the examples compile as plain C"
    if clang and not Path(clang).exists():
        rep.check(False, name, f"cannot run {clang}")
        return
    compiler = find_clang(clang)
    if compiler is None:
        if require:
            rep.check(False, name, "the NDK's clang was not found and --require-compile was given")
        else:
            rep.skip(name, "the NDK's clang was not found; install the NDK or give --clang")
        return

    include = at(INCLUDE)
    if not include.is_dir():
        rep.check(False, name, f"cannot read {INCLUDE}")
        return

    work = Path(tempfile.mkdtemp(prefix="manual-c-examples-android-"))
    try:
        sources, problems = common.write_sources(found, work, PRELUDE, encoding="utf-8")
        for source in sources:
            result = subprocess.run(
                [compiler, f"--target={TARGET}", "-x", "c", "-std=c99", "-Wall", "-Wextra", "-Werror",
                 *IGNORED_WARNINGS, "-fsyntax-only", f"-I{include}", str(source)],
                capture_output=True, text=True, errors="replace")
            if result.returncode != 0:
                errors = [line.strip() for line in result.stderr.splitlines() if "error" in line]
                problems.append(f"{source.name}: {' | '.join(errors) or result.returncode}")
        rep.check(not problems, f"{name} ({len(sources)} examples)", "; ".join(problems)[:2000])
        if keep:
            print(f"  note: the generated files are in {work}")
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)


USAGE = ("usage: check_manual_c_examples_android.py [<version>] [--root <tree>] [--require-examples] "
         "[--require-compile] [--keep] [--clang <clang>]")


def parse_arguments(argv):
    """The options and the version; None on a usage error."""
    with_value = {"--root", "--clang"}
    flags = {"--require-examples", "--require-compile", "--keep"}
    parsed, rest = {}, list(argv)
    while rest:
        argument = rest.pop(0)
        if argument in with_value:
            if not rest or rest[0].startswith("--"):
                print(f"{argument} needs a value\n{USAGE}", file=sys.stderr)
                return None
            parsed[argument] = rest.pop(0)
        elif argument in flags:
            parsed[argument] = True
        elif not argument.startswith("--") and "version" not in parsed:
            parsed["version"] = argument
        else:
            print(f"unknown argument {argument}\n{USAGE}", file=sys.stderr)
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
    clang = parsed.get("--clang")
    require = parsed.get("--require-compile", False)
    keep = parsed.get("--keep", False)

    version = parsed.get("version") or common.latest_version(ROOT)
    rep = Report()
    if version is None:
        rep.check(False, "the manual is readable", f"cannot read {MANUAL}")
        rep.title = "manual/? Android C examples"
        return 0 if rep.dump() else 1
    rep.title = f"manual/{version} Android C examples"

    found = common.pages(ROOT, version, rep, OS_NAME,
                         missing_is_failure=parsed.get("--require-examples", False))
    if found is not None:
        exports = exported(rep)
        if exports is not None:
            common.check_coverage(found, exports, rep)
        declared = common.declared_names(ROOT, INCLUDE, rep)
        if declared is not None:
            common.check_symbols(found, declared, rep)
        common.check_parity(found, rep, OS_NAME)
        check_compile(found, rep, require, keep, clang)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
