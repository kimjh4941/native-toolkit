"""Break each check of the manual C example checker and confirm it notices.

Each case copies the files the checker reads into a temporary tree, makes one
small change there, and asserts that the named check fails. The real tree is
never touched. A case whose own anchor text is missing fails too, so a case
cannot go quiet because the file it edits has moved on.

The compile check is not exercised here: it needs Visual Studio, and a case
that silently passes without it would be worse than no case at all. Run
`python scripts/check_manual_c_examples.py` on Windows for that one.

Run: python3 -m unittest discover -s scripts/tests
"""

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_manual_c_examples.py"

DEF = "windows/WindowsLibraryCApi/WindowsLibraryCApi.def"
INCLUDE = "windows/WindowsLibraryCApi/include"
MANUAL = "manual"


def latest_version():
    versions = [p.name for p in (ROOT / MANUAL).iterdir()
                if p.is_dir() and re.fullmatch(r"\d+(\.\d+)*", p.name)]
    return max(versions, key=lambda v: tuple(int(part) for part in v.split(".")))


VERSION = latest_version()
PAGES = [f"{MANUAL}/{VERSION}/dialog.md",
         f"{MANUAL}/{VERSION}/dialog.ja.md",
         f"{MANUAL}/{VERSION}/dialog.ko.md",
         f"{MANUAL}/{VERSION}/clipboard.md",
         f"{MANUAL}/{VERSION}/clipboard.ja.md",
         f"{MANUAL}/{VERSION}/clipboard.ko.md",
         f"{MANUAL}/{VERSION}/notification.md",
         f"{MANUAL}/{VERSION}/notification.ja.md",
         f"{MANUAL}/{VERSION}/notification.ko.md"]


class CheckerCase(unittest.TestCase):
    def setUp(self):
        self.tree = pathlib.Path(tempfile.mkdtemp(prefix="manual-c-check-"))
        self.addCleanup(shutil.rmtree, self.tree, True)
        for fragment in PAGES + [DEF]:
            target = self.tree / fragment
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / fragment, target)
        shutil.copytree(ROOT / INCLUDE, self.tree / INCLUDE)

    def run_checker(self):
        # --require-compile is left off: the compile check reports SKIP without
        # Visual Studio, and these cases are about the other three.
        result = subprocess.run(
            [sys.executable, str(CHECKER), VERSION, "--root", str(self.tree)],
            capture_output=True, text=True, encoding="utf-8", errors="replace")
        return result.returncode, result.stdout + result.stderr

    def edit(self, fragment, old, new):
        path = self.tree / fragment
        text = path.read_text(encoding="utf-8-sig")
        self.assertIn(old, text, f"the anchor is gone from {fragment}")
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def assertFails(self, check):
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertRegex(output, rf"FAIL {check}", output)


class CleanTree(CheckerCase):
    def test_passes(self):
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)
        self.assertNotIn("FAIL", output)


class Coverage(CheckerCase):
    def test_a_new_export_that_no_example_shows(self):
        self.edit(DEF, "ntk_version", "ntk_version_two\n    ntk_version")
        self.assertFails("coverage")

    def test_an_example_that_drops_a_function(self):
        self.edit(f"{MANUAL}/{VERSION}/clipboard.md",
                  "ntk_clipboard_clear(session)", "ntk_clipboard_session_free(session)")
        self.assertFails("coverage")


class Symbols(CheckerCase):
    def test_a_function_the_headers_do_not_declare(self):
        self.edit(f"{MANUAL}/{VERSION}/dialog.md",
                  "ntk_dialog_show_alert(&request", "ntk_dialog_show_alert_box(&request")
        self.assertFails("symbols")

    def test_a_constant_the_headers_do_not_declare(self):
        self.edit(f"{MANUAL}/{VERSION}/clipboard.md",
                  "NTK_CLIPBOARD_WRITE_SENSITIVE", "NTK_CLIPBOARD_WRITE_SECRET")
        self.assertFails("symbols")


class Parity(CheckerCase):
    def test_a_language_whose_code_differs(self):
        # Inside a C block, so that the C++ examples above it are not the ones
        # being edited: only the C ABI section is compared.
        self.edit(f"{MANUAL}/{VERSION}/clipboard.ja.md",
                  'ntk_clipboard_copy_text(session, "Hello from native-toolkit"',
                  'ntk_clipboard_copy_text(session, "Hello"')
        self.assertFails("parity")

    def test_a_language_missing_a_block(self):
        page = self.tree / f"{MANUAL}/{VERSION}/dialog.ko.md"
        text = page.read_text(encoding="utf-8-sig")
        start = text.index("```c\n", text.index("### C ABI"))
        end = text.index("```", start + 5) + 3
        page.write_text(text[:start] + text[end:], encoding="utf-8")
        self.assertFails("parity")


class MissingFiles(CheckerCase):
    def test_a_missing_def_fails_rather_than_skips(self):
        (self.tree / DEF).unlink()
        self.assertFails("coverage")

    def test_missing_headers_fail_rather_than_skip(self):
        shutil.rmtree(self.tree / INCLUDE)
        self.assertFails("symbols")

    def test_a_missing_translation_fails(self):
        (self.tree / f"{MANUAL}/{VERSION}/clipboard.ko.md").unlink()
        self.assertFails("the manual is readable")

    def test_a_missing_manual_fails(self):
        shutil.rmtree(self.tree / MANUAL)
        self.assertFails("the manual is readable")


class Options(CheckerCase):
    def test_require_compile_fails_when_msbuild_is_absent(self):
        """Only meaningful where MSBuild is missing; elsewhere it must pass."""
        result = subprocess.run(
            [sys.executable, str(CHECKER), VERSION, "--root", str(self.tree), "--require-compile"],
            capture_output=True, text=True, encoding="utf-8", errors="replace")
        output = result.stdout + result.stderr
        self.assertNotIn("SKIP", output, output)


if __name__ == "__main__":
    unittest.main()
