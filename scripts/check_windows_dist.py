#!/usr/bin/env python3
"""Check that dist/<release>/windows/ was built from the sources in this tree.

dist/ is committed and rebuilt by hand with build_windows_library_dll.ps1, so
it can fall behind the source without anyone noticing. It has: 67217afb
changed two public headers and dist kept the old ones until an unrelated
rebuild picked them up. This is what a release should run before it ships.

  source    the sources the build read are the sources in the tree now. The
            build script records a hash of them in SOURCE-HASH.txt; a
            mismatch means something changed after the last build.
  headers   the public headers in dist/<release>/windows/include/ and inside
            both .nupkg files are byte for byte the ones in the tree
  names     the distributables carry the versions the headers declare
            (NATIVETOOLKIT_VERSION_* and NTK_VERSION_*)
  exports   every function the .def exports is named in the DLL, both the
            loose one and the one inside NativeToolkit.CApi

A file that cannot be read fails its check: a check that skips because its
subject is missing reports agreement it never checked.

Usage:
    python3 scripts/check_windows_dist.py [<release>] [--root <tree>]
    python3 scripts/check_windows_dist.py <release> --stamp [--root <tree>]

<release> is a folder under dist/ (default: the highest one with windows/).
--stamp writes SOURCE-HASH.txt instead of checking; the build script calls it
after it has written the distributables.
--root aims every path at another copy of the repository, which is how the
self-test breaks one thing at a time without editing the real one.

Exit status is 1 when any check fails.
"""

import hashlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STAMP = "SOURCE-HASH.txt"

# What the build reads. Build outputs are excluded because only tracked files
# are hashed.
SOURCES = [
    "windows/WindowsLibrary/include",
    "windows/WindowsLibrary/src",
    "windows/WindowsLibrary/WindowsLibrary.vcxproj",
    "windows/WindowsLibrary/packages.config",
    "windows/WindowsLibrary/pch.cpp",
    "windows/WindowsLibrary/pch.h",
    "windows/WindowsLibrary/targetver.h",
    "windows/WindowsLibraryCApi/include",
    "windows/WindowsLibraryCApi/src",
    "windows/WindowsLibraryCApi/WindowsLibraryCApi.def",
    "windows/WindowsLibraryCApi/WindowsLibraryCApi.vcxproj",
    "windows/WindowsLibraryCApi/WindowsLibraryCApi.rc",
    "scripts/nuget",
    "scripts/build_windows_library_dll.ps1",
]

# Public header folder in the tree -> its name under include/ in dist and in
# the package.
HEADERS = {
    "windows/WindowsLibrary/include/NativeToolkit": "NativeToolkit",
    "windows/WindowsLibraryCApi/include/NativeToolkitC": "NativeToolkitC",
}

DEF = "windows/WindowsLibraryCApi/WindowsLibraryCApi.def"
CPP_VERSION = ("windows/WindowsLibrary/include/NativeToolkit/BuildStamp.h", "NATIVETOOLKIT_VERSION")
C_VERSION = ("windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h", "NTK_VERSION")


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

    def dump(self, release):
        print(f"== dist/{release}/windows")
        for line in self.lines:
            print(line)
        return not self.failed


def tracked(paths):
    """Tracked files under the given paths, relative and sorted."""
    result = subprocess.run(["git", "ls-files", "--", *paths], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        return None
    return sorted(line for line in result.stdout.split("\n") if line)


def normalise(data):
    # A checkout may have CRLF where the build machine had LF. UTF-16 text
    # (the .rc) has no b"\r\n" in it, so it is left alone.
    return data.replace(b"\r\n", b"\n")


def source_hash():
    """(hex digest, file count) over the tracked build inputs, or None."""
    files = tracked(SOURCES)
    if not files:
        return None
    digest = hashlib.sha256()
    for rel in files:
        path = at(rel)
        if not path.is_file():
            continue          # tracked but deleted in the working tree
        digest.update(rel.encode("utf-8") + b"\0")
        digest.update(normalise(path.read_bytes()) + b"\0")
    return digest.hexdigest(), len(files)


def declared_version(fragment, macro):
    path = at(fragment)
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    parts = []
    for part in ("MAJOR", "MINOR", "PATCH"):
        m = re.search(rf"#define\s+{macro}_{part}\s+(\d+)", text)
        if not m:
            return None
        parts.append(m.group(1))
    return ".".join(parts)


def latest_release():
    dist = at("dist")
    if not dist.is_dir():
        return None
    versions = [p.name for p in dist.iterdir()
                if p.is_dir() and (p / "windows").is_dir() and re.fullmatch(r"\d+(\.\d+)*", p.name)]
    if not versions:
        return None
    return max(versions, key=lambda v: tuple(int(x) for x in v.split(".")))


# --- stamp ---------------------------------------------------------------------

def stamp(release):
    folder = at(f"dist/{release}/windows")
    if not folder.is_dir():
        print(f"cannot read dist/{release}/windows")
        return 1
    result = source_hash()
    if result is None:
        print("no tracked build inputs found")
        return 1
    digest, count = result
    (folder / STAMP).write_text(
        f"{digest}\n"
        f"# sha256 over the {count} tracked build inputs of the Windows distributables,\n"
        f"# written by scripts/check_windows_dist.py --stamp when they were built.\n"
        f"# scripts/check_windows_dist.py compares it with the tree.\n",
        encoding="utf-8")
    print(f"stamped dist/{release}/windows/{STAMP}: {digest} ({count} files)")
    return 0


# --- 1. source -------------------------------------------------------------------

def check_source(folder, rep):
    name = "source: the distributables were built from the sources in this tree"
    recorded_path = folder / STAMP
    if not recorded_path.exists():
        rep.check(False, name, f"cannot read {STAMP}; rebuild with build_windows_library_dll.ps1")
        return
    recorded = recorded_path.read_text(encoding="utf-8").split("\n", 1)[0].strip()
    result = source_hash()
    if result is None:
        rep.check(False, name, "no tracked build inputs found")
        return
    current, count = result
    rep.check(recorded == current, name,
              f"recorded {recorded[:12]}, tree {current[:12]} over {count} files; "
              f"a build input changed after the last build - rebuild dist")


# --- 2. headers ------------------------------------------------------------------

def check_headers(folder, packages, rep):
    problems = []
    for source_dir, leaf in HEADERS.items():
        src = at(source_dir)
        if not src.is_dir():
            problems.append(f"cannot read {source_dir}")
            continue
        wanted = {p.name: normalise(p.read_bytes()) for p in src.glob("*.h")}

        shipped_dir = folder / "include" / leaf
        shipped = {p.name: normalise(p.read_bytes()) for p in shipped_dir.glob("*.h")} if shipped_dir.is_dir() else {}
        compare(wanted, shipped, f"include/{leaf}", problems)

        for package in packages:
            try:
                with zipfile.ZipFile(package) as z:
                    prefix = f"build/native/include/{leaf}/"
                    inside = {n[len(prefix):]: normalise(z.read(n)) for n in z.namelist()
                              if n.startswith(prefix) and n.endswith(".h")}
            except (OSError, zipfile.BadZipFile):
                problems.append(f"cannot read {package.name}")
                continue
            if inside:
                compare(wanted, inside, f"{package.name}:{leaf}", problems)
    rep.check(not problems, "headers: dist and both packages carry the tree's public headers",
              "; ".join(problems))


def compare(wanted, shipped, where, problems):
    missing = sorted(set(wanted) - set(shipped))
    extra = sorted(set(shipped) - set(wanted))
    differ = sorted(n for n in set(wanted) & set(shipped) if wanted[n] != shipped[n])
    if missing:
        problems.append(f"{where} lacks {', '.join(missing)}")
    if extra:
        problems.append(f"{where} has extra {', '.join(extra)}")
    if differ:
        problems.append(f"{where} differs in {', '.join(differ)}")


# --- 3. names --------------------------------------------------------------------

def expected_files(folder, rep):
    """The distributables the declared versions call for, or None."""
    cpp = declared_version(*CPP_VERSION)
    capi = declared_version(*C_VERSION)
    if cpp is None or capi is None:
        rep.check(False, "names: the distributables carry the declared versions",
                  "cannot read the version macros")
        return None
    names = [f"windows-native-toolkit-{cpp}.lib", f"windows-native-toolkit-{cpp}.nupkg",
             f"windows-native-toolkit-capi-{capi}.dll", f"windows-native-toolkit-capi-{capi}.lib",
             f"windows-native-toolkit-capi-{capi}.nupkg"]
    missing = [n for n in names if not (folder / n).exists()]
    rep.check(not missing, f"names: the distributables carry the declared versions ({cpp}, capi {capi})",
              f"missing {', '.join(missing)}")
    return {"dll": folder / names[2],
            "packages": [folder / names[1], folder / names[4]],
            "capi_package": folder / names[4]}


# --- 4. exports ------------------------------------------------------------------

def check_exports(files, rep):
    name = "exports: every function in the .def is named in the DLL"
    def_path = at(DEF)
    if not def_path.exists():
        rep.check(False, name, f"cannot read {DEF}")
        return
    exports = [line.split()[0] for line in def_path.read_text(encoding="utf-8").splitlines()
               if line.strip().startswith("ntk_")]
    problems = []

    def missing_in(data, where):
        absent = [e for e in exports if (e.encode("ascii") + b"\0") not in data]
        if absent:
            problems.append(f"{where} lacks {len(absent)} of {len(exports)} (e.g. {absent[0]})")

    dll = files["dll"]
    if dll.exists():
        missing_in(dll.read_bytes(), dll.name)
    else:
        problems.append(f"cannot read {dll.name}")
    try:
        with zipfile.ZipFile(files["capi_package"]) as z:
            inner = [n for n in z.namelist() if n.lower().endswith(".dll")]
            if not inner:
                problems.append(f"{files['capi_package'].name} has no DLL")
            for n in inner:
                missing_in(z.read(n), f"{files['capi_package'].name}:{n}")
    except (OSError, zipfile.BadZipFile):
        problems.append(f"cannot read {files['capi_package'].name}")
    rep.check(not problems, f"{name} ({len(exports)})", "; ".join(problems))


def main(argv):
    global ROOT
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    arguments = list(argv[1:])
    if "--root" in arguments:
        index = arguments.index("--root")
        ROOT = Path(arguments[index + 1]).resolve()
        del arguments[index:index + 2]
    stamping = "--stamp" in arguments
    if stamping:
        arguments.remove("--stamp")

    release = arguments[0] if arguments else latest_release()
    if release is None:
        print("no dist/<release>/windows/ to check")
        return 1
    if stamping:
        return stamp(release)

    rep = Report()
    folder = at(f"dist/{release}/windows")
    if not folder.is_dir():
        rep.check(False, "the distributables are readable", f"cannot read dist/{release}/windows")
        return 0 if rep.dump(release) else 1

    check_source(folder, rep)
    files = expected_files(folder, rep)
    packages = files["packages"] if files else sorted(folder.glob("*.nupkg"))
    check_headers(folder, [p for p in packages if p.exists()], rep)
    if files:
        check_exports(files, rep)
    return 0 if rep.dump(release) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
