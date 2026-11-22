#!/usr/bin/env python3
"""Check the iOS distributable against the C ABI's distribution rules.

The rules come from README 7.3 of artifact/topics/ios-c-abi/ and part 1, 5.4
and 5.5 of its C ABI design (C-5); part 2, TB-11 runs it:

  files       one ios-native-toolkit-capi-<version>.xcframework, whose name
              gives the library version, ios-native-toolkit-<version>.xcframework
              at that version, include/NativeToolkitC/, and no debug build of
              the capi (it ships in Release only: part 1, 5.4)
  slices      both xcframeworks have exactly ios-arm64 (arm64) and
              ios-arm64_x86_64-simulator (arm64 and x86_64), as their Info.plist
              says and as their binaries hold, each built for its platform
              (README D-11, 7.4)
  symbols     per slice and architecture, the capi exports the functions of
              the public headers of the tree and nothing else (AP-15)
  swift       the capi ships no Swift module, interface or -Swift.h, and
              Headers/ holds NativeToolkitC/ only (D-10, D-11); IosLibrary
              ships its swiftinterface for every architecture
  modules     the capi's Modules/module.modulemap is the tree's
  dependencies  per architecture (otool -L): the capi needs
              @rpath/IosLibrary.framework/IosLibrary, the OS's frameworks and
              libraries and /usr/lib/swift/ only, never @rpath/libswift*;
              IosLibrary needs nothing from @rpath
  exit        neither framework imports what runs a function at exit:
              __cxa_atexit, atexit, __cxa_thread_atexit, _tlv_atexit
              (part 1, 5.14, G-5)
  install     LC_ID_DYLIB is @rpath/<name>.framework/<name>
  version     per slice: CFBundleShortVersionString is the library version
              in both (P1-19), which is also the NTK_VERSION_* of the tree's
              Common.h; MinimumOSVersion and LC_BUILD_VERSION's minos are 18.0
              (D-15); the bundle ids are those of D-12
  privacy     IosLibrary has PrivacyInfo.xcprivacy in both slices, plutil
              -lint passes, it is the tree's, it declares no tracking and no
              collected data, and the categories of required-reason APIs it
              declares are those its sources use (Swift API design 8.8.1).
              The capi's sources use none, and it ships no manifest; if they
              come to use one, it must ship a manifest that declares it
  signature   D-18 (A): the ios-arm64 slices are not signed; the simulator
              slices carry the linker's ad-hoc signature at most (linker-signed,
              no Authority, no TeamIdentifier); no framework has a
              _CodeSignature folder
  headers     include/NativeToolkitC/, the capi's Headers/NativeToolkitC/ in
              both slices and the tree's headers are byte for byte the same

A file that cannot be read fails its check: a check that skips because its
subject is missing reports agreement it never checked.

Usage:
    python3 scripts/check_ios_dist.py [<release> | --dist <folder>] [--root <tree>]

<release> is a folder under dist/ (default: the highest one with an
ios/ios-native-toolkit-capi-<version>.xcframework); --dist names the folder
that holds the two xcframeworks and include/ directly, for a build that is not
under dist/ (scripts/build_ios_library_xcframework.sh --output-dir). --root
aims every path of the tree at another copy of the repository (the self-test).
The tools are the Xcode command line tools: lipo, nm, otool, codesign, plutil.

Exit status is 1 when any check fails.
"""

import plistlib
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from c_abi_contract_common import Report  # noqa: E402
from check_c_abi_contract_ios import check_symbols  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

LIBRARY = "IosLibrary"
CAPI = "IosLibraryCApi"
XCFRAMEWORK_NAME = {LIBRARY: "ios-native-toolkit", CAPI: "ios-native-toolkit-capi"}
BUNDLE_ID = {LIBRARY: "com.jonghyunkim.nativetoolkit.IosLibrary", CAPI: "com.jonghyunkim.nativetoolkit.IosLibraryCApi"}
HEADERS_IN_TREE = "ios/IosLibraryCApi/include/NativeToolkitC"
MODULE_MAP_IN_TREE = "ios/IosLibraryCApi/IosLibraryCApi/module.modulemap"
SOURCES = {LIBRARY: "ios/IosLibrary/IosLibrary", CAPI: "ios/IosLibraryCApi/IosLibraryCApi"}
PRIVACY_IN_TREE = "ios/IosLibrary/IosLibrary/PrivacyInfo.xcprivacy"
MINIMUM_IOS = "18.0"
# The slices of README D-11 / 7.4: identifier -> (architectures, platform variant).
SLICES = {"ios-arm64": (["arm64"], None), "ios-arm64_x86_64-simulator": (["arm64", "x86_64"], "simulator")}
# LC_BUILD_VERSION's platform per slice; otool prints the number or the name.
PLATFORM = {"ios-arm64": {"2", "IOS"}, "ios-arm64_x86_64-simulator": {"7", "IOSSIMULATOR"}}
# What registers a function to run at exit. On Darwin a thread_local with a destructor brings in
# _tlv_atexit; the others are as on Android (part 1, 5.14).
EXIT_REGISTRARS = {"___cxa_atexit", "_atexit", "___cxa_thread_atexit", "___cxa_thread_atexit_impl", "__tlv_atexit"}
# Every Swift binary imports this: reading none means the imports were not read.
ALWAYS_IMPORTED = "_swift_release"
# The OS's own libraries and frameworks, which every app has.
SYSTEM_DEPENDENCY = re.compile(r"^(/System/Library/Frameworks/[^/]+\.framework/|/usr/lib/swift/lib\w+\.dylib$|/usr/lib/lib[\w.+-]+\.dylib$)")
# Apple's required-reason API categories and how a Swift or C source would use each (Swift API
# design 8.8.1). Comments are stripped first, so only code counts.
REQUIRED_REASON_APIS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": re.compile(
        r"\.creationDate\b|\.modificationDate\b|fileModificationDate|fileCreationDate|contentModificationDate|"
        r"creationDateKey|contentAccessDateKey|NSFileCreationDate|NSFileModificationDate|\bf?getattrlist(bulk|at)?\b|"
        r"\b[fl]?stat(at)?\s*\("),
    "NSPrivacyAccessedAPICategorySystemBootTime": re.compile(r"\bsystemUptime\b|\bmach_absolute_time\b"),
    "NSPrivacyAccessedAPICategoryDiskSpace": re.compile(
        r"volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|\.systemSize\b|NSFileSystemFreeSize|"
        r"NSFileSystemSize|\bf?statv?fs\b"),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": re.compile(r"\bactiveInputModes\b"),
    "NSPrivacyAccessedAPICategoryUserDefaults": re.compile(r"\b(NS)?UserDefaults\b"),
}
# The reasons Apple approves for each category (the required-reason API list), so that a typo or a
# reason of another category is caught.
APPROVED_REASONS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"3EC4.1", "54BD.1"},
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}
USAGE = "usage: check_ios_dist.py [<release> | --dist <folder>] [--root <tree>]"


def version_key(name):
    return [int(part) if part.isdigit() else part for part in re.split(r"[.-]", name)]


def capi_versions(folder):
    """The library versions of the capi xcframeworks in a folder, debug builds aside."""
    prefix = XCFRAMEWORK_NAME[CAPI] + "-"
    return sorted(path.name[len(prefix):-len(".xcframework")] for path in folder.glob(f"{prefix}*.xcframework")
                  if not path.name.endswith("-debug.xcframework"))


def default_release(root):
    found = [path.name for path in (root / "dist").glob("*") if capi_versions(path / "ios")]
    return max(found, key=version_key) if found else None


def run(*command):
    """(return code, stdout, stderr); a missing tool is return code 127."""
    try:
        finished = subprocess.run(list(command), capture_output=True, text=True)
    except OSError as error:
        return 127, "", str(error)
    return finished.returncode, finished.stdout, finished.stderr


def framework(dist, module, version, slice_id):
    return dist / f"{XCFRAMEWORK_NAME[module]}-{version}.xcframework" / slice_id / f"{module}.framework"


def binary(dist, module, version, slice_id):
    return framework(dist, module, version, slice_id) / module


def read_plist(path):
    """The plist as a dict, or None."""
    try:
        with open(path, "rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None
    return value if isinstance(value, dict) else None


def tree_functions(root):
    """The functions the tree's public headers declare."""
    return sorted({match for path in (root / HEADERS_IN_TREE).glob("*.h")
                   for match in re.findall(r"NTK_CALL\s*\**\s*(ntk_\w+)\s*\(", path.read_text(encoding="utf-8"))})


def header_version(root):
    """MAJOR.MINOR.PATCH from the tree's Common.h, or None."""
    try:
        text = (root / HEADERS_IN_TREE / "Common.h").read_text(encoding="utf-8")
    except OSError:
        return None
    parts = [re.search(rf"^#define NTK_VERSION_{part}\s+(\d+)\s*$", text, re.M) for part in ("MAJOR", "MINOR", "PATCH")]
    return ".".join(match.group(1) for match in parts) if all(parts) else None


def architectures(path):
    """The architectures of a binary, or an error text."""
    code, out, err = run("lipo", "-archs", str(path))
    if code != 0:
        return f"lipo -archs {path.name} failed: {err.strip()}"
    return sorted(out.split())


def held(path, slice_id):
    """The architectures a binary holds, so that a missing one is reported once, by slices; the
    slice's own when they cannot be read (then the checks that read them fail)."""
    has = architectures(path)
    return SLICES[slice_id][0] if isinstance(has, str) else has


def check_files(dist, version, rep):
    name = "files: both xcframeworks, include/NativeToolkitC/ and no debug capi"
    wanted = [f"{XCFRAMEWORK_NAME[LIBRARY]}-{version}.xcframework", f"{XCFRAMEWORK_NAME[CAPI]}-{version}.xcframework",
              "include/NativeToolkitC"]
    problems = [f"missing in {dist}: {', '.join(item for item in wanted if not (dist / item).exists())}"] \
        if any(not (dist / item).exists() for item in wanted) else []
    debug = sorted(path.name for path in dist.glob(f"{XCFRAMEWORK_NAME[CAPI]}-*-debug.xcframework"))
    if debug:
        problems.append(f"{', '.join(debug)}: the capi ships in Release only (part 1, 5.4)")
    rep.check(not problems, name, "; ".join(problems))


def check_slices(dist, version, rep):
    for module in (LIBRARY, CAPI):
        name = f"slices: {module} has ios-arm64 (arm64) and ios-arm64_x86_64-simulator (arm64, x86_64), built for each platform"
        xcframework = dist / f"{XCFRAMEWORK_NAME[module]}-{version}.xcframework"
        info = read_plist(xcframework / "Info.plist")
        if info is None:
            rep.check(False, name, f"cannot read {xcframework.name}/Info.plist")
            continue
        problems = []
        listed = {}
        for library in info.get("AvailableLibraries", []):
            listed[library.get("LibraryIdentifier")] = (sorted(library.get("SupportedArchitectures", [])),
                                                        library.get("SupportedPlatformVariant"),
                                                        library.get("SupportedPlatform"), library.get("LibraryPath"))
        if sorted(listed) != sorted(SLICES):
            problems.append(f"Info.plist lists {sorted(map(str, listed))}, not {sorted(SLICES)}")
        on_disk = sorted(path.name for path in xcframework.iterdir() if path.is_dir()) if xcframework.is_dir() else []
        if on_disk != sorted(SLICES):
            problems.append(f"the folder holds {on_disk}, not {sorted(SLICES)}")
        for slice_id, (archs, variant) in SLICES.items():
            if slice_id in listed:
                said_archs, said_variant, platform, path = listed[slice_id]
                if (said_archs, said_variant, platform, path) != (archs, variant, "ios", f"{module}.framework"):
                    problems.append(f"Info.plist says {slice_id} is {said_archs} {platform} {said_variant} {path}")
            path = binary(dist, module, version, slice_id)
            has = architectures(path)
            if isinstance(has, str):
                problems.append(has)
                continue
            if has != archs:
                problems.append(f"{slice_id} holds {has}, not {archs}")
            for arch in has:
                platform = build_version(path, arch)
                if isinstance(platform, str):
                    problems.append(platform)
                elif platform[0] not in PLATFORM[slice_id]:
                    problems.append(f"{slice_id} {arch} is built for platform {platform[0]}")
        rep.check(not problems, name, "; ".join(problems))


def build_version(path, arch):
    """(platform, minos) of LC_BUILD_VERSION, or an error text."""
    code, out, err = run("otool", "-arch", arch, "-l", str(path))
    if code != 0:
        return f"otool -l {path.name} ({arch}) failed: {err.strip()}"
    match = re.search(r"cmd LC_BUILD_VERSION\n(?:.*\n)*?\s*platform (\S+)\n(?:.*\n)*?\s*minos (\S+)", out)
    return (match.group(1), match.group(2)) if match else f"{path.name} ({arch}) has no LC_BUILD_VERSION"


def check_capi_symbols(root, dist, version, rep):
    functions = tree_functions(root)
    if not functions:
        rep.check(False, "symbols: the capi exports the functions of the public headers", f"cannot read {HEADERS_IN_TREE}/*.h")
        return
    for slice_id, (archs, _) in SLICES.items():
        symbols = Report()
        check_symbols(str(binary(dist, CAPI, version, slice_id)), None, ",".join(archs), set(functions), symbols)
        for line in symbols.lines:
            line = re.sub(r"symbols: the library exports the _ntk_\* of 8\.2 less what is not implemented yet, and nothing else \(AP-15\)",
                          f"symbols: {slice_id} exports the functions of the public headers and nothing else (AP-15)", line)
            rep.lines.append(line)
        rep.failed = rep.failed or symbols.failed


def check_swift(dist, version, rep):
    name = "swift: the capi ships no Swift module, interface or -Swift.h, and Headers/ holds NativeToolkitC/ only (D-10, D-11)"
    problems = []
    for slice_id in SLICES:
        root = framework(dist, CAPI, version, slice_id)
        if not root.is_dir():
            problems.append(f"cannot read {slice_id}/{CAPI}.framework")
            continue
        headers = root / "Headers"
        held_headers = sorted(path.name for path in headers.iterdir()) if headers.is_dir() else []
        if held_headers != ["NativeToolkitC"]:
            problems.append(f"{slice_id} Headers/ holds {held_headers}, not only NativeToolkitC/")
        swift_headers = sorted(str(path.relative_to(root)) for path in root.rglob("*-Swift.h"))
        if swift_headers:
            problems.append(f"{slice_id} has {', '.join(swift_headers)}")
        modules = root / "Modules"
        listed = sorted(path.name for path in modules.iterdir()) if modules.is_dir() else []
        if listed != ["module.modulemap"]:
            problems.append(f"{slice_id} Modules/ holds {listed}, not only module.modulemap")
        swift_files = sorted(str(path.relative_to(root)) for path in root.rglob("*")
                             if path.suffix in (".swiftmodule", ".swiftinterface", ".swiftdoc", ".abi.json", ".swiftsourceinfo"))
        if swift_files:
            problems.append(f"{slice_id} has {', '.join(swift_files)}")
    rep.check(not problems, name, "; ".join(problems))

    name = "swift: IosLibrary ships its swiftinterface for every architecture"
    problems = []
    for slice_id, (archs, variant) in SLICES.items():
        module = framework(dist, LIBRARY, version, slice_id) / "Modules" / f"{LIBRARY}.swiftmodule"
        for arch in archs:
            interface = module / f"{arch}-apple-ios{'-' + variant if variant else ''}.swiftinterface"
            if not interface.is_file():
                problems.append(f"{slice_id} has no {interface.name}")
    rep.check(not problems, name, "; ".join(problems))


def check_modules(root, dist, version, rep):
    name = "modules: the capi's Modules/module.modulemap is the tree's"
    try:
        tree = (root / MODULE_MAP_IN_TREE).read_bytes()
    except OSError:
        rep.check(False, name, f"cannot read {MODULE_MAP_IN_TREE}")
        return
    problems = []
    for slice_id in SLICES:
        path = framework(dist, CAPI, version, slice_id) / "Modules" / "module.modulemap"
        if not path.is_file():
            problems.append(f"{slice_id} has no Modules/module.modulemap")
        elif path.read_bytes() != tree:
            problems.append(f"{slice_id} differs from the tree")
    rep.check(not problems, name, "; ".join(problems))


def dependencies(path, arch):
    """(id, [libraries]) from otool -D and -L, or an error text."""
    code, out, err = run("otool", "-arch", arch, "-L", str(path))
    if code != 0:
        return f"otool -L {path.name} ({arch}) failed: {err.strip()}"
    code, own, err = run("otool", "-arch", arch, "-D", str(path))
    if code != 0:
        return f"otool -D {path.name} ({arch}) failed: {err.strip()}"
    own_lines = [line.strip() for line in own.splitlines()[1:] if line.strip()]
    identity = own_lines[0] if len(own_lines) == 1 else None
    libraries = [line.strip().split(" (compatibility")[0] for line in out.splitlines()[1:] if line.strip()]
    # otool -L lists the binary's own id first.
    if identity is not None and libraries and libraries[0] == identity:
        libraries = libraries[1:]
    return identity, libraries


def check_dependencies(dist, version, rep):
    for module in (LIBRARY, CAPI):
        if module == CAPI:
            name = "dependencies: the capi needs @rpath/IosLibrary.framework, the OS and /usr/lib/swift/ only"
        else:
            name = "dependencies: IosLibrary needs the OS and /usr/lib/swift/ only"
        problems = []
        for slice_id in SLICES:
            path = binary(dist, module, version, slice_id)
            for arch in held(path, slice_id):
                found = dependencies(path, arch)
                if isinstance(found, str):
                    problems.append(found)
                    continue
                _, libraries = found
                if not libraries:
                    problems.append(f"{slice_id} {arch}: no dependency was read")
                    continue
                allowed = {"@rpath/IosLibrary.framework/IosLibrary"} if module == CAPI else set()
                other = [library for library in libraries if library not in allowed and not SYSTEM_DEPENDENCY.match(library)]
                if other:
                    problems.append(f"{slice_id} {arch} needs {', '.join(other)}")
                if module == CAPI and "@rpath/IosLibrary.framework/IosLibrary" not in libraries:
                    problems.append(f"{slice_id} {arch} does not need @rpath/IosLibrary.framework/IosLibrary")
        rep.check(not problems, name, "; ".join(problems))


def imports(path, arch):
    """The undefined symbols, or an error text."""
    code, out, err = run("nm", "-arch", arch, "-u", str(path))
    if code != 0:
        return f"nm -u {path.name} ({arch}) failed: {err.strip()}"
    names = {line.strip() for line in out.splitlines() if line.strip()}
    return names if ALWAYS_IMPORTED in names else f"{path.name} ({arch}): no {ALWAYS_IMPORTED} among the imports read: they were not read"


def check_exit(dist, version, rep):
    name = "exit: neither framework imports __cxa_atexit, atexit, __cxa_thread_atexit or _tlv_atexit (part 1, 5.14)"
    problems = []
    for module in (LIBRARY, CAPI):
        for slice_id in SLICES:
            path = binary(dist, module, version, slice_id)
            for arch in held(path, slice_id):
                found = imports(path, arch)
                if isinstance(found, str):
                    problems.append(found)
                elif EXIT_REGISTRARS & found:
                    problems.append(f"{module} {slice_id} {arch} imports {', '.join(sorted(EXIT_REGISTRARS & found))}")
    rep.check(not problems, name, "; ".join(problems))


def check_install(dist, version, rep):
    name = "install: LC_ID_DYLIB is @rpath/<name>.framework/<name>"
    problems = []
    for module in (LIBRARY, CAPI):
        for slice_id in SLICES:
            path = binary(dist, module, version, slice_id)
            for arch in held(path, slice_id):
                found = dependencies(path, arch)
                if isinstance(found, str):
                    problems.append(found)
                elif found[0] != f"@rpath/{module}.framework/{module}":
                    problems.append(f"{module} {slice_id} {arch} is {found[0]}")
    rep.check(not problems, name, "; ".join(problems))


def check_version(root, dist, version, rep):
    name = (f"version: {version} in both (P1-19) and in Common.h, minimum iOS {MINIMUM_IOS} (D-15), "
            "the bundle ids of D-12")
    problems = []
    declared = header_version(root)
    if declared != version:
        problems.append(f"the tree's Common.h says {declared}, the xcframework's name {version}")
    for module in (LIBRARY, CAPI):
        for slice_id in SLICES:
            info = read_plist(framework(dist, module, version, slice_id) / "Info.plist")
            if info is None:
                problems.append(f"cannot read {module} {slice_id} Info.plist")
                continue
            expected = {"CFBundleShortVersionString": version, "MinimumOSVersion": MINIMUM_IOS,
                        "CFBundleIdentifier": BUNDLE_ID[module], "CFBundleExecutable": module}
            for key, value in expected.items():
                if info.get(key) != value:
                    problems.append(f"{module} {slice_id} has {key} = {info.get(key)}, not {value}")
            path = binary(dist, module, version, slice_id)
            for arch in held(path, slice_id):
                found = build_version(path, arch)
                if isinstance(found, str):
                    problems.append(found)
                elif found[1] != MINIMUM_IOS:
                    problems.append(f"{module} {slice_id} {arch} has minos {found[1]}")
    rep.check(not problems, name, "; ".join(problems))


def code_only(text):
    """The text with comments and the contents of string and character literals blanked (newlines
    kept), so that only code is searched. Swift's nested block comments, multi-line strings and the
    code of string interpolation are read as code would be; C character literals are skipped."""
    out, i, n = [], 0, len(text)
    # Each entry: "code"; a string as (multi-line, number of #: Swift's raw strings #"..."#, whose
    # escapes and interpolations take the same #s); or an int, the parenthesis depth of an interpolation.
    stack = ["code"]

    def blank(fragment):
        out.append("".join("\n" if ch == "\n" else " " for ch in fragment))

    while i < n:
        mode = stack[-1]
        if isinstance(mode, tuple):
            multiline, hashes = mode
            close = ('"""' if multiline else '"') + "#" * hashes
            escape = "\\" + "#" * hashes
            if text.startswith(escape + "(", i):
                blank(escape + "(")
                stack.append(1)
                i += len(escape) + 1
            elif text.startswith(escape, i):
                blank(text[i:i + len(escape) + 1])
                i += len(escape) + 1
            elif text.startswith(close, i):
                blank(close)
                stack.pop()
                i += len(close)
            elif not multiline and text[i] == "\n":
                blank(text[i])
                stack.pop()
                i += 1
            else:
                blank(text[i])
                i += 1
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            blank(text[i:end])
            i = end
        elif text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(text[i:j])
            i = j
        elif text[i] in '#"':
            j = i
            while j < n and text[j] == "#":
                j += 1
            if j < n and text[j] == '"':
                multiline = text.startswith('"""', j)
                opening = text[i:j] + ('"""' if multiline else '"')
                blank(opening)
                stack.append((multiline, j - i))
                i += len(opening)
            else:
                # A # that opens no string (#if, #include, #selector) is code.
                out.append(text[i:j])
                i = j
        elif text[i] == "'":
            j = i + 1
            while j < n and text[j] not in "'\n":
                j += 2 if text[j] == "\\" else 1
            blank(text[i:j + 1])
            i = j + 1
        else:
            if isinstance(mode, int):
                if text[i] == "(":
                    stack[-1] += 1
                elif text[i] == ")":
                    stack[-1] -= 1
                    if stack[-1] == 0:
                        stack.pop()
                        blank(")")
                        i += 1
                        continue
            out.append(text[i])
            i += 1
    return "".join(out)


def used_categories(folder):
    """{category: [files]} of the required-reason APIs the sources use, or None when there are none to read."""
    sources = sorted(path for path in folder.rglob("*") if path.suffix in (".swift", ".c", ".m", ".h", ".mm"))
    if not sources:
        return None
    used = {}
    for path in sources:
        code = code_only(path.read_text(encoding="utf-8"))
        for category, pattern in REQUIRED_REASON_APIS.items():
            if pattern.search(code):
                used.setdefault(category, []).append(path.name)
    return used


def declared_categories(manifest):
    """({category: [reasons]}, problems) of a privacy manifest."""
    problems = []
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append("NSPrivacyTracking is not false")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        problems.append("NSPrivacyTrackingDomains is not empty")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        problems.append("NSPrivacyCollectedDataTypes is not empty")
    declared = {}
    entries = manifest.get("NSPrivacyAccessedAPITypes", [])
    if not isinstance(entries, list):
        return declared, problems + ["NSPrivacyAccessedAPITypes is not an array"]
    for entry in entries:
        if not isinstance(entry, dict):
            problems.append("an entry of NSPrivacyAccessedAPITypes is not a dictionary")
            continue
        category = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons")
        if not isinstance(category, str) or category not in APPROVED_REASONS:
            problems.append(f"{category!r} is not a category of the required-reason APIs")
            continue
        if category in declared:
            problems.append(f"{category} is declared twice")
        if not isinstance(reasons, list) or not all(isinstance(reason, str) for reason in reasons):
            problems.append(f"{category}'s reasons are not an array of strings")
            reasons = []
        elif not reasons:
            problems.append(f"{category} has no reason")
        unknown = sorted(set(reasons) - APPROVED_REASONS[category])
        if unknown:
            problems.append(f"{category} gives {', '.join(unknown)}, not a reason Apple approves for it")
        declared[category] = reasons
    return declared, problems


def check_privacy(root, dist, version, rep):
    name = "privacy: IosLibrary's PrivacyInfo.xcprivacy is in both slices, lints, is the tree's and declares what the sources use"
    problems = []
    try:
        tree = (root / PRIVACY_IN_TREE).read_bytes()
    except OSError:
        tree = None
        problems.append(f"cannot read {PRIVACY_IN_TREE}")
    used = used_categories(root / SOURCES[LIBRARY])
    if used is None:
        problems.append(f"cannot read the sources in {SOURCES[LIBRARY]}")
    for slice_id in SLICES:
        path = framework(dist, LIBRARY, version, slice_id) / "PrivacyInfo.xcprivacy"
        if not path.is_file():
            problems.append(f"{slice_id} has no PrivacyInfo.xcprivacy")
            continue
        code, out, err = run("plutil", "-lint", str(path))
        if code != 0:
            problems.append(f"{slice_id}: plutil -lint: {(out + err).strip()}")
            continue
        if tree is not None and path.read_bytes() != tree:
            problems.append(f"{slice_id} differs from {PRIVACY_IN_TREE}")
        manifest = read_plist(path)
        if manifest is None:
            problems.append(f"cannot read {slice_id} PrivacyInfo.xcprivacy")
            continue
        declared, found = declared_categories(manifest)
        problems += [f"{slice_id}: {problem}" for problem in found]
        if used is not None and sorted(declared) != sorted(used):
            problems.append(f"{slice_id} declares {sorted(declared)}, the sources use {sorted(used)} "
                            f"({'; '.join(category + ': ' + ', '.join(files) for category, files in sorted(used.items()))})")
    rep.check(not problems, name, "; ".join(problems))

    name = "privacy: the capi declares the required-reason APIs its sources use (none: no manifest)"
    problems = []
    used = used_categories(root / SOURCES[CAPI])
    if used is None:
        problems.append(f"cannot read the sources in {SOURCES[CAPI]}")
    for slice_id in SLICES:
        path = framework(dist, CAPI, version, slice_id) / "PrivacyInfo.xcprivacy"
        if used is None:
            break
        if not path.exists():
            if used:
                problems.append(f"{slice_id} has no PrivacyInfo.xcprivacy and the sources use {sorted(used)}")
            continue
        manifest = read_plist(path)
        if manifest is None:
            problems.append(f"cannot read {slice_id} PrivacyInfo.xcprivacy")
            continue
        declared, found = declared_categories(manifest)
        problems += [f"{slice_id}: {problem}" for problem in found]
        if sorted(declared) != sorted(used):
            problems.append(f"{slice_id} declares {sorted(declared)}, the sources use {sorted(used)}")
    rep.check(not problems, name, "; ".join(problems))


def signature_problems(text, simulator):
    """What codesign -dv says that D-18 (A) does not allow, for one architecture."""
    if "code object is not signed at all" in text:
        return []
    if not simulator:
        return ["is signed"]
    problems = []
    flags = re.search(r"^CodeDirectory .*flags=0x[0-9a-f]+\(([^)]*)\)", text, re.M)
    if flags is None or "linker-signed" not in flags.group(1).split(","):
        problems.append("is signed, and not by the linker")
    if not re.search(r"^Signature=adhoc$", text, re.M):
        problems.append("has a signature that is not ad hoc")
    if re.search(r"^Authority=", text, re.M):
        problems.append("names an Authority")
    team = re.search(r"^TeamIdentifier=(.*)$", text, re.M)
    if team is not None and team.group(1).strip() != "not set":
        problems.append("names a TeamIdentifier")
    return problems


def check_signature(dist, version, rep):
    name = "signature: ios-arm64 is not signed; the simulator slices carry the linker's ad-hoc signature at most (D-18)"
    problems = []
    for module in (LIBRARY, CAPI):
        for slice_id, (_, variant) in SLICES.items():
            root = framework(dist, module, version, slice_id)
            if not root.is_dir():
                problems.append(f"cannot read {module} {slice_id}")
                continue
            if (root / "_CodeSignature").exists():
                problems.append(f"{module} {slice_id} has _CodeSignature/")
            for arch in held(root / module, slice_id):
                code, out, err = run("codesign", "-dv", "--verbose=4", "--arch", arch, str(root))
                text = out + err
                if code != 0 and "not signed at all" not in text:
                    problems.append(f"{module} {slice_id} {arch}: codesign -dv failed: {text.strip()}")
                    continue
                problems += [f"{module} {slice_id} {arch} {problem}" for problem in signature_problems(text, variant == "simulator")]
    rep.check(not problems, name, "; ".join(problems))


def folder_contents(folder):
    """{relative path: bytes} of every file under a folder, and {relative path + "/": None} of every
    folder, so that a subfolder only one side has is a difference too. Empty when it is not a folder."""
    if not folder.is_dir():
        return {}
    # Finder's .DS_Store is not content: one in the tree or in a copy would fail a right distributable.
    return {str(path.relative_to(folder)) + ("/" if path.is_dir() else ""): None if path.is_dir() else path.read_bytes()
            for path in sorted(folder.rglob("*")) if path.name != ".DS_Store"}


def check_headers(root, dist, version, rep):
    name = "headers: include/NativeToolkitC/, the capi's Headers/NativeToolkitC/ and the tree are the same"
    tree = folder_contents(root / HEADERS_IN_TREE)
    if not any(name.endswith(".h") for name in tree):
        rep.check(False, name, f"cannot read {HEADERS_IN_TREE}/*.h")
        return
    copies = {"include/": dist / "include" / "NativeToolkitC"}
    for slice_id in SLICES:
        copies[f"{slice_id} Headers/"] = framework(dist, CAPI, version, slice_id) / "Headers" / "NativeToolkitC"
    problems = []
    for label, folder in copies.items():
        copy = folder_contents(folder)
        if sorted(copy) != sorted(tree):
            problems.append(f"{label} has {sorted(copy)}, the tree {sorted(tree)}")
        else:
            changed = [header for header in tree if copy[header] != tree[header]]
            if changed:
                problems.append(f"{label} differs from the tree in {', '.join(changed)}")
    rep.check(not problems, name, "; ".join(problems))


def parse_arguments(argv):
    with_value = {"--root", "--dist"}
    parsed, rest, positional = {}, list(argv), []
    while rest:
        argument = rest.pop(0)
        if argument in with_value:
            if argument in parsed or not rest or rest[0].startswith("--"):
                return None
            parsed[argument] = rest.pop(0)
        elif argument.startswith("--"):
            return None
        else:
            positional.append(argument)
    if len(positional) > 1 or (positional and "--dist" in parsed):
        return None
    parsed["release"] = positional[0] if positional else None
    return parsed


def main(argv):
    parsed = parse_arguments(argv)
    if parsed is None:
        print(USAGE, file=sys.stderr)
        return 2
    root = Path(parsed.get("--root") or ROOT).resolve()
    if "--dist" in parsed:
        dist = Path(parsed["--dist"]).resolve()
        label = str(dist)
    else:
        release = parsed["release"] or default_release(root)
        if release is None:
            print(f"no dist/<release>/ios/{XCFRAMEWORK_NAME[CAPI]}-<version>.xcframework under {root}", file=sys.stderr)
            return 1
        dist = root / "dist" / release / "ios"
        label = release
    # The library version differs from the release when only some OSes change; it is read from the
    # capi xcframework's name.
    versions = capi_versions(dist)
    version = versions[0] if len(versions) == 1 else "?"
    rep = Report(f"iOS distribution {label} (library {version})")
    rep.check(len(versions) == 1, f"files: one {XCFRAMEWORK_NAME[CAPI]}-<version>.xcframework tells the library version",
              f"found {versions} in {dist}")
    check_files(dist, version, rep)
    check_slices(dist, version, rep)
    check_capi_symbols(root, dist, version, rep)
    check_swift(dist, version, rep)
    check_modules(root, dist, version, rep)
    check_dependencies(dist, version, rep)
    check_exit(dist, version, rep)
    check_install(dist, version, rep)
    check_version(root, dist, version, rep)
    check_privacy(root, dist, version, rep)
    check_signature(dist, version, rep)
    check_headers(root, dist, version, rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
