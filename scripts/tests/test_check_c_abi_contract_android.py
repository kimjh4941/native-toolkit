"""Break each check of the Android C ABI contract checker and confirm it notices.

Each case copies the files the checker reads into a temporary tree, makes one
small change there, and asserts that the named check fails. The public headers
do not exist until stage 2b, so the tree gets a skeleton of them written from
Appendix A. The real tree is never touched. A case whose own anchor text is
missing fails too, so a case cannot go quiet because the file it edits has
moved on.

Run: python3 -m unittest discover -s scripts/tests
"""

import os
import pathlib
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_c_abi_contract_android.py"
sys.path.insert(0, str(ROOT / "scripts"))
import c_abi_contract_common  # noqa: E402

DESIGN = "artifact/topics/android-c-abi/designs/2026-10-05-android-c-abi-c-abi-design-part2.md"
README = "artifact/topics/android-c-abi/README.md"
KOTLIN = "android/android_library/src/main/java"
INCLUDE = "android/android_library_capi/src/main/cpp/include/NativeToolkitC"
WINDOWS_COMMON = "windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h"
COMMON = f"{INCLUDE}/Common.h"
CLIPBOARD = f"{INCLUDE}/Clipboard.h"
SHARE = f"{INCLUDE}/Share.h"
KOTLIN_PACKAGE = f"{KOTLIN}/com/jonghyunkim/nativetoolkit"
CLIPBOARD_MANAGER = f"{KOTLIN_PACKAGE}/clipboard/AndroidClipboardManager.kt"
SHARE_ERROR = f"{KOTLIN_PACKAGE}/share/domain/error/ShareDomainError.kt"


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


class AndroidCAbiContractChecker(unittest.TestCase):

    def run_checker(self, edits=(), removed=(), headers=True, arguments=(), before=None):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for fragment in (DESIGN, README, WINDOWS_COMMON):
                destination = root / fragment
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / fragment, destination)
            shutil.copytree(ROOT / KOTLIN, root / KOTLIN)
            if headers:
                design = (ROOT / DESIGN).read_text(encoding="utf-8")
                for name, code in c_abi_contract_common.appendix_headers(design).items():
                    path = root / INCLUDE / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(code, encoding="utf-8")
            for fragment in removed:
                (root / fragment).unlink()
            for fragment, old, new in edits:
                path = root / fragment
                text = path.read_text(encoding="utf-8")
                self.assertIn(old, text, f"the test's own anchor is missing from {fragment}")
                path.write_text(text.replace(old, new, 1), encoding="utf-8")
            extra = list(arguments)
            if before:
                extra += before(root)
            finished = subprocess.run([sys.executable, str(CHECKER), "--root", str(root), *extra],
                                      capture_output=True, text=True, encoding="utf-8")
            return finished.stdout, finished.returncode

    def assert_catches(self, name, *edits, removed=(), headers=True, arguments=(), before=None):
        output, code = self.run_checker(edits, removed, headers, arguments, before)
        reported = failures(output)
        self.assertTrue(any(name in line for line in reported),
                        f"breaking {name!r} was not reported; failures were {reported}")
        self.assertEqual(code, 1, "a failure must make the exit status 1")

    def assert_passes(self, *edits, headers=True, arguments=(), before=None):
        output, code = self.run_checker(edits, (), headers, arguments, before)
        self.assertEqual(failures(output), [], output)
        self.assertEqual(code, 0, output)
        return output

    # --- the unbroken tree --------------------------------------------------

    def test_nothing_fails_when_nothing_is_wrong(self):
        output = self.assert_passes()
        self.assertIn("SKIP symbols", output)
        self.assertNotIn("SKIP signatures", output)

    def test_design_only_reads_appendix_a_in_place_of_the_headers(self):
        output = self.assert_passes(headers=False, arguments=("--design-only",))
        self.assertIn("SKIP signatures", output)

    def test_a_missing_header_fails_rather_than_skips(self):
        self.assert_catches("the public header Share.h", removed=(SHARE,))

    def test_no_headers_without_design_only_fails(self):
        self.assert_catches("functions", headers=False)

    # --- functions ----------------------------------------------------------

    def test_a_header_function_8_2_does_not_name(self):
        self.assert_catches("functions", (CLIPBOARD, "ntk_clipboard_error NTK_CALL ntk_clipboard_clear(void);",
                                          "ntk_clipboard_error NTK_CALL ntk_clipboard_clear(void);\n"
                                          "ntk_clipboard_error NTK_CALL ntk_clipboard_undesigned(void);"))

    def test_a_total_that_no_longer_adds_up(self):
        self.assert_catches("functions", (DESIGN, "| 合計 | | | 155 |", "| 合計 | | | 156 |"))

    def test_a_row_of_8_2_that_miscounts(self):
        self.assert_catches("functions", (DESIGN, "`ntk_bytes_data`、`ntk_bytes_size`、`ntk_bytes_free` | 3 |",
                                          "`ntk_bytes_data`、`ntk_bytes_size`、`ntk_bytes_free` | 4 |"))

    def test_a_heading_that_disagrees_with_the_total(self):
        self.assert_catches("functions", (DESIGN, "### 8.2 公開する関数の全体（155）", "### 8.2 公開する関数の全体（150）"))

    # --- signatures ---------------------------------------------------------

    def test_a_parameter_type_that_changed(self):
        self.assert_catches("signatures", (CLIPBOARD, "ntk_clipboard_error NTK_CALL ntk_clipboard_has_clip(int32_t* out_has_clip);",
                                           "ntk_clipboard_error NTK_CALL ntk_clipboard_has_clip(int64_t* out_has_clip);"))

    # --- operations and Kotlin ----------------------------------------------

    def test_chapter_9_missing_an_operation(self):
        self.assert_catches("operations", (DESIGN, "| OP-05 | `clearPrimaryClip`（同期）", "| OP-5x | `clearPrimaryClip`（同期）"))

    def test_8_1_naming_a_function_appendix_a_lacks(self):
        self.assert_catches("operations", (DESIGN, "| `ntk_clipboard_clear()` |", "| `ntk_clipboard_clear_all()` |"))

    def test_a_kotlin_entry_that_was_renamed(self):
        self.assert_catches("kotlin", (CLIPBOARD_MANAGER, "fun copyPlainText(", "fun copyPlain("))

    # --- behaviours ---------------------------------------------------------

    def test_a_behaviour_naming_an_unknown_operation(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-01 | テキストをコピーする | 操作 | 同期の結果 | CL-06 | OP-01 |",
                                           "| BH-01 | テキストをコピーする | 操作 | 同期の結果 | CL-06 | OP-99 |"))

    def test_a_kind_its_functions_contradict(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-01 | テキストをコピーする | 操作 | 同期の結果 |",
                                           "| BH-01 | テキストをコピーする | 操作 | 受け付けた後の完了 |"))

    def test_a_completion_whose_function_takes_no_callback(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-11 | Alert を出す | 操作と完了 | 受け付けた後の完了 | DL-08 | OP-13 |",
                                           "| BH-11 | Alert を出す | 操作と完了 | 受け付けた後の完了 | DL-08 | OP-05 |"))

    def test_an_operation_count_readme_disagrees_with(self):
        self.assert_catches("behaviours", (README, "| 計 | 69 | 45 |", "| 計 | 69 | 46 |"))

    def test_a_gap_in_the_ids(self):
        self.assert_catches("behaviours", (DESIGN, "| EV-05 |", "| EV-06 |"))

    # --- values -------------------------------------------------------------

    def test_a_header_value_the_table_disagrees_with(self):
        self.assert_catches("tables of chapter 11", (SHARE, "NTK_SHARE_ERROR_NO_SHARE_TARGET = 8,", "NTK_SHARE_ERROR_NO_SHARE_TARGET = 18,"))

    def test_a_shared_value_one_feature_moved(self):
        self.assert_catches("0 to 5", (DESIGN, "| 4 | `UNKNOWN` |", "| 4 | `UNKNOWN_ERROR` |"))

    def test_a_kotlin_order_that_changed(self):
        self.assert_catches("Kotlin declaration order", (SHARE_ERROR, "    data object EmptyIdList : ShareDomainError()\n",
                                                         "    data object EmptyIdListMoved : ShareDomainError()\n"))

    # --- names and ASCII ----------------------------------------------------

    def test_a_function_named_against_the_rules(self):
        self.assert_catches("names", (CLIPBOARD, "ntk_clipboard_has_clip(", "ntk_clipboard_hasClip("))

    def test_a_constant_in_the_wrong_header(self):
        self.assert_catches("names", (SHARE, "NTK_SHARE_ERROR_NONE = 0,", "NTK_SHARE_ERROR_NONE = 0,\n    NTK_CLIPBOARD_STRAY = 99,"))

    def test_a_header_that_is_not_ascii(self):
        self.assert_catches("ascii", (CLIPBOARD, "#define NATIVETOOLKITC_CLIPBOARD_H", "#define NATIVETOOLKITC_CLIPBOARD_H /* — */"))

    def test_appendix_a_that_is_not_ascii(self):
        self.assert_catches("ascii", (DESIGN, "#define NATIVETOOLKITC_CLIPBOARD_H", "#define NATIVETOOLKITC_CLIPBOARD_H /* — */"),
                            headers=False, arguments=("--design-only",))

    # --- Common.h across the OSes (part 1, 5.2) ----------------------------

    def test_a_shared_declaration_that_differs(self):
        self.assert_catches("common", (WINDOWS_COMMON, "size_t      NTK_CALL ntk_string_size(const ntk_string* s);",
                                       "uint32_t    NTK_CALL ntk_string_size(const ntk_string* s);"))

    def test_an_incomplete_type_only_one_side_has(self):
        self.assert_catches("common", (COMMON, "typedef struct ntk_bytes ntk_bytes;", "typedef struct ntk_bytes ntk_bytes;\ntypedef struct ntk_extra ntk_extra;"))

    def test_a_version_part_that_is_missing(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION_PATCH 0\n", ""))

    def test_a_version_that_is_not_its_parts(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020100"))

    def test_a_calling_convention_that_is_not_empty(self):
        self.assert_catches("common", (COMMON, "#else\n#define NTK_CALL\n", "#else\n#define NTK_CALL __attribute__((cdecl))\n"))

    def test_a_system_code_on_android(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020000\n#define NTK_SYSTEM_CODE_E_OUTOFMEMORY 0x8007000E"))

    def test_a_windows_constant_that_is_not_allowed(self):
        self.assert_catches("common", (WINDOWS_COMMON, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020000\n#define NTK_STRAY 1"))

    def test_appendix_a_common_h_is_compared_under_design_only(self):
        self.assert_catches("common", (DESIGN, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020001"),
                            headers=False, arguments=("--design-only",))

    # --- symbols ------------------------------------------------------------

    @staticmethod
    def fake_nm(extra=(), dropped=()):
        """A stand-in for llvm-nm that prints the functions of 8.2 as defined dynamic symbols."""
        def prepare(root):
            design = (root / DESIGN).read_text(encoding="utf-8")
            code = c_abi_contract_common.appendix_code(design)
            names = sorted(set(c_abi_contract_common.declarations(code)["function"]) - set(dropped))
            names += ["JNI_OnLoad", *extra]
            listing = root / "symbols.txt"
            listing.write_text("".join(f"0000000000001000 T {n}\n" for n in names), encoding="utf-8")
            library = root / "libntk.so"
            library.write_bytes(b"\x7fELF")
            nm = root / "fake_nm.py"
            nm.write_text(textwrap.dedent(f"""\
                #!{sys.executable}
                import sys
                sys.stdout.write(open({str(listing)!r}).read())
                """), encoding="utf-8")
            nm.chmod(nm.stat().st_mode | stat.S_IXUSR)
            return ["--library", str(library), "--nm", str(nm)]
        return prepare

    def test_symbols_that_match_8_2(self):
        output = self.assert_passes(before=self.fake_nm())
        self.assertIn("OK   symbols", output)

    def test_an_exported_symbol_8_2_lacks(self):
        self.assert_catches("symbols", before=self.fake_nm(extra=("ntk_internal_helper",)))

    def test_a_function_the_library_does_not_export(self):
        self.assert_catches("symbols", before=self.fake_nm(dropped=("ntk_share_file",)))

    def test_a_library_that_is_missing(self):
        self.assert_catches("symbols", arguments=("--library", os.devnull + ".missing"))


if __name__ == "__main__":
    unittest.main()
