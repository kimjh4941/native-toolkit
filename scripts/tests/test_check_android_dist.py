"""Break each check of the Android dist checker and confirm it notices.

Each case builds a temporary repository: the tree's C headers and version
catalog, and a dist/<release>/android/ made from the publications the build
left in android/build/m2 (scripts/build_android_library_aar.sh --m2, or the
publish tasks). It makes one change and asserts that the named check fails and
the others pass. The real tree and the real dist/ are never touched. Without a
build there is nothing real to break, so the cases are skipped.

Run: python3 -m unittest discover -s scripts/tests
"""

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_android_dist.py"
M2 = ROOT / "android" / "build" / "m2"
GROUP_DIR = "io/github/kimjh4941"
HEADERS = "android/android_library_capi/src/main/cpp/include/NativeToolkitC"
VERSIONS = "android/gradle/libs.versions.toml"


def built_release():
    folder = M2 / GROUP_DIR / "android-native-toolkit-capi"
    versions = sorted(path.name for path in folder.glob("*") if path.is_dir()) if folder.exists() else []
    return versions[-1] if versions else None


RELEASE = built_release()
# scripts/test_android.sh sets this after it published android/build/m2: a run without the
# fixture is then a failure, not a skip that would pass without checking anything.
REQUIRE_FIXTURE = os.environ.get("NTK_REQUIRE_DIST_FIXTURE") == "1"


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


def rewrite_zip(path, name, data):
    """Replaces (or with None removes) one entry of an archive."""
    with zipfile.ZipFile(path) as archive:
        entries = {item: archive.read(item) for item in archive.namelist()}
    if data is None:
        entries = {item: value for item, value in entries.items() if not item.startswith(name)}
    else:
        entries[name] = data
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for item, value in entries.items():
            archive.writestr(item, value)


@unittest.skipIf(RELEASE is None and not REQUIRE_FIXTURE,
                 "no android/build/m2: build the AARs with --m2 (or the publish tasks) first")
class AndroidDistCheckTest(unittest.TestCase):
    def setUp(self):
        if RELEASE is None:
            self.fail("no android/build/m2, and NTK_REQUIRE_DIST_FIXTURE=1 asks for it")
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        shutil.copytree(ROOT / HEADERS, self.root / HEADERS)
        (self.root / VERSIONS).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / VERSIONS, self.root / VERSIONS)
        self.dist = self.root / "dist" / RELEASE / "android"
        shutil.copytree(M2, self.dist / "m2")
        for artifact in ("android-native-toolkit", "android-native-toolkit-capi"):
            shutil.copy(self.dist / "m2" / GROUP_DIR / artifact / RELEASE / f"{artifact}-{RELEASE}.aar",
                        self.dist / f"{artifact}-{RELEASE}.aar")
        shutil.copytree(ROOT / HEADERS, self.dist / "include" / "NativeToolkitC")

    def run_checker(self):
        finished = subprocess.run([sys.executable, str(CHECKER), RELEASE, "--root", str(self.root)],
                                  capture_output=True, text=True)
        return finished.returncode, finished.stdout + finished.stderr

    def assert_only(self, prefix):
        code, output = self.run_checker()
        failed = failures(output)
        self.assertEqual(1, code, output)
        self.assertTrue(failed, output)
        for line in failed:
            self.assertTrue(line.startswith(f"FAIL {prefix}"), f"unexpected failure: {line}\n{output}")

    def capi_aar(self):
        return self.dist / f"android-native-toolkit-capi-{RELEASE}.aar"

    def rewrite_capi(self, name, data):
        """The same change in dist/ and in m2/, so that only the check under test sees it. m2/ gets a
        copy: the entries carry the time they were written, so two rewrites can differ."""
        rewrite_zip(self.capi_aar(), name, data)
        shutil.copy(self.capi_aar(), self.dist / "m2" / GROUP_DIR / "android-native-toolkit-capi" / RELEASE /
                    f"android-native-toolkit-capi-{RELEASE}.aar")

    def pom(self, artifact):
        return self.dist / "m2" / GROUP_DIR / artifact / RELEASE / f"{artifact}-{RELEASE}.pom"

    def edit(self, path, old, new):
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text, f"the case's anchor is gone from {path}")
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def test_an_intact_distribution_passes(self):
        code, output = self.run_checker()
        self.assertEqual(0, code, output)
        self.assertEqual([], failures(output))

    def test_a_missing_maven_repository_fails_files(self):
        shutil.rmtree(self.dist / "m2")
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertTrue(any(line.startswith("FAIL files") for line in failures(output)), output)

    def test_a_changed_shipped_header_fails_headers(self):
        self.edit(self.dist / "include/NativeToolkitC/Share.h", "#define", "#  define")
        self.assert_only("headers")

    def test_a_missing_shipped_header_fails_headers(self):
        (self.dist / "include/NativeToolkitC/Dialog.h").unlink()
        self.assert_only("headers")

    def test_a_header_changed_in_the_tree_after_the_build_fails_headers(self):
        self.edit(self.root / HEADERS / "Common.h", "#define", "#  define")
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertTrue(any(line.startswith("FAIL headers") for line in failures(output)), output)

    def test_another_package_name_fails_prefab(self):
        with zipfile.ZipFile(self.capi_aar()) as archive:
            package = archive.read("prefab/prefab.json").decode()
        self.rewrite_capi("prefab/prefab.json", package.replace('"ntk"', '"capi"').encode())
        self.assert_only("prefab")

    def test_a_static_stl_fails_prefab(self):
        name = "prefab/modules/ntk/libs/android.arm64-v8a/abi.json"
        with zipfile.ZipFile(self.capi_aar()) as archive:
            info = archive.read(name).decode()
        self.assertIn('"none"', info)
        self.rewrite_capi(name, info.replace('"none"', '"c++_static"').encode())
        self.assert_only("prefab")

    def test_a_missing_abi_fails_prefab_and_native(self):
        self.rewrite_capi("prefab/modules/ntk/libs/android.x86_64/", None)
        code, output = self.run_checker()
        failed = failures(output)
        self.assertEqual(1, code)
        self.assertTrue(any(line.startswith("FAIL prefab") for line in failed), output)
        self.assertTrue(any(line.startswith("FAIL native: x86_64") for line in failed), output)

    def test_another_library_in_jni_fails_native(self):
        with zipfile.ZipFile(self.capi_aar()) as archive:
            other = archive.read("jni/x86_64/libntk.so")
        self.rewrite_capi("jni/arm64-v8a/libntk.so", other)
        code, output = self.run_checker()
        self.assertEqual(1, code)
        self.assertTrue(any(line.startswith("FAIL native: arm64-v8a") for line in failures(output)), output)

    def test_another_artifact_id_fails_m2(self):
        self.edit(self.pom("android-native-toolkit-capi"), "<artifactId>android-native-toolkit-capi</artifactId>",
                  "<artifactId>ntk</artifactId>")
        self.assert_only("m2")

    def test_a_capi_pom_on_another_version_of_the_kotlin_api_fails_m2(self):
        pom = self.pom("android-native-toolkit-capi")
        text = pom.read_text(encoding="utf-8")
        changed = re.sub(r"(<artifactId>android-native-toolkit</artifactId>\s*<version>)[^<]+", r"\g<1>0.0.1", text)
        self.assertNotEqual(text, changed, "the case's anchor is gone")
        pom.write_text(changed, encoding="utf-8")
        self.assert_only("m2")

    def test_a_newer_kotlin_stdlib_fails_m2(self):
        pom = self.pom("android-native-toolkit")
        text = pom.read_text(encoding="utf-8")
        changed = re.sub(r"(<artifactId>kotlin-stdlib</artifactId>\s*<version>)[^<]+", r"\g<1>2.4.20", text)
        self.assertNotEqual(text, changed, "the case's anchor is gone")
        pom.write_text(changed, encoding="utf-8")
        self.assert_only("m2")

    def test_a_newer_kotlin_stdlib_in_the_module_metadata_fails_m2(self):
        # Gradle reads the .module file before the POM, so a POM that is right is not enough.
        metadata = self.pom("android-native-toolkit-capi").with_suffix(".module")
        text = metadata.read_text(encoding="utf-8")
        changed = re.sub(r'("module": "kotlin-stdlib",\s*"version": \{\s*"requires": ")[^"]+', r"\g<1>2.4.20", text)
        self.assertNotEqual(text, changed, "the case's anchor is gone")
        metadata.write_text(changed, encoding="utf-8")
        self.assert_only("m2")

    def test_a_library_that_registers_something_for_exit_fails_native(self):
        # A static with a destructor imports __cxa_atexit. Renaming the import malloc to atexit (same
        # length) in both copies gives such a library and keeps jni/ and Prefab alike.
        for path in ("jni/arm64-v8a/libntk.so", "prefab/modules/ntk/libs/android.arm64-v8a/libntk.so"):
            with zipfile.ZipFile(self.capi_aar()) as archive:
                library = archive.read(path)
            self.assertIn(b"\0malloc\0", library, "the case's anchor is gone")
            self.rewrite_capi(path, library.replace(b"\0malloc\0", b"\0atexit\0"))
        self.assert_only("native: arm64-v8a")

    def test_an_extra_jni_abi_fails_native(self):
        # The C ABI is 64-bit only (README D-10), even when Prefab still lists two ABIs.
        with zipfile.ZipFile(self.capi_aar()) as archive:
            library = archive.read("jni/arm64-v8a/libntk.so")
        self.rewrite_capi("jni/armeabi-v7a/libntk.so", library)
        self.assert_only("native: jni/")

    def test_a_pom_without_kotlin_fails_m2(self):
        pom = self.pom("android-native-toolkit-capi")
        text = pom.read_text(encoding="utf-8")
        changed = re.sub(r"<dependency>\s*<groupId>org\.jetbrains\.kotlin</groupId>.*?</dependency>\s*", "", text, flags=re.S)
        self.assertNotEqual(text, changed, "the case's anchor is gone")
        pom.write_text(changed, encoding="utf-8")
        self.assert_only("m2")

    def test_module_metadata_without_kotlin_fails_m2(self):
        metadata = self.pom("android-native-toolkit").with_suffix(".module")
        data = json.loads(metadata.read_text(encoding="utf-8"))
        removed = 0
        for variant in data["variants"]:
            kept = [d for d in variant.get("dependencies", []) if d.get("group") != "org.jetbrains.kotlin"]
            removed += len(variant.get("dependencies", [])) - len(kept)
            if "dependencies" in variant:
                variant["dependencies"] = kept
        self.assertGreater(removed, 0, "the case's anchor is gone")
        metadata.write_text(json.dumps(data), encoding="utf-8")
        self.assert_only("m2")

    def test_an_aar_in_m2_other_than_the_one_in_dist_fails_m2(self):
        aar = self.dist / f"android-native-toolkit-{RELEASE}.aar"
        rewrite_zip(aar, "extra.txt", b"rebuilt after publishing")
        self.assert_only("m2")

    def test_no_consumer_kotlin_version_fails_m2(self):
        self.edit(self.root / VERSIONS, "kotlinConsumer", "kotlinUser")
        self.assert_only("m2")


if __name__ == "__main__":
    unittest.main()
