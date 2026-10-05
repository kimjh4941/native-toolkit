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
import re
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
import check_c_abi_contract_android  # noqa: E402

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
CLIPBOARD_ERROR_CODE = f"{KOTLIN_PACKAGE}/clipboard/domain/error/ClipboardErrorCode.kt"


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

    def test_design_only_once_a_header_exists_fails(self):
        self.assert_catches("design only", arguments=("--design-only",))

    def test_a_missing_windows_common_h_fails(self):
        self.assert_catches("common", removed=(WINDOWS_COMMON,))

    def test_missing_kotlin_sources_fail(self):
        def remove(root):
            shutil.rmtree(root / KOTLIN)
            return []
        self.assert_catches("the Kotlin sources", before=remove)

    def test_an_unknown_argument_is_a_usage_error(self):
        output, code = self.run_checker(arguments=("--libary", "x"))
        self.assertEqual(code, 2, output)

    def test_an_option_without_its_value_is_a_usage_error(self):
        output, code = self.run_checker(arguments=("--library",))
        self.assertEqual(code, 2, output)

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

    def test_a_row_whose_8_1_count_is_wrong(self):
        self.assert_catches("functions", (DESIGN, "| 操作（OP-01〜OP-12） | 8.1 の 12 関数 | 12 |",
                                          "| 操作（OP-01〜OP-12） | 8.1 の 10 関数 | 12 |"))

    def test_a_heading_that_disagrees_with_the_total(self):
        self.assert_catches("functions", (DESIGN, "### 8.2 公開する関数の全体（155）", "### 8.2 公開する関数の全体（150）"))

    # --- signatures ---------------------------------------------------------

    def test_a_parameter_type_that_changed(self):
        self.assert_catches("signatures", (CLIPBOARD, "ntk_clipboard_error NTK_CALL ntk_clipboard_has_clip(int32_t* out_has_clip);",
                                           "ntk_clipboard_error NTK_CALL ntk_clipboard_has_clip(int64_t* out_has_clip);"))

    def test_a_typedef_that_changed(self):
        self.assert_catches("signatures", (CLIPBOARD, "typedef int32_t ntk_clipboard_error;", "typedef int64_t ntk_clipboard_error;"))

    def test_a_declaration_inside_an_if(self):
        self.assert_catches("signatures", (CLIPBOARD, "ntk_clipboard_error NTK_CALL ntk_clipboard_clear(void);",
                                           "#if defined(NTK_EXPERIMENTAL)\nntk_clipboard_error NTK_CALL ntk_clipboard_clear(void);\n#endif"))

    def test_another_packing(self):
        self.assert_catches("signatures", (CLIPBOARD, "#pragma pack(push, 8)", "#pragma pack(push, 4)"))

    def test_a_struct_outside_the_packing(self):
        self.assert_catches("signatures", (CLIPBOARD, "#pragma pack(push, 8)\n", ""), (CLIPBOARD, "#pragma pack(pop)\n", ""))

    # --- operations and Kotlin ----------------------------------------------

    def test_chapter_9_missing_an_operation(self):
        self.assert_catches("operations", (DESIGN, "| OP-05 | `clearPrimaryClip`（同期）", "| OP-5x | `clearPrimaryClip`（同期）"))

    def test_8_1_naming_a_function_appendix_a_lacks(self):
        self.assert_catches("operations", (DESIGN, "| `ntk_clipboard_clear()` |", "| `ntk_clipboard_clear_all()` |"))

    def test_a_kotlin_entry_that_was_renamed(self):
        self.assert_catches("kotlin", (CLIPBOARD_MANAGER, "fun copyPlainText(", "fun copyPlain("))

    def test_a_kotlin_entry_left_only_in_a_comment(self):
        self.assert_catches("kotlin", (CLIPBOARD_MANAGER, "    fun copyPlainText(", "    // fun copyPlainText(x: Int) {}\n    fun copyPlain("))

    def test_a_kotlin_entry_on_another_type_of_the_same_file(self):
        self.assert_catches("kotlin", (CLIPBOARD_MANAGER, "    fun copyPlainText(", "    fun copyPlain("),
                            (CLIPBOARD_MANAGER, "\nclass AndroidClipboardManager", "\nprivate class Other {\n    fun copyPlainText() {}\n}\n\nclass AndroidClipboardManager"))

    def test_two_kotlin_types_with_the_name(self):
        def duplicate(root):
            (root / KOTLIN_PACKAGE / "Duplicate.kt").write_text(
                "package other\n\nclass AndroidClipboardManager {\n    fun copyPlainText() {}\n}\n", encoding="utf-8")
            return []
        self.assert_catches("kotlin", before=duplicate)

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

    def test_the_last_event_row_removed(self):
        self.assert_catches("behaviours", (DESIGN, "| EV-05 | Share で選ばれたアプリ | 自発のイベント | イベント | SH-02 | OP-53 |\n", ""))

    def test_the_addition_row_removed(self):
        self.assert_catches("behaviours", (DESIGN, "| PR-01 | 通知の権限の要求（ブリッジに無い。README D-5） | 操作と完了 | 受け付けた後の完了 | - | OP-38、OP-39 |\n", ""))

    def test_a_completion_row_called_an_event(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-11 | Alert を出す | 操作と完了 | 受け付けた後の完了 |",
                                           "| BH-11 | Alert を出す | 操作と完了 | イベント |"))

    def test_an_event_row_called_a_registration(self):
        self.assert_catches("behaviours", (DESIGN, "| EV-01 | クリップボードの変更 | 自発のイベント | イベント |",
                                           "| EV-01 | クリップボードの変更 | 自発のイベント | 登録と解除 |"))

    def test_a_completion_row_with_a_sync_function(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-11 | Alert を出す | 操作と完了 | 受け付けた後の完了 | DL-08 | OP-13 |",
                                           "| BH-11 | Alert を出す | 操作と完了 | 受け付けた後の完了 | DL-08 | OP-05、OP-13 |"))

    def test_a_sync_row_called_posted(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-01 | テキストをコピーする | 操作 | 同期の結果 |",
                                           "| BH-01 | テキストをコピーする | 操作 | 受け付けだけ（main に積む） |"))

    def test_a_listener_no_row_names(self):
        self.assert_catches("behaviours", (DESIGN, "| EV-01 | クリップボードの変更 | 自発のイベント | イベント | CL-04 | OP-11 |",
                                           "| EV-01 | クリップボードの変更 | 自発のイベント | イベント | CL-04 | OP-53 |"),
                            (DESIGN, "| CL-04、CL-05 | OP-11、OP-12 |", "| CL-04、CL-05 | OP-53、OP-54 |"))

    def test_a_readme_range_that_disagrees(self):
        self.assert_catches("behaviours", (README, "RG-01〜RG-06", "RG-01〜RG-07"))

    def test_a_full_width_tilde_still_reads_as_a_range(self):
        self.assert_passes((DESIGN, "| CL-14、CL-15 | OP-09、OP-10 |", "| CL-14、CL-15 | OP-09～OP-10 |"))

    # --- values -------------------------------------------------------------

    def test_a_header_value_the_table_disagrees_with(self):
        self.assert_catches("tables of chapter 11", (SHARE, "NTK_SHARE_ERROR_NO_SHARE_TARGET = 8,", "NTK_SHARE_ERROR_NO_SHARE_TARGET = 18,"))

    def test_a_shared_value_one_feature_moved(self):
        self.assert_catches("0 to 5", (DESIGN, "| 4 | `UNKNOWN` |", "| 4 | `UNKNOWN_ERROR` |"))

    def test_a_table_naming_a_value_twice(self):
        self.assert_catches("tables of chapter 11", (DESIGN, "| 4 | `NTK_ANDROID_ERROR_IN_PROGRESS` |",
                                                     "| 4 | `NTK_ANDROID_ERROR_IN_PROGRESS` |\n| 4 | `IN_PROGRESS` |"))

    def test_a_kotlin_enum_order_that_changed(self):
        self.assert_catches("Kotlin declaration order", (CLIPBOARD_ERROR_CODE, "    EMPTY_ITEMS,", "    EMPTY_ITEMZ,"))

    def test_a_table_naming_a_value_twice_the_same_way(self):
        self.assert_catches("tables of chapter 11", (DESIGN, "| 4 | `NTK_ANDROID_ERROR_IN_PROGRESS` |",
                                                     "| 4 | `NTK_ANDROID_ERROR_IN_PROGRESS` |\n| 4 | `NTK_ANDROID_ERROR_IN_PROGRESS` |"))

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

    def test_an_android_declaration_that_differs(self):
        self.assert_catches("common", (COMMON, "size_t         NTK_CALL ntk_bytes_size(const ntk_bytes* b);",
                                       "uint32_t       NTK_CALL ntk_bytes_size(const ntk_bytes* b);"))

    def test_an_incomplete_type_only_windows_has(self):
        self.assert_catches("common", (WINDOWS_COMMON, "typedef struct ntk_bytes ntk_bytes;", "typedef struct ntk_bytes ntk_bytes;\ntypedef struct ntk_extra ntk_extra;"))

    def test_a_windows_version_that_is_not_its_parts(self):
        self.assert_catches("common", (WINDOWS_COMMON, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020001"))

    def test_a_version_part_defined_in_two_branches(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION_PATCH 0\n",
                                       "#if BAD_ABI\n#define NTK_VERSION_PATCH 0\n#else\n#define NTK_VERSION_PATCH 1\n#endif\n"))

    def test_a_calling_convention_redefined_after_the_block(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION_MAJOR 2", "#undef NTK_CALL\n#define NTK_CALL __attribute__((stdcall))\n#define NTK_VERSION_MAJOR 2"))

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

    def test_versioned_symbols_and_headings_are_read_as_names(self):
        def prepare(root):
            arguments = self.fake_nm()(root)
            listing = root / "symbols.txt"
            lines = listing.read_text(encoding="utf-8").splitlines()
            listing.write_text("libntk.so:\n" + "".join(line + "@@LIBNTK_2\n" for line in lines), encoding="utf-8")
            return arguments
        output = self.assert_passes(before=prepare)
        self.assertIn("OK   symbols", output)

    def test_an_nm_that_does_not_exist(self):
        def prepare(root):
            arguments = self.fake_nm()(root)
            arguments[-1] = str(root / "no-nm")
            return arguments
        self.assert_catches("symbols", before=prepare)

    def test_a_library_that_is_missing(self):
        self.assert_catches("symbols", arguments=("--library", os.devnull + ".missing"))


if __name__ == "__main__":
    unittest.main()


class HeaderShape(unittest.TestCase):
    """directive_problems against one header of Appendix A, broken one way at a time."""

    @classmethod
    def setUpClass(cls):
        design = (ROOT / DESIGN).read_text(encoding="utf-8")
        cls.clipboard = c_abi_contract_common.appendix_headers(design)["Clipboard.h"]
        cls.common = c_abi_contract_common.appendix_headers(design)["Common.h"]

    def problems(self, old, new, text=None, label="Clipboard.h"):
        text = text or self.clipboard
        self.assertIn(old, text)
        return c_abi_contract_common.directive_problems(label, text.replace(old, new, 1))

    def test_the_headers_of_appendix_a_have_the_shape(self):
        self.assertEqual(c_abi_contract_common.directive_problems("Clipboard.h", self.clipboard), [])
        self.assertEqual(c_abi_contract_common.directive_problems("Common.h", self.common), [])

    def test_extra_whitespace_in_a_pragma_is_read_not_raised(self):
        self.assertEqual(self.problems("#pragma pack(push, 8)", "#  pragma  pack( push,8 )"), [])

    def test_a_guard_that_is_never_closed(self):
        text = self.clipboard.rstrip()
        self.assertTrue(text.endswith("#endif"))
        self.assertNotEqual(c_abi_contract_common.directive_problems("Clipboard.h", text[:-len("#endif")]), [])

    def test_no_extern_c(self):
        text = re.sub(r"#ifdef __cplusplus\n.*?#endif\n", "", self.clipboard, flags=re.S)
        self.assertNotEqual(c_abi_contract_common.directive_problems("Clipboard.h", text), [])

    def test_a_declaration_after_extern_c_closes(self):
        text = self.clipboard.rstrip()
        cut = text.rindex("#endif")
        text = text[:cut] + "int NTK_CALL ntk_clipboard_late(void);\n" + text[cut:]
        self.assertTrue(any("outside extern" in p for p in c_abi_contract_common.directive_problems("Clipboard.h", text)))

    def test_a_pop_inside_a_struct(self):
        problems = self.problems("#pragma pack(pop)\n", "")
        self.assertNotEqual(problems, [])
        text = self.clipboard.replace("#pragma pack(pop)\n", "", 1)
        first_field = re.search(r"typedef struct \w+ \{\n", text).end()
        text = text[:first_field] + "#pragma pack(pop)\n" + text[first_field:]
        self.assertTrue(any("inside a struct" in p for p in c_abi_contract_common.directive_problems("Clipboard.h", text)))


class KotlinReading(unittest.TestCase):

    def test_enum_entries_over_several_lines(self):
        source = "enum class E(val value: Int) {\n    A(\n        1\n    ),\n    B(2);\n\n    fun f() {}\n}\n"
        problems = []
        order = check_c_abi_contract_android.kotlin_order({"E.kt": source}, "E", problems)
        self.assertEqual((order, problems), (["A", "B"], []))

    def test_enum_entries_without_a_semicolon(self):
        problems = []
        order = check_c_abi_contract_android.kotlin_order({"E.kt": "enum class E {\n    A,\n    B\n}\n"}, "E", problems)
        self.assertEqual(order, ["A", "B"])
