"""Break each check of the manual iOS C example checker and confirm it notices.

The manual has no iOS C ABI section until stage 4, so each case writes a small
manual of its own into a temporary tree: one page in three languages whose iOS
chapter has a C ABI section. Its first block lists every function in a comment
(coverage reads the block as written); the second is real code. The public
headers do not exist until TB-1 either, so the tree gets a skeleton of them
written from Appendix A as it stands. The real tree is never touched.

The compile cases need Xcode's clang and are skipped, saying so, without it.

Run: python3 -m unittest discover -s scripts/tests
"""

import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_manual_c_examples_ios.py"
sys.path.insert(0, str(ROOT / "scripts"))
import c_abi_contract_common  # noqa: E402
import check_manual_c_examples_ios  # noqa: E402
import manual_c_examples_common  # noqa: E402

DESIGN = "artifact/topics/ios-c-abi/designs/2026-11-03-ios-c-abi-c-abi-design-part2.md"
INCLUDE = "ios/IosLibraryCApi/include"
VERSION = "9.9.9"
PAGE = f"manual/{VERSION}/clipboard"
CLANG = check_manual_c_examples_ios.find_clang(None) and check_manual_c_examples_ios.find_sdk()

CODE = """\
static void NTK_CALL on_change(void* user_data, ntk_clipboard_change* change)
{
    (void)user_data;
    ntk_clipboard_change_free(change);
}

ntk_clipboard_listener* listener = NULL;
ntk_clipboard_error error = ntk_clipboard_cancel_load(1);
if (error == NTK_CLIPBOARD_ERROR_NONE) {
    ntk_clipboard_add_change_listener(on_change, NULL, NULL, &listener);
}
"""


def page(functions, comment):
    every = " ".join(sorted(functions))
    return (f"# Clipboard\n\n## iOS\n\nSwift first.\n\n### C ABI\n\n{comment}\n\n"
            f"```c\n/* {every} */\n```\n\n```c\n{CODE}```\n\n---\n\n## Android\n\nNothing here.\n")


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


# A manual whose Windows chapter has a C ABI section and whose iOS chapter has none.
NO_IOS_C_ABI = "1.12.0"


class IosManualChecker(unittest.TestCase):

    def setUp(self):
        self.tree = pathlib.Path(tempfile.mkdtemp(prefix="manual-c-check-ios-"))
        self.addCleanup(shutil.rmtree, self.tree, True)
        design = (ROOT / DESIGN).read_text(encoding="utf-8")
        for name, code in c_abi_contract_common.appendix_headers(design).items():
            path = self.tree / INCLUDE / "NativeToolkitC" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(code, encoding="utf-8")
        self.functions = set(c_abi_contract_common.declarations(
            c_abi_contract_common.appendix_code(design))["function"])
        for suffix, comment in (("", "Each block in C."), (".ja", "C のブロック。"), (".ko", "C 블록.")):
            path = self.tree / f"{PAGE}{suffix}.md"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(page(self.functions, comment), encoding="utf-8")

    def run_checker(self, *arguments, env=None):
        result = subprocess.run([sys.executable, str(CHECKER), VERSION, "--root", str(self.tree), *arguments],
                                capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
        return result.returncode, result.stdout + result.stderr

    def edit(self, fragment, old, new):
        path = self.tree / fragment
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text, f"the anchor is gone from {fragment}")
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def assertFails(self, check, *arguments):
        code, output = self.run_checker(*arguments)
        self.assertEqual(code, 1, output)
        self.assertTrue(any(check in line for line in failures(output)), output)

    # --- the unbroken tree --------------------------------------------------

    def test_passes(self):
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)
        self.assertEqual(failures(output), [], output)
        self.assertIn(f"coverage: every exported function appears in an example ({len(self.functions)})", output)

    def test_a_manual_without_an_ios_c_abi_section_skips(self):
        # The Windows chapter of the real manual has a C ABI section; the iOS
        # chapter must not borrow it.
        real = ROOT / "manual"
        version = NO_IOS_C_ABI
        shutil.copytree(real / version, self.tree / "manual" / version, ignore=shutil.ignore_patterns("images"))
        result = subprocess.run([sys.executable, str(CHECKER), version, "--root", str(self.tree)],
                                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("SKIP the manual has C examples", result.stdout)
        self.assertIn("an iOS C ABI section", result.stdout)
        self.assertTrue(any("### C ABI" in p.read_text(encoding="utf-8-sig")
                            for p in (real / version).glob("*.md")), "the real manual has no C ABI section to borrow")

    def test_another_os_chapter_is_not_read_as_ios(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "## iOS\n", "## Windows\n")
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)
        self.assertIn("SKIP the manual has C examples", output)

    def test_a_heading_of_another_level_before_the_chapter(self):
        # '### iOS' must not be taken for the chapter, leaving no section to check.
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "# Clipboard\n", "# Clipboard\n\n### iOS\n\nA note.\n")
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_cancel_load(1)", "ntk_clipboard_cancel_all(1)")
        self.assertFails("symbols")

    # --- coverage and symbols -----------------------------------------------

    def test_a_function_no_example_shows(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", " ntk_share_content_async ", " ")
        self.assertFails("coverage")

    def test_a_name_the_headers_do_not_declare(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_cancel_load(1)", "ntk_clipboard_cancel_all(1)")
        self.assertFails("symbols")

    def test_a_constant_the_headers_do_not_declare(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "NTK_CLIPBOARD_ERROR_NONE", "NTK_CLIPBOARD_ERROR_NOTHING")
        self.assertFails("symbols")

    def test_a_name_only_a_comment_of_the_headers_has(self):
        header = self.tree / INCLUDE / "NativeToolkitC" / "Share.h"
        header.write_text(header.read_text(encoding="utf-8") + "/* ntk_clipboard_cancel_all */\n// NTK_CLIPBOARD_ERROR_NOTHING\n", encoding="utf-8")
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_cancel_load(1)", "ntk_clipboard_cancel_all(1)")
        self.assertFails("symbols")

    def test_a_header_this_script_does_not_list_adds_to_coverage(self):
        (self.tree / INCLUDE / "NativeToolkitC" / "Ios.h").write_text("int NTK_CALL ntk_ios_new(void);\n", encoding="utf-8")
        self.assertFails("coverage")

    def test_a_block_under_the_next_heading_is_not_of_the_section(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "\n---\n\n## Android", "\n### Something else\n\n```c\nntk_not_declared();\n```\n\n---\n\n## Android")
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)

    def test_missing_headers_fail_rather_than_skip(self):
        shutil.rmtree(self.tree / INCLUDE)
        self.assertFails("coverage")

    def test_one_missing_header_fails_rather_than_asking_for_less(self):
        (self.tree / INCLUDE / "NativeToolkitC" / "Share.h").unlink()
        self.assertFails("coverage")

    # --- a section that would read as absent -------------------------------

    def test_a_heading_that_nearly_reads_the_chapter(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "## iOS\n", "## iOS (Swift)\n")
        self.assertFails("the manual is readable")

    def test_a_heading_that_nearly_reads_c_abi(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "### C ABI", "### C-ABI")
        self.assertFails("the manual is readable")

    def test_a_translation_with_a_section_english_lacks(self):
        self.edit(f"{PAGE}.md", "### C ABI\n", "### Native\n")
        self.assertFails("the manual is readable")

    def test_require_examples_fails_on_a_manual_without_them(self):
        version = NO_IOS_C_ABI
        shutil.copytree(ROOT / "manual" / version, self.tree / "manual" / version, ignore=shutil.ignore_patterns("images"))
        result = subprocess.run([sys.executable, str(CHECKER), version, "--root", str(self.tree), "--require-examples"],
                                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("FAIL the manual is readable", result.stdout)

    # --- arguments ----------------------------------------------------------

    def test_an_unknown_argument_is_a_usage_error(self):
        code, output = self.run_checker("--require-compiles")
        self.assertEqual(code, 2, output)

    def test_an_option_without_its_value_is_a_usage_error(self):
        code, output = self.run_checker("--clang")
        self.assertEqual(code, 2, output)

    def test_an_option_given_twice_is_a_usage_error(self):
        code, output = self.run_checker("--clang", "a", "--clang", "b")
        self.assertEqual(code, 2, output)

    # --- parity -------------------------------------------------------------

    def test_a_language_whose_code_differs(self):
        self.edit(f"{PAGE}.ja.md", "ntk_clipboard_cancel_load(1)", "ntk_clipboard_cancel_load(2)")
        self.assertFails("parity")

    def test_a_language_without_the_section(self):
        self.edit(f"{PAGE}.ko.md", "### C ABI", "### Other")
        self.assertFails("parity")

    def test_a_missing_translation_fails(self):
        (self.tree / f"{PAGE}.ko.md").unlink()
        self.assertFails("the manual is readable")

    # --- compile ------------------------------------------------------------

    @unittest.skipUnless(CLANG, "Xcode's clang and iOS SDK were not found")
    def test_the_examples_compile(self):
        code, output = self.run_checker("--require-compile")
        self.assertEqual(code, 0, output)
        self.assertRegex(output, r"OK   compile: the examples compile as plain C \(2 examples\)")

    @unittest.skipUnless(CLANG, "Xcode's clang and iOS SDK were not found")
    def test_an_example_that_does_not_compile(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_cancel_load(1)", "ntk_clipboard_cancel_load(1, 2)")
        self.assertFails("compile", "--require-compile")

    @unittest.skipUnless(CLANG, "Xcode's clang and iOS SDK were not found")
    def test_a_warning_fails_the_compile(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "if (error == NTK_CLIPBOARD_ERROR_NONE) {", "if (error = NTK_CLIPBOARD_ERROR_NONE) {")
        self.assertFails("compile", "--require-compile")

    @unittest.skipUnless(CLANG, "Xcode's clang and iOS SDK were not found")
    def test_a_cpp_keyword_is_a_name_in_c(self):
        # It compiles only because the compiler reads C, not C++.
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_listener* listener = NULL;",
                      "int class = 0;\nntk_clipboard_listener* listener = NULL;")
        code, output = self.run_checker("--require-compile")
        self.assertEqual(code, 0, output)

    @unittest.skipUnless(CLANG, "Xcode's clang and iOS SDK were not found")
    def test_the_standard_is_c99_without_extensions(self):
        # typeof is a keyword in gnu modes and a name under -std=c99.
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_listener* listener = NULL;",
                      "int typeof = 0;\nntk_clipboard_listener* listener = NULL;")
        code, output = self.run_checker("--require-compile")
        self.assertEqual(code, 0, output)

    @unittest.skipUnless(CLANG, "Xcode's clang and iOS SDK were not found")
    def test_the_target_is_ios_18(self):
        # A negative array size unless the compiler is aimed at iOS 18 exactly.
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_listener* listener = NULL;",
                      "int aimed[__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ == 180000 ? 1 : -1];\n"
                      "ntk_clipboard_listener* listener = NULL;")
        code, output = self.run_checker("--require-compile")
        self.assertEqual(code, 0, output)

    @unittest.skipUnless(CLANG, "Xcode's clang and iOS SDK were not found")
    def test_an_example_in_utf_8_compiles(self):
        for suffix in ("", ".ja", ".ko"):
            self.edit(f"{PAGE}{suffix}.md", "ntk_clipboard_listener* listener = NULL;",
                      "const char* text = \"こんにちは\";\nntk_clipboard_listener* listener = NULL;")
        code, output = self.run_checker("--require-compile")
        self.assertEqual(code, 0, output)

    def test_a_clang_given_that_does_not_exist_fails(self):
        self.assertFails("compile", "--clang", str(self.tree / "no-clang"))

    def no_xcode(self):
        empty = self.tree / "no-bin"
        empty.mkdir()
        env = dict(os.environ)
        env["PATH"] = str(empty)
        return env

    def test_no_xcode_skips_without_require_compile(self):
        code, output = self.run_checker(env=self.no_xcode())
        self.assertEqual(code, 0, output)
        self.assertTrue(re.search(r"SKIP compile", output), output)

    def test_no_xcode_fails_with_require_compile(self):
        code, output = self.run_checker("--require-compile", env=self.no_xcode())
        self.assertEqual(code, 1, output)
        self.assertIn("FAIL compile", output)

    # --- writing the examples out -------------------------------------------

    def test_a_block_the_encoding_cannot_hold_is_reported_not_raised(self):
        found = {"page": {"": ['int x = 0; /* — */']}}
        with tempfile.TemporaryDirectory() as work:
            written, problems = manual_c_examples_common.write_sources(found, work, "", encoding="ascii")
        self.assertEqual(written, [])
        self.assertEqual(len(problems), 1, problems)


if __name__ == "__main__":
    unittest.main()
