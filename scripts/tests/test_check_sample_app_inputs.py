"""Tests for the sample app input field checker.

The checker exists because review cannot see this defect, so a checker that
quietly passes would be worse than none at all. These break it on purpose:
each case that must FAIL is paired with the near-miss that must not, because
the two live one character apart in the source (a tag versus the same word
inside a caption).

Run: python3 -m unittest discover -s scripts/tests
"""

import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_sample_app_inputs.py"

PASS, FAIL, SKIP = 0, 1, 2


def run(files):
    """Write files into a temp root and run the checker over it."""
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        for name, text in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(CHECKER), str(root)],
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout


class Declarations(unittest.TestCase):
    def test_xaml_input_is_reported(self):
        code, out = run({"Page.xaml": '<Page>\n  <TextBox x:Name="Input" />\n</Page>\n'})
        self.assertEqual(code, FAIL, out)
        self.assertIn("TextBox", out)

    def test_caption_naming_a_control_is_not_reported(self):
        # The real line in NotificationPage.xaml. A checker that matched the bare
        # word would fail the tree as it stands today.
        code, out = run({
            "Page.xaml": '<Page>\n'
                         '  <Button Content="ShowWithInput (TextBox + ComboBox)" />\n'
                         '</Page>\n'
        })
        self.assertEqual(code, PASS, out)

    def test_swift_input_is_reported(self):
        code, out = run({"View.swift": 'var body: some View {\n    TextField("x", text: $v)\n}\n'})
        self.assertEqual(code, FAIL, out)
        self.assertIn("TextField", out)

    def test_swift_modifier_is_not_reported(self):
        # .textFieldStyle( shares the word but declares nothing.
        code, out = run({"View.swift": 'Text("x")\n    .textFieldStyle(.roundedBorder)\n'})
        self.assertEqual(code, PASS, out)

    def test_kotlin_input_is_reported(self):
        code, out = run({"Screen.kt": "@Composable\nfun S() {\n    OutlinedTextField(value = v, onValueChange = {})\n}\n"})
        self.assertEqual(code, FAIL, out)

    def test_android_xml_input_is_reported(self):
        code, out = run({"layout.xml": '<LinearLayout>\n  <EditText android:id="@+id/x" />\n</LinearLayout>\n'})
        self.assertEqual(code, FAIL, out)

    def test_commented_out_declaration_is_not_reported(self):
        code, out = run({"View.swift": '// TextField("x", text: $v)\n'})
        self.assertEqual(code, PASS, out)


class Approval(unittest.TestCase):
    MARKER = "sample-app-input-approved: artifact/designs/f/plan.md"

    def test_marker_allows_the_field(self):
        code, out = run({
            "Page.xaml": f"<!-- {self.MARKER} -->\n<Page>\n  <TextBox />\n</Page>\n"
        })
        self.assertEqual(code, PASS, out)
        self.assertIn("ALLOW", out)

    def test_marker_without_a_reference_does_not_allow(self):
        # A bare marker names no plan document, so nothing carries the reason.
        code, out = run({"Page.xaml": "<!-- sample-app-input-approved: -->\n<Page>\n  <TextBox />\n</Page>\n"})
        self.assertEqual(code, FAIL, out)

    def test_marker_does_not_leak_to_other_files(self):
        code, out = run({
            "Allowed.xaml": f"<!-- {self.MARKER} -->\n<Page><TextBox /></Page>\n",
            "Other.xaml": "<Page><TextBox /></Page>\n",
        })
        self.assertEqual(code, FAIL, out)
        self.assertIn("Other.xaml", out)


class VacuousPass(unittest.TestCase):
    def test_empty_root_reports_skip_not_ok(self):
        code, out = run({})
        self.assertEqual(code, SKIP, out)
        self.assertIn("SKIP", out)

    def test_unreadable_suffix_is_not_counted_as_checked(self):
        code, out = run({"notes.txt": "<TextBox />\n"})
        self.assertEqual(code, SKIP, out)


class CurrentTree(unittest.TestCase):
    def test_the_repository_passes(self):
        result = subprocess.run(
            [sys.executable, str(CHECKER)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
        )
        self.assertEqual(result.returncode, PASS, result.stdout + result.stderr)
        # Guards against the roots being renamed and the run going vacuous.
        self.assertNotIn("0 files checked", result.stdout)


if __name__ == "__main__":
    unittest.main()
