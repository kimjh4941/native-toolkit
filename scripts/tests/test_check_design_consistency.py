"""Tests for the parts of the design checker that decide what it checks.

The checker is what the review workflow leans on, and its exemption has now been wrong
twice: once matching the token anywhere in the document, once matching the declaration line
anywhere. Both times the check went quiet and nothing said so. These pin the boundary.

Run: python3 -m unittest discover -s scripts/tests
"""

import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_design_consistency.py"

# Named so the checker recognises a clipboard document; it keys its source roots off the name.
DOCUMENT = "clipboard-exemption-case.md"

TITLE = "# macOS Clipboard test document\n\n"
INFO = "## 基本情報\n\n- 機能名: clipboard\n- 対象OS: macOS 15 以降\n"
BODY = "\n## 1. 本文\n\n`somethingThatDoesNotExistAnywhere` を名指しする。\n"
DECLARATION = "- **`PLANNED_SYMBOLS_EXEMPT`**: 未実装のコードを名指す\n"


def run(text):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / DOCUMENT
        path.write_text(text, encoding="utf-8")
        finished = subprocess.run([sys.executable, str(CHECKER), str(path)],
                                  capture_output=True, text=True, cwd=ROOT)
        return finished.stdout


def is_exempt(output):
    return "declares PLANNED_SYMBOLS_EXEMPT" in output


class ExemptionBoundary(unittest.TestCase):

    def test_a_declaration_in_the_info_section_exempts_the_document(self):
        self.assertTrue(is_exempt(run(TITLE + INFO + DECLARATION + BODY)))

    def test_a_declaration_in_an_appendix_does_not_exempt_the_document(self):
        self.assertFalse(is_exempt(run(TITLE + INFO + BODY + "\n## Appendix\n\n" + DECLARATION)))

    def test_merely_mentioning_the_token_does_not_exempt_the_document(self):
        mention = "\n| 中 7 | 除外を `PLANNED_SYMBOLS_EXEMPT` の宣言制にした |\n"
        self.assertFalse(is_exempt(run(TITLE + INFO + mention + BODY)))

    def test_a_document_with_one_section_cannot_exempt_itself(self):
        # Everything is "before the second heading" when there is no second heading, which is
        # how a one-section document used to opt out from anywhere in its text.
        self.assertFalse(is_exempt(run(TITLE + INFO + DECLARATION)))

    def test_a_declaration_that_is_not_a_bullet_does_not_exempt_the_document(self):
        # The shape is the declaration. A mention inside a prose line, a table cell, or a code
        # fence is not a document declaring anything (review v5 MU-7), and the info section of
        # a real plan carries change tables where the token appears in bold.
        for shape in ["**`PLANNED_SYMBOLS_EXEMPT`**: 誤り\n",
                      "| 変更 | **`PLANNED_SYMBOLS_EXEMPT`** を宣言制にした |\n",
                      "```\n- **`PLANNED_SYMBOLS_EXEMPT`**\n```\n"]:
            with self.subTest(shape=shape):
                self.assertFalse(is_exempt(run(TITLE + INFO + shape + BODY)))

    def test_a_declaration_below_the_info_section_does_not_exempt_the_document(self):
        # The upper bound of the front matter is the second heading, not the last one
        # (review v5 MU-8): a declaration in section 1 is already outside it.
        text = TITLE + INFO + "\n## 1. 本文\n\n" + DECLARATION + "\n## 2. 続き\n\n本文\n"
        self.assertFalse(is_exempt(run(text)))

    def test_the_check_actually_runs_when_the_document_is_not_exempt(self):
        # Without this, all of the above could pass because the check never ran at all.
        output = run(TITLE + INFO + BODY)
        self.assertIn("named symbols exist in the implementation", output)
        self.assertIn("somethingThatDoesNotExistAnywhere", output)


if __name__ == "__main__":
    unittest.main()
