#!/usr/bin/env python3
"""Check dist/<release>/android/ against the Android C ABI's distribution rules.

The rules come from the C ABI design (part 1 chapter 6 "配布物の名前", part 2
15.2) and README chapter 9 of artifact/topics/android-c-abi/:

  files     one android-native-toolkit-capi-<version>.aar, whose name gives the
            library version (it differs from the release when only some OSes
            change: dist/1.13.0/android/ holds 2.0.0), both AARs at that
            version, the C headers in include/NativeToolkitC/, and m2/
  headers   include/, the capi AAR's Prefab headers and the tree's headers are
            byte for byte the same
  prefab    the package and module are "ntk" at the library version; every
            ABI says "stl": "none" and API 31; the ABIs are arm64-v8a and x86_64
  native    jni/ has libntk.so for arm64-v8a and x86_64 and no other .so (README
            D-10); per ABI: jni/ and Prefab hold the same libntk.so (AGP strips the
            jni/ copy and keeps Prefab's for linking and debugging, so they are
            compared stripped), every LOAD segment of both is aligned to 16 KB,
            libc++_shared.so is not needed, nothing is registered to run at
            exit (no __cxa_atexit, atexit or __cxa_thread_atexit(_impl) import,
            read from an import list that has __cxa_finalize: a static or
            thread_local with a destructor would be torn down under threads
            still calling the library, design part 1, 5.5), and the exports are
            the headers' functions and JNI_OnLoad only (AP-15)
  m2        the POMs carry io.github.kimjh4941:android-native-toolkit(-capi) at
            the library version (README D-17), the AARs there are the ones in
            dist/, the capi POM depends on android-native-toolkit at the same
            version, and kotlin-stdlib is there, at the consumer version of
            gradle/libs.versions.toml (kotlinConsumer: Kotlin 2.1 and 2.2 users),
            in the POM and in every variant of the Gradle Module Metadata that
            publishes the AAR (with or without dependencies), which Gradle reads
            in preference to the POM. Every other Kotlin core library there is
            at that version too
  manual    the dependency list that manual/<release>/index.md, index.ja.md and
            index.ko.md tell AAR users to add (the code block right before the
            <!-- ntk-android-dependencies --> marker) is what the runtime variants
            of the Module Metadata need, the toolkit's own artifacts aside

A file that cannot be read fails its check: a check that skips because its
subject is missing reports agreement it never checked.

Usage:
    python3 scripts/check_android_dist.py [<release>] [--root <tree>] [--readelf <path>] [--nm <path>] [--strip <path>]

<release> is a folder under dist/ (default: the highest one with an
android/android-native-toolkit-capi-<version>.aar). --root aims every path at
another copy of the repository (the self-test). --readelf, --nm and --strip
name the NDK tools; by default they are found as check_c_abi_contract_android.py
finds them.

Exit status is 1 when any check fails.
"""

import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from c_abi_contract_common import Report  # noqa: E402
from check_c_abi_contract_android import check_symbols, find_ndk_tool  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

GROUP = "io.github.kimjh4941"
KOTLIN_ARTIFACT = "android-native-toolkit"
CAPI_ARTIFACT = "android-native-toolkit-capi"
HEADERS_IN_TREE = "android/android_library_capi/src/main/cpp/include/NativeToolkitC"
VERSIONS = "android/gradle/libs.versions.toml"
ABIS = ["arm64-v8a", "x86_64"]
PAGE = 0x4000
# What registers a function to run at exit; a static with a destructor brings in __cxa_atexit, a
# thread_local with one __cxa_thread_atexit(_impl), which exit runs for the calling thread.
EXIT_REGISTRARS = {"__cxa_atexit", "atexit", "__cxa_thread_atexit", "__cxa_thread_atexit_impl"}
# Every shared library imports this (crtbegin's dlclose hook): reading none means the import list
# was not read.
ALWAYS_IMPORTED = "__cxa_finalize"
POM_NS = {"m": "http://maven.apache.org/POM/4.0.0"}
USAGE = "usage: check_android_dist.py [<release>] [--root <tree>] [--readelf <path>] [--nm <path>] [--strip <path>]"


def version_key(name):
    return [int(part) if part.isdigit() else part for part in re.split(r"[.-]", name)]


def capi_versions(dist):
    """The library versions of the C ABI AARs in dist/<release>/android/ (debug builds aside)."""
    return sorted(path.name[len(CAPI_ARTIFACT) + 1:-len(".aar")] for path in dist.glob(f"{CAPI_ARTIFACT}-*.aar")
                  if not path.name.endswith("-debug.aar"))


def default_release(root):
    found = [path.name for path in (root / "dist").glob("*") if capi_versions(path / "android")]
    return max(found, key=version_key) if found else None


def zip_entries(path):
    """{name: bytes} of an archive, or None when it cannot be read."""
    try:
        with zipfile.ZipFile(path) as archive:
            return {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}
    except (OSError, zipfile.BadZipFile):
        return None


def check_files(dist, release, rep):
    name = "files: both AARs, include/NativeToolkitC/ and m2/"
    wanted = [f"{KOTLIN_ARTIFACT}-{release}.aar", f"{CAPI_ARTIFACT}-{release}.aar", "include/NativeToolkitC", "m2"]
    missing = [item for item in wanted if not (dist / item).exists()]
    rep.check(not missing, name, f"missing in {dist}: {', '.join(missing)}")


def check_headers(root, dist, capi, rep):
    name = "headers: include/, the capi AAR's Prefab and the tree are the same"
    tree = {path.name: path.read_bytes() for path in sorted((root / HEADERS_IN_TREE).glob("*.h"))}
    if not tree:
        rep.check(False, name, f"cannot read {HEADERS_IN_TREE}/*.h")
        return
    shipped = {path.name: path.read_bytes() for path in sorted((dist / "include/NativeToolkitC").glob("*.h"))}
    prefab_dir = "prefab/modules/ntk/include/NativeToolkitC/"
    prefab = {} if capi is None else {key[len(prefab_dir):]: value for key, value in capi.items()
                                      if key.startswith(prefab_dir)}
    problems = []
    for label, copy in (("include/", shipped), ("the AAR's Prefab", prefab)):
        if set(copy) != set(tree):
            problems.append(f"{label} has {sorted(copy)}, the tree {sorted(tree)}")
        else:
            changed = [header for header in tree if copy[header] != tree[header]]
            if changed:
                problems.append(f"{label} differs from the tree in {', '.join(changed)}")
    rep.check(not problems, name, "; ".join(problems))


def check_prefab(capi, release, rep):
    name = 'prefab: package and module "ntk", "stl": "none" and API 31 per ABI'
    if capi is None:
        rep.check(False, name, "cannot read the capi AAR")
        return
    problems = []
    try:
        package = json.loads(capi["prefab/prefab.json"])
        if package.get("name") != "ntk":
            problems.append(f'the package is "{package.get("name")}", not "ntk"')
        if package.get("version") != release:
            problems.append(f'the package version is {package.get("version")}, not {release}')
        if "prefab/modules/ntk/module.json" not in capi:
            problems.append('there is no module "ntk"')
        abis = sorted(key.split("/")[4][len("android."):] for key in capi
                      if re.fullmatch(r"prefab/modules/ntk/libs/android\.[^/]+/abi\.json", key))
        if abis != sorted(ABIS):
            problems.append(f"the ABIs are {abis}, not {ABIS}")
        for abi in abis:
            info = json.loads(capi[f"prefab/modules/ntk/libs/android.{abi}/abi.json"])
            if info.get("stl") != "none":
                problems.append(f'{abi} says "stl": "{info.get("stl")}"')
            if info.get("api") != 31:
                problems.append(f"{abi} says API {info.get('api')}")
    except (KeyError, ValueError) as error:
        problems.append(f"cannot read the Prefab metadata: {error}")
    rep.check(not problems, name, "; ".join(problems))


def load_alignments(readelf, library):
    """The alignments of the LOAD segments, or an error text."""
    finished = subprocess.run([readelf, "-lW", str(library)], capture_output=True, text=True)
    if finished.returncode != 0:
        return f"{readelf} failed: {finished.stderr.strip()}"
    return [int(line.split()[-1], 16) for line in finished.stdout.splitlines() if line.strip().startswith("LOAD")]


def needed(readelf, library):
    """The libraries the library needs, or an error text. libc.so is always among them, so none
    means the dynamic section was not read."""
    finished = subprocess.run([readelf, "-dW", str(library)], capture_output=True, text=True)
    if finished.returncode != 0:
        return f"{readelf} -dW failed: {finished.stderr.strip()}"
    libraries = re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", finished.stdout)
    return libraries if "libc.so" in libraries else "no libc.so among the needed libraries read: they were not read"


def imports(readelf, library):
    """The names of the undefined dynamic symbols, without their versions, or an error text."""
    finished = subprocess.run([readelf, "--dyn-syms", "-W", str(library)], capture_output=True, text=True)
    if finished.returncode != 0:
        return f"{readelf} --dyn-syms failed: {finished.stderr.strip()}"
    names = {line.split()[7].split("@")[0] for line in finished.stdout.splitlines()
             if len(line.split()) >= 8 and line.split()[6] == "UND"}
    return names if ALWAYS_IMPORTED in names else f"no {ALWAYS_IMPORTED} among the imports read: they were not read"


def stripped(strip, data, folder, label):
    """The bytes of a copy stripped of what linking at run time does not need, or None."""
    source = Path(folder) / f"{label}.so"
    target = Path(folder) / f"{label}.stripped.so"
    source.write_bytes(data)
    finished = subprocess.run([strip, "--strip-unneeded", "-o", str(target), str(source)], capture_output=True)
    return target.read_bytes() if finished.returncode == 0 and target.exists() else None


def check_native(root, capi, readelf_given, nm_given, strip_given, rep):
    if capi is None:
        rep.check(False, "native: libntk.so of every ABI", "cannot read the capi AAR")
        return
    jni_abis = sorted({key.split("/")[1] for key in capi if re.fullmatch(r"jni/[^/]+/[^/]+\.so", key)})
    libraries = sorted(key for key in capi if re.fullmatch(r"jni/[^/]+/[^/]+\.so", key))
    rep.check(jni_abis == sorted(ABIS) and libraries == [f"jni/{abi}/libntk.so" for abi in sorted(ABIS)],
              "native: jni/ has libntk.so for arm64-v8a and x86_64 only", f"jni/ has {libraries}")
    readelf = find_ndk_tool("llvm-readelf", readelf_given)
    strip = find_ndk_tool("llvm-strip", strip_given)
    listed = sorted({match for path in (root / HEADERS_IN_TREE).glob("*.h")
                     for match in re.findall(r"NTK_CALL\s*\**\s*(ntk_\w+)\s*\(", path.read_text(encoding="utf-8"))})
    with tempfile.TemporaryDirectory() as folder:
        for abi in ABIS:
            name = f"native: {abi} libntk.so (one copy, 16 KB pages, no libc++_shared, nothing run at exit)"
            jni = capi.get(f"jni/{abi}/libntk.so")
            prefab = capi.get(f"prefab/modules/ntk/libs/android.{abi}/libntk.so")
            if jni is None or prefab is None:
                rep.check(False, name, "libntk.so is missing in jni/ or in Prefab")
                continue
            library = Path(folder) / f"{abi}-libntk.so"
            library.write_bytes(jni)
            unstripped = Path(folder) / f"{abi}-prefab-libntk.so"
            unstripped.write_bytes(prefab)
            problems = []
            if strip is None or not Path(strip).exists():
                problems.append("no llvm-strip (give --strip or set ANDROID_NDK_HOME)")
            else:
                ours = stripped(strip, jni, folder, f"{abi}-jni")
                theirs = stripped(strip, prefab, folder, f"{abi}-prefab")
                if ours is None or theirs is None or ours != theirs:
                    problems.append("jni/ and Prefab hold different libraries (compared stripped)")
            if readelf is None or not Path(readelf).exists():
                problems.append("no llvm-readelf (give --readelf or set ANDROID_NDK_HOME)")
            else:
                for label, copy in (("jni/", library), ("Prefab", unstripped)):
                    aligned = load_alignments(readelf, copy)
                    if isinstance(aligned, str):
                        problems.append(aligned)
                    elif not aligned or any(value < PAGE for value in aligned):
                        problems.append(f"{label} LOAD alignments {[hex(value) for value in aligned]}, not 0x4000")
                    libraries = needed(readelf, copy)
                    if isinstance(libraries, str):
                        problems.append(libraries)
                    elif "libc++_shared.so" in libraries:
                        problems.append(f"{label} needs libc++_shared.so")
                    imported = imports(readelf, copy)
                    if isinstance(imported, str):
                        problems.append(imported)
                    elif EXIT_REGISTRARS & imported:
                        problems.append(f"{label} imports {sorted(EXIT_REGISTRARS & imported)}: something runs at exit")
            rep.check(not problems, name, "; ".join(problems))
            symbols = Report()
            check_symbols(str(library), nm_given, listed, symbols)
            for line in symbols.lines:
                rep.lines.append(line.replace("  OK   symbols:", f"  OK   native: {abi}").replace(
                    "  FAIL symbols:", f"  FAIL native: {abi}"))
            rep.failed = rep.failed or symbols.failed


def pom(path):
    """(groupId, artifactId, version, [(group, artifact, version)]), or None."""
    try:
        project = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return None

    def text(node, tag):
        found = node.find(f"m:{tag}", POM_NS)
        return None if found is None else found.text

    dependencies = [(text(d, "groupId"), text(d, "artifactId"), text(d, "version"))
                    for d in project.findall("m:dependencies/m:dependency", POM_NS)]
    return text(project, "groupId"), text(project, "artifactId"), text(project, "version"), dependencies


def module_dependencies(path):
    """{variant: [(group, module, version)]} of the variants of a .module file that publish the AAR
    (what a consumer resolves), with or without dependencies, or None when it cannot be read."""
    try:
        metadata = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    found = {}
    for variant in metadata.get("variants", []):
        dependencies = variant.get("dependencies", [])
        if any(str(item.get("name", "")).endswith(".aar") for item in variant.get("files", [])):
            found[variant.get("name")] = [
                (d.get("group"), d.get("module"), d.get("version", {}).get("requires") or d.get("version", {}).get("strictly"))
                for d in dependencies]
    return found


MANUAL_MARKER = "<!-- ntk-android-dependencies"
MANUAL_DEPENDENCY = re.compile(r'implementation\("([^":]+):([^":]+):([^"]+)"\)')


def manual_dependencies(path):
    """{(group, module, version)} of the code block right before the marker in a manual index, or an
    error text."""
    try:
        text = path.read_text(encoding="utf-8-sig")
    except OSError as error:
        return f"cannot read {path}: {error}"
    marker = text.find(MANUAL_MARKER)
    if marker < 0:
        return f"{path.name} has no {MANUAL_MARKER} marker after its dependency list"
    blocks = re.findall(r"```[^\n]*\n(.*?)```", text[:marker], re.S)
    if not blocks:
        return f"{path.name} has no code block before the marker"
    return set(MANUAL_DEPENDENCY.findall(blocks[-1]))


def runtime_dependencies(dist, version):
    """{(group, module, version)} the two AARs need at run time, from the runtime variants of the
    Module Metadata, without the toolkit's own artifacts; or an error text."""
    found = set()
    for artifact in (KOTLIN_ARTIFACT, CAPI_ARTIFACT):
        path = dist / "m2" / GROUP.replace(".", "/") / artifact / version / f"{artifact}-{version}.module"
        try:
            metadata = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return f"cannot read {path}"
        for variant in metadata.get("variants", []):
            if variant.get("attributes", {}).get("org.gradle.usage") != "java-runtime":
                continue
            for d in variant.get("dependencies", []):
                if d.get("group") != GROUP:
                    found.add((d.get("group"), d.get("module"),
                               d.get("version", {}).get("requires") or d.get("version", {}).get("strictly")))
    return found


def check_manual(root, dist, release, version, rep):
    """The dependency list the manual tells AAR users to add (Option B of the index) is what the AARs
    need at run time, in every language (README D-17)."""
    name = f"manual: the dependency list in manual/{release}/index*.md matches the Module Metadata"
    expected = runtime_dependencies(dist, version)
    if isinstance(expected, str):
        rep.check(False, name, expected)
        return
    problems = []
    for language in ("index.md", "index.ja.md", "index.ko.md"):
        listed = manual_dependencies(root / "manual" / release / language)
        if isinstance(listed, str):
            problems.append(listed)
            continue
        missing = sorted(f"{g}:{m}:{v}" for g, m, v in expected - listed)
        extra = sorted(f"{g}:{m}:{v}" for g, m, v in listed - expected)
        if missing:
            problems.append(f"{language} lacks {missing}")
        if extra:
            problems.append(f"{language} lists {extra}, which the AARs do not need")
    rep.check(not problems, name, "; ".join(problems))


def consumer_kotlin(root):
    match = re.search(r'^kotlinConsumer\s*=\s*"([^"]+)"', (root / VERSIONS).read_text(encoding="utf-8"), re.M)
    return match.group(1) if match else None


def check_m2(root, dist, release, rep):
    kotlin = consumer_kotlin(root)
    for artifact in (KOTLIN_ARTIFACT, CAPI_ARTIFACT):
        name = f"m2: {GROUP}:{artifact}:{release}"
        folder = dist / "m2" / GROUP.replace(".", "/") / artifact / release
        found = pom(folder / f"{artifact}-{release}.pom")
        if found is None:
            rep.check(False, name, f"cannot read the POM in {folder}")
            continue
        group, artifact_id, version, dependencies = found
        problems = []
        if (group, artifact_id, version) != (GROUP, artifact, release):
            problems.append(f"the POM says {group}:{artifact_id}:{version}")
        published = folder / f"{artifact}-{release}.aar"
        local = dist / f"{artifact}-{release}.aar"
        if not published.exists() or not local.exists() or published.read_bytes() != local.read_bytes():
            problems.append("the AAR in m2/ is not the one in dist/")
        if kotlin is None:
            problems.append(f"no kotlinConsumer in {VERSIONS}")
        if not any(g == "org.jetbrains.kotlin" and a == "kotlin-stdlib" for g, a, _ in dependencies):
            problems.append("the POM has no kotlin-stdlib")
        for dep_group, dep_artifact, dep_version in dependencies:
            if dep_group == "org.jetbrains.kotlin" and dep_version != kotlin:
                problems.append(f"the POM's {dep_artifact} is {dep_version}, not {kotlin}")
        in_module = module_dependencies(folder / f"{artifact}-{release}.module")
        if in_module is None:
            problems.append("cannot read the Gradle Module Metadata")
        elif not in_module:
            problems.append("the Gradle Module Metadata has no variant that publishes the AAR")
        else:
            for variant, listed in sorted(in_module.items()):
                if not any(g == "org.jetbrains.kotlin" and m == "kotlin-stdlib" for g, m, _ in listed):
                    problems.append(f"the metadata has no kotlin-stdlib in {variant}")
                for group, module, version in listed:
                    if group == "org.jetbrains.kotlin" and version != kotlin:
                        problems.append(f"the metadata's {module} is {version} in {variant}, not {kotlin}")
        if artifact == CAPI_ARTIFACT and (GROUP, KOTLIN_ARTIFACT, release) not in dependencies:
            problems.append(f"it does not depend on {GROUP}:{KOTLIN_ARTIFACT}:{release}")
        rep.check(not problems, name, "; ".join(problems))


def parse_arguments(argv):
    with_value = {"--root", "--readelf", "--nm", "--strip"}
    parsed, rest, positional = {}, list(argv), []
    while rest:
        argument = rest.pop(0)
        if argument in with_value:
            if not rest or rest[0].startswith("--"):
                return None
            parsed[argument] = rest.pop(0)
        elif argument.startswith("--"):
            return None
        else:
            positional.append(argument)
    if len(positional) > 1:
        return None
    parsed["release"] = positional[0] if positional else None
    return parsed


def main(argv):
    parsed = parse_arguments(argv)
    if parsed is None:
        print(USAGE, file=sys.stderr)
        return 2
    root = Path(parsed.get("--root") or ROOT)
    release = parsed["release"] or default_release(root)
    if release is None:
        print(f"no dist/<release>/android/{CAPI_ARTIFACT}-<release>.aar under {root}", file=sys.stderr)
        return 1
    dist = root / "dist" / release / "android"
    # The library version differs from the release when only some OSes change: dist/1.13.0/android/
    # holds the 2.0.0 AARs. It is read from the C ABI AAR's file name.
    versions = capi_versions(dist)
    version = versions[0] if len(versions) == 1 else release
    rep = Report(f"Android distribution {release} (library {version})")
    rep.check(len(versions) == 1, f"files: one {CAPI_ARTIFACT}-<version>.aar tells the library version",
              f"found {versions}")
    check_files(dist, version, rep)
    capi = zip_entries(dist / f"{CAPI_ARTIFACT}-{version}.aar")
    check_headers(root, dist, capi, rep)
    check_prefab(capi, version, rep)
    check_native(root, capi, parsed.get("--readelf"), parsed.get("--nm"), parsed.get("--strip"), rep)
    check_m2(root, dist, version, rep)
    check_manual(root, dist, release, version, rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
