"""Break each check of the C++ API contract checker and confirm it notices.

A check that cannot fail is not a check, and the ones here are easy to make
vacuous by accident: one of them silently compared the wrong operation's
documentation, because two classes both have a Close and the lookup took
whichever came first. It agreed with itself and reported OK.

Each case copies the files the checker reads into a temporary tree, makes one
small change there, and asserts that the named check fails. The real tree is
never touched.

Run: python3 -m unittest discover -s scripts/tests
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_cpp_api_contract.py"

# What the checker reads. Copying only these keeps a case fast; anything it
# cannot find it reports as a failure, which the clean case below would catch.
COPIED = [
    "artifact/topics/windows-architecture/designs/2026-09-20-windows-architecture-cpp-api-design.md",
    "artifact/features/clipboard/designs/2026-07-28-windows-clipboard-design-v2.md",
    "artifact/features/notification/designs/2026-05-30-windows-notification-design-v3.md",
    "windows/WindowsLibrary/include/NativeToolkit/Dialog.h",
    "windows/WindowsLibrary/include/NativeToolkit/Notification.h",
    "windows/WindowsLibrary/include/NativeToolkit/Clipboard.h",
    "windows/WindowsLibrary/include/NativeToolkit/Error.h",
    "windows/WindowsLibraryCApi/include/NativeToolkitC/Dialog.h",
    "windows/WindowsLibraryCApi/include/NativeToolkitC/Notification.h",
    "windows/WindowsLibraryCApi/include/NativeToolkitC/Clipboard.h",
]

DESIGN = COPIED[0]
CLIPBOARD_H = "windows/WindowsLibrary/include/NativeToolkit/Clipboard.h"
ERROR_H = "windows/WindowsLibrary/include/NativeToolkit/Error.h"


def run(root):
    finished = subprocess.run([sys.executable, str(CHECKER), "--root", str(root)],
                              capture_output=True, text=True)
    return finished.stdout


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


class ContractChecker(unittest.TestCase):

    def check_with(self, edits=(), removed=()):
        """Runs the checker over a copy of the tree, with those edits applied."""
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for fragment in COPIED:
                if fragment in removed:
                    continue
                destination = root / fragment
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / fragment, destination)
            for fragment, old, new in edits:
                path = root / fragment
                text = path.read_text(encoding="utf-8")
                self.assertIn(old, text, f"the test's own anchor is missing from {fragment}")
                path.write_text(text.replace(old, new, 1), encoding="utf-8")
            return run(root)

    def assert_catches(self, name, *edits):
        reported = failures(self.check_with(edits))
        self.assertTrue(any(name in line for line in reported),
                        f"breaking {name!r} was not reported; failures were {reported}")

    # --- the unbroken tree --------------------------------------------------

    def test_nothing_fails_when_nothing_is_wrong(self):
        output = self.check_with()
        self.assertEqual(failures(output), [], output)
        self.assertNotIn("SKIP", output, output)

    # --- section 8.1 against the code ---------------------------------------

    def test_a_file_it_cannot_read_fails(self):
        output = self.check_with(removed=(ERROR_H,))
        self.assertTrue(any("cannot check" in line for line in failures(output)), output)

    def test_a_cpp_name_the_headers_do_not_declare(self):
        self.assert_catches("every C++ name in 8.1 is declared",
                            (CLIPBOARD_H, "Result<std::wstring> PasteText();",
                             "Result<std::wstring> PasteTextRenamed();"))

    def test_a_public_operation_the_design_never_mentions(self):
        self.assert_catches("the headers declare nothing 8.1 does not",
                            (CLIPBOARD_H, "    Result<void> Clear();",
                             "    Result<void> Clear();\n    Result<void> Undesigned();"))

    # --- the enumerations against their #define -----------------------------

    def test_an_enumerator_whose_value_moved(self):
        self.assert_catches("ClipboardError matches the C ABI",
                            (ERROR_H, "    Busy                  = 3,",
                             "    Busy                  = 33,"))

    def test_an_enumerator_that_was_renamed(self):
        self.assert_catches("NotificationError matches the C ABI",
                            (ERROR_H, "    Disabled         = 2,",
                             "    DisabledRenamed  = 2,"))

    # --- section 11.4 -------------------------------------------------------

    def test_a_retval_the_table_does_not_list(self):
        self.assert_catches(
            "@retval agrees with 11.4",
            (CLIPBOARD_H, "@retval WrongThread           Called from a thread other than the owner.",
             "@retval NotForeground         Called from a thread other than the owner."))

    def test_an_error_the_code_does_not_have(self):
        self.assert_catches("11.4 names errors that exist",
                            (DESIGN, "| OP-07 | `HResultFailure` |",
                             "| OP-07 | `HResultFailure`、`NoSuchError` |"))

    # --- T-16 ---------------------------------------------------------------

    def test_an_operation_that_can_fail_but_says_nothing_about_it(self):
        self.assert_catches("every operation that can fail documents how",
                            (CLIPBOARD_H, "     * @retval Busy           Another process kept the clipboard open.\n"
                                          "     * @retval Unknown        The clipboard refused.\n",
                             ""),
                            (CLIPBOARD_H, "     * @retval NotInitialized Closed, or moved from.\n"
                                          "     */\n    Result<void> Clear();",
                             "     */\n    Result<void> Clear();"))

    def test_an_operation_with_no_comment_at_all(self):
        self.assert_catches("every operation is documented",
                            (CLIPBOARD_H, "    /**\n     * @brief Empties the clipboard.\n", "    /*\n"))

    # --- section 10 ---------------------------------------------------------

    def test_a_citation_that_points_somewhere_else(self):
        self.assert_catches("section 10 cites its sources correctly",
                            (DESIGN, "| CLP-02 | 281 |", "| CLP-02 | 481 |"))

    def test_a_citation_past_the_end_of_what_it_cites(self):
        self.assert_catches("section 10 cites its sources correctly",
                            (DESIGN, "| CLP-02 | 281 |", "| CLP-02 | 99999 |"))


if __name__ == "__main__":
    unittest.main()
