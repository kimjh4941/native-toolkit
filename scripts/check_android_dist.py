#!/usr/bin/env python3
"""Check dist/<release>/android/ against the Android C ABI's distribution rules.

The rules come from the C ABI design (part 1 chapter 6 "配布物の名前", part 2
15.2) and README chapter 9 of artifact/topics/android-c-abi/:

  files     both AARs, the C headers in include/NativeToolkitC/, and m2/
  headers   include/, the capi AAR's Prefab headers and the tree's headers are
            byte for byte the same
  prefab    the package and module are "ntk" at the release's version; every
            ABI says "stl": "none" and API 31; the ABIs are arm64-v8a and x86_64
  native    per ABI: jni/ and Prefab hold the same libntk.so (AGP strips the
            jni/ copy and keeps Prefab's for linking and debugging, so they are
            compared stripped), every LOAD segment of both is aligned to 16 KB,
            libc++_shared.so is not needed, and the exports are the headers'
            functions and JNI_OnLoad only (AP-15)
  m2        the POMs carry io.github.kimjh4941:android-native-toolkit(-capi) at
            the release's version (README D-17), the AARs there are the ones in
            dist/, the capi POM depends on android-native-toolkit at the same
            version, and the Kotlin core libraries are at the consumer version of
            gradle/libs.versions.toml (kotlinConsumer: Kotlin 2.1 and 2.2 users) in
            the POM and in every variant of the Gradle Module Metadata, which
            Gradle reads in preference to the POM

A file that cannot be read fails its check: a check that skips because its
subject is missing reports agreement it never checked.

Usage:
    python3 scripts/check_android_dist.py [<release>] [--root <tree>] [--readelf <path>] [--nm <path>] [--strip <path>]

<release> is a folder under dist/ (default: the highest one with
android/android-native-toolkit-capi-<release>.aar). --root aims every path at
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
POM_NS = {"m": "http://maven.apache.org/POM/4.0.0"}
USAGE = "usage: check_android_dist.py [<release>] [--root <tree>] [--readelf <path>] [--nm <path>] [--strip <path>]"


def version_key(name):
    return [int(part) if part.isdigit() else part for part in re.split(r"[.-]", name)]


def default_release(root):
    found = [path.name for path in (root / "dist").glob("*")
             if (path / "android" / f"{CAPI_ARTIFACT}-{path.name}.aar").exists()]
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
    finished = subprocess.run([readelf, "-dW", str(library)], capture_output=True, text=True)
    return re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", finished.stdout)


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
    readelf = find_ndk_tool("llvm-readelf", readelf_given)
    strip = find_ndk_tool("llvm-strip", strip_given)
    listed = sorted({match for path in (root / HEADERS_IN_TREE).glob("*.h")
                     for match in re.findall(r"NTK_CALL\s*\**\s*(ntk_\w+)\s*\(", path.read_text(encoding="utf-8"))})
    with tempfile.TemporaryDirectory() as folder:
        for abi in ABIS:
            name = f"native: {abi} libntk.so (one copy, 16 KB pages, no libc++_shared)"
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
                    if "libc++_shared.so" in needed(readelf, copy):
                        problems.append(f"{label} needs libc++_shared.so")
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


def module_kotlin(path):
    """[(variant, artifact, version)] of the Kotlin dependencies in a .module file, or None."""
    try:
        metadata = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    found = []
    for variant in metadata.get("variants", []):
        for dependency in variant.get("dependencies", []):
            if dependency.get("group") == "org.jetbrains.kotlin":
                version = dependency.get("version", {})
                found.append((variant.get("name"), dependency.get("module"), version.get("requires") or version.get("strictly")))
    return found


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
        for dep_group, dep_artifact, dep_version in dependencies:
            if dep_group == "org.jetbrains.kotlin" and dep_version != kotlin:
                problems.append(f"the POM's {dep_artifact} is {dep_version}, not {kotlin}")
        in_module = module_kotlin(folder / f"{artifact}-{release}.module")
        if in_module is None:
            problems.append("cannot read the Gradle Module Metadata")
        else:
            for variant, module, version in in_module:
                if version != kotlin:
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
    rep = Report(f"Android distribution {release}")
    check_files(dist, release, rep)
    capi = zip_entries(dist / f"{CAPI_ARTIFACT}-{release}.aar")
    check_headers(root, dist, capi, rep)
    check_prefab(capi, release, rep)
    check_native(root, capi, parsed.get("--readelf"), parsed.get("--nm"), parsed.get("--strip"), rep)
    check_m2(root, dist, release, rep)
    return 0 if rep.dump() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
