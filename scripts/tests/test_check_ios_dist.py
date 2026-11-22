"""Break each check of the iOS dist checker and confirm it notices.

Each case copies a built distributable (the two xcframeworks and
include/NativeToolkitC/, as scripts/build_ios_library_xcframework.sh writes
them) and the files of the tree the checker reads into a temporary folder,
makes one change, and asserts that the named check fails and the others pass.
The real tree and the real dist/ are never touched. The build is found in
NTK_IOS_DIST (a folder, such as the --output-dir of the build script) or in the
highest dist/<release>/ios/ that has one. Without a build there is nothing real
to break, so the cases are skipped, unless NTK_REQUIRE_DIST_FIXTURE=1.

Run: python3 -m unittest discover -s scripts/tests
"""

import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import check_ios_dist  # noqa: E402

CHECKER = ROOT / "scripts" / "check_ios_dist.py"
TREE = (check_ios_dist.HEADERS_IN_TREE, check_ios_dist.MODULE_MAP_IN_TREE, check_ios_dist.PRIVACY_IN_TREE,
        check_ios_dist.SOURCES["IosLibrary"], check_ios_dist.SOURCES["IosLibraryCApi"])
DEVICE, SIMULATOR = "ios-arm64", "ios-arm64_x86_64-simulator"


def built_dist():
    """The folder of a built distributable, or None."""
    given = os.environ.get("NTK_IOS_DIST")
    if given:
        return pathlib.Path(given)
    release = check_ios_dist.default_release(ROOT)
    return ROOT / "dist" / release / "ios" if release else None


DIST = built_dist()
VERSION = check_ios_dist.capi_versions(DIST)[0] if DIST and check_ios_dist.capi_versions(DIST) else None
# NTK_REQUIRE_DIST_FIXTURE=1 asks for a build; so does naming one in NTK_IOS_DIST, which is then a
# failure when it is not there rather than a skip.
REQUIRE_FIXTURE = os.environ.get("NTK_REQUIRE_DIST_FIXTURE") == "1" or bool(os.environ.get("NTK_IOS_DIST"))


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


class SignatureReadingTest(unittest.TestCase):
    """What codesign -dv prints, read without signing anything."""

    LINKER = ("Executable=/x\nIdentifier=IosLibraryCApi\nFormat=Mach-O thin (arm64)\n"
              "CodeDirectory v=20400 size=4743 flags=0x20002(adhoc,linker-signed) hashes=145+0 location=embedded\n"
              "Signature=adhoc\nInfo.plist=not bound\nTeamIdentifier=not set\nSealed Resources=none\n")

    def test_unsigned_passes_everywhere(self):
        text = "/x/IosLibraryCApi.framework: code object is not signed at all\n"
        self.assertEqual([], check_ios_dist.signature_problems(text, simulator=False))
        self.assertEqual([], check_ios_dist.signature_problems(text, simulator=True))

    def test_the_linkers_signature_passes_on_the_simulator_only(self):
        self.assertEqual([], check_ios_dist.signature_problems(self.LINKER, simulator=True))
        self.assertEqual(["is signed"], check_ios_dist.signature_problems(self.LINKER, simulator=False))

    def test_a_signature_by_a_person(self):
        text = (self.LINKER.replace("flags=0x20002(adhoc,linker-signed)", "flags=0x0(none)")
                .replace("Signature=adhoc", "Signature size=4790\nAuthority=Apple Development: someone\n"
                         "Authority=Apple Worldwide Developer Relations Certification Authority")
                .replace("TeamIdentifier=not set", "TeamIdentifier=ABCDE12345"))
        problems = check_ios_dist.signature_problems(text, simulator=True)
        self.assertEqual(4, len(problems), problems)

    def test_an_ad_hoc_signature_not_from_the_linker(self):
        text = self.LINKER.replace("flags=0x20002(adhoc,linker-signed)", "flags=0x2(adhoc)")
        self.assertEqual(["is signed, and not by the linker"], check_ios_dist.signature_problems(text, simulator=True))


class RequiredReasonReadingTest(unittest.TestCase):
    def used(self, code):
        with tempfile.TemporaryDirectory() as folder:
            (pathlib.Path(folder) / "A.swift").write_text(code, encoding="utf-8")
            return sorted(check_ios_dist.used_categories(pathlib.Path(folder)))

    def test_a_name_in_a_string_is_not_a_use(self):
        self.assertEqual([], self.used('let key = "UserDefaults"\nlet text = """\nsystemUptime "\n"""\n'))
        self.assertEqual([], self.used("let c: Character = \"x\"\n/* outer /* inner */ activeInputModes */\n"))

    def test_a_slash_slash_in_a_string_does_not_hide_the_code_after_it(self):
        self.assertEqual(["NSPrivacyAccessedAPICategoryUserDefaults"],
                         self.used('let url = "https://example.com"; let value = UserDefaults.standard\n'))

    def test_code_in_an_interpolation_is_a_use(self):
        self.assertEqual(["NSPrivacyAccessedAPICategorySystemBootTime"],
                         self.used('let text = "up \\(ProcessInfo.processInfo.systemUptime) s"\n'))

    def test_swift_raw_strings(self):
        boot = ["NSPrivacyAccessedAPICategorySystemBootTime"]
        defaults = ["NSPrivacyAccessedAPICategoryUserDefaults"]
        # A quote inside a raw string does not end it; a name inside it is not a use.
        self.assertEqual([], self.used('let s = #"a "UserDefaults" b"#\n'))
        self.assertEqual(defaults, self.used('let s = #"a "x" b"#; let d = UserDefaults.standard\n'))
        # A backslash before the closing quote is not an escape in a raw string.
        self.assertEqual(defaults, self.used('let s = #"\\"#; let d = UserDefaults.standard\n'))
        # A raw interpolation is code; a plain one inside a raw string is text.
        self.assertEqual(boot, self.used('let s = #"up \\#(ProcessInfo.processInfo.systemUptime)"#\n'))
        self.assertEqual([], self.used('let s = #"up \\(ProcessInfo.processInfo.systemUptime)"#\n'))
        # A raw multi-line string ends only at """ with its #s.
        self.assertEqual([], self.used('let s = #"""\nx """ UserDefaults\n"""#\n'))
        self.assertEqual(defaults, self.used('let s = ##"a"#b"##; let d = UserDefaults.standard\n'))

    def test_a_ds_store_is_not_a_header(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            (path / "Common.h").write_text("x", encoding="utf-8")
            (path / ".DS_Store").write_bytes(b"\0")
            self.assertEqual(["Common.h"], sorted(check_ios_dist.folder_contents(path)))

    def test_a_c_character_literal_does_not_open_a_string(self):
        self.assertEqual(["NSPrivacyAccessedAPICategoryDiskSpace"], self.used("char q = '\"'; struct statfs s;\n"))

    def test_reasons_are_approved_and_typed(self):
        base = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": []}
        timestamp = "NSPrivacyAccessedAPICategoryFileTimestamp"
        cases = {
            "approved": ([{"NSPrivacyAccessedAPIType": timestamp, "NSPrivacyAccessedAPITypeReasons": ["C617.1"]}], 0),
            "unknown reason": ([{"NSPrivacyAccessedAPIType": timestamp, "NSPrivacyAccessedAPITypeReasons": ["C617.2"]}], 1),
            "reason of another category": (
                [{"NSPrivacyAccessedAPIType": timestamp, "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}], 1),
            "reasons not an array": ([{"NSPrivacyAccessedAPIType": timestamp, "NSPrivacyAccessedAPITypeReasons": "C617.1"}], 1),
            "no reason": ([{"NSPrivacyAccessedAPIType": timestamp, "NSPrivacyAccessedAPITypeReasons": []}], 1),
            "unknown category": ([{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryOther",
                                   "NSPrivacyAccessedAPITypeReasons": ["C617.1"]}], 1),
            "entries not an array": ({"NSPrivacyAccessedAPIType": timestamp}, 1),
        }
        for label, (entries, count) in cases.items():
            with self.subTest(label=label):
                _, problems = check_ios_dist.declared_categories({**base, "NSPrivacyAccessedAPITypes": entries})
                self.assertEqual(count, len(problems), problems)

    def test_each_category_is_found_in_code_and_not_in_comments(self):
        samples = {
            "NSPrivacyAccessedAPICategoryFileTimestamp": "let keys: [URLResourceKey] = [.contentModificationDateKey]",
            "NSPrivacyAccessedAPICategorySystemBootTime": "let up = ProcessInfo.processInfo.systemUptime",
            "NSPrivacyAccessedAPICategoryDiskSpace": "let keys: [URLResourceKey] = [.volumeAvailableCapacityKey]",
            "NSPrivacyAccessedAPICategoryActiveKeyboards": "let modes = UITextInputMode.activeInputModes",
            "NSPrivacyAccessedAPICategoryUserDefaults": "let value = UserDefaults.standard.bool(forKey: \"k\")",
        }
        self.assertEqual(sorted(samples), sorted(check_ios_dist.REQUIRED_REASON_APIS))
        for category, code in samples.items():
            with self.subTest(category=category), tempfile.TemporaryDirectory() as folder:
                path = pathlib.Path(folder) / "A.swift"
                path.write_text(code + "\n", encoding="utf-8")
                self.assertEqual([category], sorted(check_ios_dist.used_categories(pathlib.Path(folder))))
                path.write_text(f"// {code}\n/* {code} */\nlet other = 1\n", encoding="utf-8")
                self.assertEqual({}, check_ios_dist.used_categories(pathlib.Path(folder)))


@unittest.skipIf(VERSION is None and not REQUIRE_FIXTURE,
                 "no built iOS distributable: set NTK_IOS_DIST or build into dist/<release>/ios/ first")
class IosDistCheckTest(unittest.TestCase):
    def setUp(self):
        if VERSION is None:
            self.fail(f"no built iOS distributable in {DIST}, and NTK_IOS_DIST or NTK_REQUIRE_DIST_FIXTURE=1 asks for it")
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        for fragment in TREE:
            source, target = ROOT / fragment, self.root / fragment
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, target, ignore=shutil.ignore_patterns("*.docc"), dirs_exist_ok=True)
            else:
                shutil.copy(source, target)
        self.dist = self.root / "dist-ios"
        shutil.copytree(DIST, self.dist, symlinks=True)

    def run_checker(self, *arguments):
        finished = subprocess.run([sys.executable, str(CHECKER), "--dist", str(self.dist), "--root", str(self.root),
                                   *arguments], capture_output=True, text=True)
        return finished.returncode, finished.stdout + finished.stderr

    def assert_only_among(self, *prefixes):
        """Only checks named by prefixes fail, and the first of them does."""
        code, output = self.run_checker()
        failed = failures(output)
        self.assertEqual(1, code, output)
        self.assertTrue(any(line.startswith(f"FAIL {prefixes[0]}") for line in failed), output)
        for line in failed:
            self.assertTrue(any(line.startswith(f"FAIL {p}") for p in prefixes), f"unexpected failure: {line}\n{output}")

    def framework(self, module, slice_id):
        name = check_ios_dist.XCFRAMEWORK_NAME[module]
        return self.dist / f"{name}-{VERSION}.xcframework" / slice_id / f"{module}.framework"

    def binary(self, module, slice_id):
        return self.framework(module, slice_id) / module

    def edit_plist(self, path, change):
        with open(path, "rb") as handle:
            value = plistlib.load(handle)
        change(value)
        with open(path, "wb") as handle:
            plistlib.dump(value, handle)

    def append(self, path, text):
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text)

    def tool(self, *command):
        subprocess.run(list(command), check=True, capture_output=True)

    # --- the unbroken copy -----------------------------------------------------

    def test_nothing_fails_when_nothing_is_wrong(self):
        code, output = self.run_checker()
        self.assertEqual(0, code, output)
        self.assertEqual([], failures(output))
        self.assertEqual(18, output.count("  OK   "), output)
        self.assertIn("(134 symbols, 2 architectures)", output)

    def test_an_unknown_argument_is_a_usage_error(self):
        self.assertEqual(2, self.run_checker("--strict")[0])

    # --- files -----------------------------------------------------------------

    def test_no_loose_headers(self):
        shutil.rmtree(self.dist / "include")
        self.assert_only_among("files", "headers")

    def test_a_debug_capi(self):
        name = check_ios_dist.XCFRAMEWORK_NAME["IosLibraryCApi"]
        shutil.copytree(self.dist / f"{name}-{VERSION}.xcframework", self.dist / f"{name}-{VERSION}-debug.xcframework")
        self.assert_only_among("files")

    # --- slices ----------------------------------------------------------------

    def test_a_slice_without_x86_64(self):
        path = self.binary("IosLibraryCApi", SIMULATOR)
        self.tool("lipo", "-remove", "x86_64", "-output", str(path), str(path))
        self.assert_only_among("slices", "symbols")

    def test_an_xcframework_that_lists_another_slice(self):
        xcframework = self.framework("IosLibrary", DEVICE).parent.parent

        def add(value):
            extra = dict(value["AvailableLibraries"][0])
            extra["LibraryIdentifier"] = "ios-arm64_x86_64-maccatalyst"
            value["AvailableLibraries"].append(extra)
        self.edit_plist(xcframework / "Info.plist", add)
        self.assert_only_among("slices")

    # --- symbols ---------------------------------------------------------------

    def test_a_function_the_library_does_not_export(self):
        self.append(self.root / check_ios_dist.HEADERS_IN_TREE / "Share.h", "\nvoid NTK_CALL ntk_share_extra(void);\n")
        self.assert_only_among("symbols", "headers")

    # --- swift -----------------------------------------------------------------

    def test_a_swift_header_in_the_capi(self):
        (self.framework("IosLibraryCApi", SIMULATOR) / "Headers" / "IosLibraryCApi-Swift.h").write_text("/* */\n")
        self.assert_only_among("swift")

    def test_a_swift_module_in_the_capi(self):
        module = self.framework("IosLibraryCApi", DEVICE) / "Modules" / "IosLibraryCApi.swiftmodule"
        module.mkdir()
        (module / "arm64-apple-ios.swiftinterface").write_text("// swift-interface-format-version: 1.0\n")
        self.assert_only_among("swift")

    def test_an_interface_iosLibrary_lost(self):
        (self.framework("IosLibrary", SIMULATOR) / "Modules" / "IosLibrary.swiftmodule" /
         "x86_64-apple-ios-simulator.swiftinterface").unlink()
        self.assert_only_among("swift")

    # --- modules ---------------------------------------------------------------

    def test_a_module_map_that_is_not_the_trees(self):
        self.append(self.framework("IosLibraryCApi", DEVICE) / "Modules" / "module.modulemap", "\n")
        self.assert_only_among("modules")

    # --- dependencies, exit, install ----------------------------------------

    def test_a_dependency_on_a_bundled_swift_library(self):
        self.tool("install_name_tool", "-change", "/usr/lib/swift/libswiftCore.dylib", "@rpath/libswiftCore.dylib",
                  str(self.binary("IosLibraryCApi", DEVICE)))
        self.assert_only_among("dependencies")

    def test_an_import_that_runs_at_exit(self):
        # The symbol table is what nm reads: rename one import of the same length in it.
        path = self.binary("IosLibraryCApi", DEVICE)
        data = path.read_bytes()
        self.assertIn(b"\x00_objc_release\x00", data)
        path.write_bytes(data.replace(b"\x00_objc_release\x00", b"\x00___cxa_atexit\x00"))
        self.assert_only_among("exit")

    def test_an_install_name_that_is_not_rpath(self):
        self.tool("install_name_tool", "-id", "@executable_path/Frameworks/IosLibrary.framework/IosLibrary",
                  str(self.binary("IosLibrary", DEVICE)))
        self.assert_only_among("install")

    # --- version ---------------------------------------------------------------

    def test_versions_that_differ(self):
        self.edit_plist(self.framework("IosLibrary", SIMULATOR) / "Info.plist",
                        lambda value: value.update(CFBundleShortVersionString="1.3.0"))
        self.assert_only_among("version")

    def test_a_header_version_that_is_not_the_librarys(self):
        common = self.root / check_ios_dist.HEADERS_IN_TREE / "Common.h"
        text = common.read_text(encoding="utf-8")
        self.assertIn("#define NTK_VERSION_PATCH 0\n", text)
        common.write_text(text.replace("#define NTK_VERSION_PATCH 0\n", "#define NTK_VERSION_PATCH 1\n"), encoding="utf-8")
        self.assert_only_among("version", "headers")

    def test_a_lower_minimum_ios(self):
        self.edit_plist(self.framework("IosLibraryCApi", DEVICE) / "Info.plist",
                        lambda value: value.update(MinimumOSVersion="17.0"))
        self.assert_only_among("version")

    def test_the_old_bundle_id(self):
        self.edit_plist(self.framework("IosLibrary", DEVICE) / "Info.plist",
                        lambda value: value.update(CFBundleIdentifier="ios.library.IosLibrary"))
        self.assert_only_among("version")

    # --- privacy ---------------------------------------------------------------

    def test_a_slice_without_the_manifest(self):
        (self.framework("IosLibrary", SIMULATOR) / "PrivacyInfo.xcprivacy").unlink()
        self.assert_only_among("privacy")

    def test_a_manifest_that_does_not_lint(self):
        (self.framework("IosLibrary", DEVICE) / "PrivacyInfo.xcprivacy").write_text("<plist><dict>\n")
        self.assert_only_among("privacy")

    def test_a_category_the_sources_use_and_the_manifest_does_not_declare(self):
        self.append(self.root / check_ios_dist.SOURCES["IosLibrary"] / "Common" / "Probe.swift",
                    "let probe = UserDefaults.standard.bool(forKey: \"probe\")\n")
        self.assert_only_among("privacy")

    def test_a_category_the_capi_uses_without_a_manifest(self):
        self.append(self.root / check_ios_dist.SOURCES["IosLibraryCApi"] / "Common" / "Probe.swift",
                    "let probe = ProcessInfo.processInfo.systemUptime\n")
        self.assert_only_among("privacy")

    def test_an_api_named_in_a_comment_passes(self):
        self.append(self.root / check_ios_dist.SOURCES["IosLibraryCApi"] / "Common" / "Probe.swift",
                    "// UserDefaults and systemUptime are not used here.\nlet probe = 1\n")
        code, output = self.run_checker()
        self.assertEqual(0, code, output)

    # --- signature -------------------------------------------------------------

    def test_an_ad_hoc_signed_device_slice(self):
        # Ad hoc (-s -): no key and no certificate is used.
        self.tool("codesign", "-s", "-", "-f", str(self.binary("IosLibraryCApi", DEVICE)))
        self.assert_only_among("signature")

    def test_a_simulator_slice_signed_ad_hoc_by_codesign_not_the_linker(self):
        self.tool("codesign", "-s", "-", "-f", str(self.binary("IosLibrary", SIMULATOR)))
        code, output = self.run_checker()
        self.assertIn("is signed, and not by the linker", output)
        self.assert_only_among("signature")

    def test_a_reason_apple_does_not_approve(self):
        # The same manifest in the tree and both slices, so that only the reason differs.
        paths = [self.root / check_ios_dist.PRIVACY_IN_TREE] + [
            self.framework("IosLibrary", slice_id) / "PrivacyInfo.xcprivacy" for slice_id in (DEVICE, SIMULATOR)]
        for path in paths:
            text = path.read_text(encoding="utf-8")
            self.assertIn("<string>C617.1</string>", text)
            path.write_text(text.replace("<string>C617.1</string>", "<string>C617.9</string>"), encoding="utf-8")
        code, output = self.run_checker()
        self.assertIn("not a reason Apple approves", output)
        self.assert_only_among("privacy")

    def test_an_api_named_in_a_string_passes_and_one_after_a_url_does_not(self):
        probe = self.root / check_ios_dist.SOURCES["IosLibraryCApi"] / "Common" / "Probe.swift"
        probe.write_text('let probe = "UserDefaults systemUptime"\n', encoding="utf-8")
        self.assertEqual(0, self.run_checker()[0])
        probe.write_text('let site = "https://example.com"; let probe = UserDefaults.standard\n', encoding="utf-8")
        self.assert_only_among("privacy")

    def test_a_sealed_device_framework(self):
        seal = self.framework("IosLibraryCApi", DEVICE) / "_CodeSignature"
        seal.mkdir()
        (seal / "CodeResources").write_text("<plist/>\n")
        self.assert_only_among("signature")

    # --- headers ---------------------------------------------------------------

    def test_loose_headers_that_differ(self):
        self.append(self.dist / "include" / "NativeToolkitC" / "Dialog.h", "\n")
        self.assert_only_among("headers")

    def test_a_subfolder_only_the_loose_headers_have(self):
        extra = self.dist / "include" / "NativeToolkitC" / "extra"
        extra.mkdir()
        (extra / "Other.h").write_text("/* */\n")
        self.assert_only_among("headers")

    def test_an_empty_subfolder_in_the_framework_headers(self):
        (self.framework("IosLibraryCApi", DEVICE) / "Headers" / "NativeToolkitC" / "sub").mkdir()
        self.assert_only_among("headers")

    def test_framework_headers_that_differ(self):
        (self.framework("IosLibraryCApi", SIMULATOR) / "Headers" / "NativeToolkitC" / "Share.h").unlink()
        self.assert_only_among("headers")


if __name__ == "__main__":
    unittest.main()
