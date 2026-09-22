"""Break each check of the C ABI contract checker and confirm it notices.

Each case copies the files the checker reads into a temporary tree, makes one
small change there, and asserts that the named check fails. The real tree is
never touched. A case whose own anchor text is missing fails too, so a case
cannot go quiet because the file it edits has moved on.

Run: python3 -m unittest discover -s scripts/tests
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_c_abi_contract.py"

DESIGN = "artifact/topics/windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md"
CPP_DESIGN = "artifact/topics/windows-architecture/designs/2026-09-20-windows-architecture-cpp-api-design.md"
DEF = "windows/WindowsLibraryCApi/WindowsLibraryCApi.def"
C_DIALOG = "windows/WindowsLibraryCApi/include/NativeToolkitC/Dialog.h"
C_NOTIFICATION = "windows/WindowsLibraryCApi/include/NativeToolkitC/Notification.h"
C_CLIPBOARD = "windows/WindowsLibraryCApi/include/NativeToolkitC/Clipboard.h"
CPP_ERROR = "windows/WindowsLibrary/include/NativeToolkit/Error.h"
CPP_NOTIFICATION = "windows/WindowsLibrary/include/NativeToolkit/Notification.h"

COPIED = [
    DESIGN, CPP_DESIGN, DEF,
    "windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h", C_DIALOG, C_NOTIFICATION, C_CLIPBOARD,
    CPP_ERROR, "windows/WindowsLibrary/include/NativeToolkit/Dialog.h", CPP_NOTIFICATION,
]


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


class CAbiContractChecker(unittest.TestCase):

    def check_with(self, edits=(), removed=()):
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
            finished = subprocess.run([sys.executable, str(CHECKER), "--root", str(root)],
                                      capture_output=True, text=True, encoding="utf-8")
            return finished.stdout, finished.returncode

    def assert_catches(self, name, *edits, removed=()):
        output, code = self.check_with(edits, removed)
        reported = failures(output)
        self.assertTrue(any(name in line for line in reported),
                        f"breaking {name!r} was not reported; failures were {reported}")
        self.assertEqual(code, 1, "a failure must make the exit status 1")

    # --- the unbroken tree --------------------------------------------------

    def test_nothing_fails_when_nothing_is_wrong(self):
        output, code = self.check_with()
        self.assertEqual(failures(output), [], output)
        self.assertEqual(code, 0, output)

    def test_a_missing_file_fails_rather_than_skips(self):
        self.assert_catches("functions", removed=(DEF,))

    # --- functions ----------------------------------------------------------

    def test_an_export_the_headers_do_not_declare(self):
        self.assert_catches("functions", (DEF, "\tntk_clipboard_clear\n", "\tntk_clipboard_clear\n\tntk_clipboard_undesigned\n"))

    def test_a_function_missing_from_the_def(self):
        self.assert_catches("functions", (DEF, "\tntk_notification_set_badge\n", ""))

    def test_a_total_that_no_longer_adds_up(self):
        self.assert_catches("functions", (DESIGN, "| 合計 | | | **105** |", "| 合計 | | | **106** |"))

    def test_a_row_of_8_2_that_miscounts(self):
        self.assert_catches("functions", (DESIGN, "`ntk_clipboard_items_free` | 5 |", "`ntk_clipboard_items_free` | 6 |"))

    # --- signatures ---------------------------------------------------------

    def test_a_parameter_type_that_changed(self):
        self.assert_catches("signatures", (C_NOTIFICATION, "ntk_notification_manager* manager, int32_t value);",
                                           "ntk_notification_manager* manager, int64_t value);"))

    def test_struct_fields_that_swapped(self):
        self.assert_catches("signatures", (C_DIALOG,
                                           "    const char* name;       /**< What the user sees",
                                           "    const char* renamed;    /**< What the user sees"))

    def test_a_callback_whose_arguments_changed(self):
        self.assert_catches("signatures", (C_CLIPBOARD,
                                           "typedef void (NTK_CALL *ntk_clipboard_changed_fn)(void* user_data);",
                                           "typedef void (NTK_CALL *ntk_clipboard_changed_fn)(void* user_data, int32_t x);"))

    def test_an_enum_value_that_moved(self):
        self.assert_catches("signatures", (C_CLIPBOARD, "NTK_CLIPBOARD_ERROR_BUSY = 3,", "NTK_CLIPBOARD_ERROR_BUSY = 33,"))

    # --- operations ---------------------------------------------------------

    def test_chapter_9_naming_another_function(self):
        self.assert_catches("operations", (DESIGN, "| OP-39 | `ntk_clipboard_clear` |", "| OP-39 | `ntk_clipboard_clear_all` |"))

    def test_8_1_wrapping_another_cpp_function(self):
        self.assert_catches("operations", (DESIGN, "| OP-14 | `Manager::SetBadge` |", "| OP-14 | `Manager::SetBadges` |"))

    # --- values -------------------------------------------------------------

    def test_a_c_value_the_cpp_enum_disagrees_with(self):
        self.assert_catches("every C enumeration matches",
                            (CPP_ERROR, "    Busy                  = 3,", "    Busy                  = 30,"))

    def test_a_cpp_enumerator_the_c_abi_lacks(self):
        self.assert_catches("every C enumeration matches",
                            (CPP_NOTIFICATION, "    Circle,  ///< \"circle\"", "    Circle,  ///< \"circle\"\n    Square,"))

    def test_a_chapter_11_table_that_disagrees(self):
        self.assert_catches("tables of chapter 11", (DESIGN, "| 17 | `NOT_FOREGROUND` | - |", "| 17 | `NOT_IN_FRONT` | - |"))

    def test_copy_flags_that_are_not_the_two_bits(self):
        self.assert_catches("copy flags", (C_CLIPBOARD, "NTK_CLIPBOARD_WRITE_SENSITIVE = 3", "NTK_CLIPBOARD_WRITE_SENSITIVE = 4"))

    # --- names and ASCII ----------------------------------------------------

    def test_a_function_named_against_1_1(self):
        self.assert_catches("names", (C_DIALOG, "ntk_dialog_show_pick_folders(", "ntk_dialog_showPickFolders("))

    def test_a_constant_in_the_wrong_header(self):
        self.assert_catches("names", (C_DIALOG, "NTK_DIALOG_ERROR_UNKNOWN = 5", "NTK_DIALOG_ERROR_UNKNOWN = 5,\n    NTK_CLIPBOARD_STRAY = 6"))

    def test_a_header_that_is_not_ascii(self):
        self.assert_catches("ascii", (C_CLIPBOARD, "/** The one clipboard session of the process. */",
                                      "/** The one clipboard session of the process — only one. */"))


if __name__ == "__main__":
    unittest.main()
