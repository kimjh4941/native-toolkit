"""Break each check of the iOS C ABI contract checker and confirm it notices.

Each case copies the files the checker reads into a temporary tree, makes one
small change there, and asserts that the named check fails. The tree's public
headers are written from Appendix A as it stands, so that the cases do not
depend on the comments of the real ones; the capi's sources and the layout test
are the real ones. The real tree is never touched. A case whose own anchor text
is missing fails too, so a case cannot go quiet because the file it edits has
moved on, and every case runs against trees checked to have no failure before
it breaks them, so a name that fails anyway proves nothing.

Run: python3 -m unittest discover -s scripts/tests
"""

import json
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
import unittest.mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_c_abi_contract_ios.py"
sys.path.insert(0, str(ROOT / "scripts"))
import c_abi_contract_common  # noqa: E402
import check_c_abi_contract_ios  # noqa: E402

DESIGN = "artifact/topics/ios-c-abi/designs/2026-11-03-ios-c-abi-c-abi-design-part2.md"
README = "artifact/topics/ios-c-abi/README.md"
SWIFT = "artifact/topics/ios-c-abi/results/swiftinterface/IosLibrary-after-tb0.swiftinterface"
SOURCES = {enumeration: f"ios/IosLibrary/IosLibrary/{feature}/Domain/Model/{enumeration}.swift"
           for enumeration, feature in (("DialogError", "Dialog"), ("NotificationError", "Notification"),
                                        ("ClipboardError", "Clipboard"), ("ShareError", "Share"))}
NUMBERS = "scripts/c_abi_error_numbers.json"
INCLUDE = "ios/IosLibraryCApi/include/NativeToolkitC"
ANDROID_INCLUDE = "android/android_library_capi/src/main/cpp/include/NativeToolkitC"
WINDOWS_COMMON = "windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h"
COMMON = f"{INCLUDE}/Common.h"
CLIPBOARD = f"{INCLUDE}/Clipboard.h"
DIALOG = f"{INCLUDE}/Dialog.h"
SHARE = f"{INCLUDE}/Share.h"
ANDROID_COMMON = f"{ANDROID_INCLUDE}/Common.h"
ANDROID_CLIPBOARD = f"{ANDROID_INCLUDE}/Clipboard.h"
ANDROID_SHARE = f"{ANDROID_INCLUDE}/Share.h"
CAPI_SOURCES = "ios/IosLibraryCApi/IosLibraryCApi"
COMMON_ENTRY = f"{CAPI_SOURCES}/Common/CommonEntry.swift"
NOTIFICATION_ENTRY = f"{CAPI_SOURCES}/Notification/NotificationEntry.swift"
HANDLE_SWIFT = f"{CAPI_SOURCES}/Common/Handle.swift"
MODULE_MAP = f"{CAPI_SOURCES}/module.modulemap"
LAYOUT_TEST = "ios/IosLibraryCApiTests/StructLayoutTests.m"
PROJECT = "ios/IosLibraryCApi/IosLibraryCApi.xcodeproj"
PBXPROJ = f"{PROJECT}/project.pbxproj"
SCHEME = f"{PROJECT}/xcshareddata/xcschemes/IosLibraryCApi.xcscheme"
RECEIVER = f"{CAPI_SOURCES}/Notification/NotificationReceiver.swift"
INSTALL_RESULT = "ios/IosLibrary/IosLibrary/Notification/Domain/Model/NotificationDelegateInstallResult.swift"
NOTIFICATION = f"{INCLUDE}/Notification.h"
NOT_IMPLEMENTED_YET = check_c_abi_contract_ios.NOT_IMPLEMENTED_YET
INCLUDE_BLOCK = "\n".join(check_c_abi_contract_ios.COMMON_INCLUDE)
CLANG = shutil.which("clang")
# compile says SKIP without Xcode, so what it reports can only be tested with it.
XCODE = shutil.which("xcrun")


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


def reports(line, name):
    """Whether a FAIL line is of the named check. One word is the check's ID, at
    the head of the line: 'functions' also appears in the details of others."""
    return line.startswith(f"FAIL {name}:") if " " not in name else name in line


class IosCAbiContractChecker(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # Red before anything is broken would make every assert_catches of that
        # check pass whatever it breaks.
        for arguments, headers in (((), True), (("--design-only",), False)):
            output, code = cls.run_tree(headers=headers, arguments=arguments)
            if failures(output) or code != 0:
                raise AssertionError(f"the unbroken tree fails with {arguments}: {output}")

    def run_checker(self, edits=(), removed=(), headers=True, arguments=(), before=None, env=None):
        return self.run_tree(edits, removed, headers, arguments, before, env)

    @staticmethod
    def run_tree(edits=(), removed=(), headers=True, arguments=(), before=None, env=None):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for fragment in (DESIGN, README, SWIFT, NUMBERS, WINDOWS_COMMON, *SOURCES.values()):
                destination = root / fragment
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / fragment, destination)
            shutil.copytree(ROOT / ANDROID_INCLUDE, root / ANDROID_INCLUDE)
            if headers:
                design = (ROOT / DESIGN).read_text(encoding="utf-8")
                for name, code in c_abi_contract_common.appendix_headers(design).items():
                    path = root / INCLUDE / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(code, encoding="utf-8")
                shutil.copytree(ROOT / CAPI_SOURCES, root / CAPI_SOURCES)
                shutil.copytree(ROOT / PROJECT, root / PROJECT, ignore=shutil.ignore_patterns("xcuserdata"))
                (root / INSTALL_RESULT).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / INSTALL_RESULT, root / INSTALL_RESULT)
                (root / LAYOUT_TEST).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / LAYOUT_TEST, root / LAYOUT_TEST)
            for fragment in removed:
                (root / fragment).unlink()
            for fragment, old, new in edits:
                path = root / fragment
                text = path.read_text(encoding="utf-8")
                if old not in text:
                    raise AssertionError(f"the test's own anchor is missing from {fragment}: {old}")
                path.write_text(text.replace(old, new, 1), encoding="utf-8")
            extra = list(arguments)
            if before:
                extra += before(root)
            finished = subprocess.run([sys.executable, str(CHECKER), "--root", str(root), *extra],
                                      capture_output=True, text=True, encoding="utf-8", env=env)
            return finished.stdout, finished.returncode

    def assert_catches(self, name, *edits, removed=(), headers=True, arguments=(), before=None):
        output, code = self.run_checker(edits, removed, headers, arguments, before)
        reported = failures(output)
        self.assertTrue(any(reports(line, name) for line in reported),
                        f"breaking {name!r} was not reported; failures were {reported}")
        self.assertEqual(code, 1, "a failure must make the exit status 1")

    def assert_catches_in_design(self, name, *edits):
        """The same, with Appendix A in place of the headers."""
        self.assert_catches(name, *edits, headers=False, arguments=("--design-only",))

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
        self.assertIn("(134 functions)", output)
        # 46 operations less the three the receiver answers (OP-16, OP-17, OP-44):
        # the rows that say 同上 are compared too.
        self.assertIn("(43 entries)", output)
        self.assertIn(f"({134 - len(NOT_IMPLEMENTED_YET)} of 134, {len(NOT_IMPLEMENTED_YET)} not implemented yet)", output)
        for check in ("public", "modulemap", "layout", "settings", "install"):
            self.assertIn(f"OK   {check}:", output)
        self.assertIn("SKIP complete", output)

    def test_design_only_reads_appendix_a_in_place_of_the_headers(self):
        output = self.assert_passes(headers=False, arguments=("--design-only",))
        self.assertIn("SKIP signatures", output)
        for check in ("entries", "public", "modulemap", "compile", "layout", "settings", "install"):
            self.assertIn(f"SKIP {check}:", output)
        self.assertIn("(134 functions)", output)

    def test_a_missing_header_fails_rather_than_skips(self):
        self.assert_catches("the public header Share.h", removed=(SHARE,))

    def test_a_header_appendix_a_does_not_have(self):
        def add(root):
            (root / INCLUDE / "Ios.h").write_text("/* new */\n", encoding="utf-8")
            return []
        self.assert_catches("the public header Ios.h", before=add)

    def test_no_headers_without_design_only_fails(self):
        self.assert_catches("functions", headers=False)
        self.assert_catches("ascii", headers=False)
        self.assert_catches("entries and public", headers=False)
        self.assert_catches("modulemap", headers=False)
        self.assert_catches("layout", headers=False)
        if XCODE:
            self.assert_catches("compile", headers=False)

    def test_design_only_once_a_header_exists_fails(self):
        self.assert_catches("design only", arguments=("--design-only",))

    def test_design_only_with_a_header_elsewhere_in_the_module_fails(self):
        for fragment in ("Sources/NativeToolkitC/Common.h", "Sources/Common.h"):
            with self.subTest(fragment=fragment):
                def stray(root):
                    path = root / "ios/IosLibraryCApi" / fragment
                    path.parent.mkdir(parents=True)
                    path.write_text("/* moved */\n", encoding="utf-8")
                    return []
                self.assert_catches("design only", headers=False, arguments=("--design-only",), before=stray)

    def test_a_missing_design_fails(self):
        self.assert_catches("the C ABI design", removed=(DESIGN,))

    def test_a_missing_readme_fails(self):
        self.assert_catches("the README", removed=(README,))

    def test_an_unknown_argument_is_a_usage_error(self):
        output, code = self.run_checker(arguments=("--libary", "x"))
        self.assertEqual(code, 2, output)

    def test_an_option_without_its_value_is_a_usage_error(self):
        output, code = self.run_checker(arguments=("--library",))
        self.assertEqual(code, 2, output)

    # --- functions ----------------------------------------------------------

    def test_a_header_function_8_2_does_not_name(self):
        self.assert_catches("functions", (CLIPBOARD, "ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint64_t request_id);",
                                          "ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint64_t request_id);\n"
                                          "ntk_clipboard_error NTK_CALL ntk_clipboard_undesigned(void);"))

    def test_an_appendix_function_8_2_does_not_name(self):
        self.assert_catches_in_design("functions", (DESIGN, "ntk_dialog_error NTK_CALL ntk_dialog_cancel(uint64_t request_id);",
                                                    "ntk_dialog_error NTK_CALL ntk_dialog_cancel(uint64_t request_id);\n"
                                                    "ntk_dialog_error NTK_CALL ntk_dialog_undesigned(void);"))

    def test_a_function_of_8_2_appendix_a_lacks(self):
        self.assert_catches_in_design("functions", (DESIGN, "ntk_dialog_error NTK_CALL ntk_dialog_cancel(uint64_t request_id);\n", ""))

    def test_a_total_that_no_longer_adds_up(self):
        self.assert_catches("functions", (DESIGN, "| 合計 | | | 134 |", "| 合計 | | | 135 |"))

    def test_a_row_of_8_2_that_miscounts(self):
        self.assert_catches("functions", (DESIGN, "`ntk_bytes_data`、`ntk_bytes_size`、`ntk_bytes_free` | 3 |",
                                          "`ntk_bytes_data`、`ntk_bytes_size`、`ntk_bytes_free` | 4 |"))

    def test_a_row_whose_8_1_count_is_wrong(self):
        self.assert_catches("functions", (DESIGN, "| 操作（OP-01〜OP-17） | 8.1 の 17 関数 | 17 |",
                                          "| 操作（OP-01〜OP-17） | 8.1 の 15 関数 | 17 |"))

    def test_a_heading_that_disagrees_with_the_total(self):
        self.assert_catches("functions", (DESIGN, "### 8.2 公開する関数の全体（134）", "### 8.2 公開する関数の全体（130）"))

    def test_a_group_of_8_2_missing_a_function(self):
        self.assert_catches("functions", (DESIGN, "`_notification_id`、`_free`（いずれも `ntk_notification_settings_request` の後に続く） | 2 |",
                                          "`_free`（いずれも `ntk_notification_settings_request` の後に続く） | 1 |"),
                            (DESIGN, "| 合計 | | | 134 |", "| 合計 | | | 133 |"),
                            (DESIGN, "### 8.2 公開する関数の全体（134）", "### 8.2 公開する関数の全体（133）"))

    # --- signatures ---------------------------------------------------------

    def test_a_parameter_type_that_changed(self):
        self.assert_catches("signatures", (CLIPBOARD, "ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint64_t request_id);",
                                           "ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint32_t request_id);"))

    def test_a_typedef_that_changed(self):
        self.assert_catches("signatures", (CLIPBOARD, "typedef int32_t ntk_clipboard_error;", "typedef int64_t ntk_clipboard_error;"))

    def test_a_bit_that_moved(self):
        self.assert_catches("signatures", (CLIPBOARD, "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2", "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 3"))

    def test_a_declaration_inside_an_if(self):
        self.assert_catches("signatures", (CLIPBOARD, "ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint64_t request_id);",
                                           "#if defined(NTK_EXPERIMENTAL)\nntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint64_t request_id);\n#endif"))

    def test_another_packing(self):
        self.assert_catches("signatures", (CLIPBOARD, "#pragma pack(push, 8)", "#pragma pack(push, 4)"))

    def test_a_feature_header_with_only_the_relative_include(self):
        self.assert_catches("signatures", (CLIPBOARD, INCLUDE_BLOCK, '#include "Common.h"'))

    def test_a_feature_header_with_no_include_of_common(self):
        self.assert_catches("signatures", (CLIPBOARD, INCLUDE_BLOCK + "\n", ""))

    def test_an_include_block_with_another_path(self):
        self.assert_catches("signatures", (DIALOG, "__has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)", "__has_include(<NativeToolkitC/Common.h>)"))

    def test_the_include_block_is_not_allowed_in_common_h(self):
        self.assert_catches("signatures", (COMMON, "#include <stddef.h>", INCLUDE_BLOCK + "\n#include <stddef.h>"))

    CANCEL_LOAD = "ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint64_t request_id);\n"

    def test_a_value_the_header_lacks(self):
        self.assert_catches("signatures", (CLIPBOARD, "    NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2,\n", ""))

    def test_a_declaration_moved_into_the_fallback_branch(self):
        # Still declared, so the declarations compare equal; only one branch sees it.
        self.assert_catches("signatures", (CLIPBOARD, self.CANCEL_LOAD, ""),
                            (CLIPBOARD, '#include "Common.h"\n#endif', f'#include "Common.h"\n{self.CANCEL_LOAD}#endif'))

    def test_a_declaration_moved_into_the_framework_branch(self):
        self.assert_catches("signatures", (CLIPBOARD, self.CANCEL_LOAD, ""),
                            (CLIPBOARD, '#include <IosLibraryCApi/NativeToolkitC/Common.h>\n#else', f'#include <IosLibraryCApi/NativeToolkitC/Common.h>\n{self.CANCEL_LOAD}#else'))

    def test_a_declaration_moved_into_the_branch_of_appendix_a(self):
        self.assert_catches_in_design("shape", (DESIGN, self.CANCEL_LOAD, ""),
                                      (DESIGN, '#include "Common.h"\n#endif', f'#include "Common.h"\n{self.CANCEL_LOAD}#endif'))

    def test_the_include_block_inside_extern_c(self):
        self.assert_catches("signatures", (CLIPBOARD, INCLUDE_BLOCK + "\n", ""),
                            (CLIPBOARD, 'extern "C" {\n#endif\n', 'extern "C" {\n#endif\n' + INCLUDE_BLOCK + "\n"))

    def test_the_include_block_inside_extern_c_in_appendix_a(self):
        self.assert_catches_in_design("shape", (DESIGN, INCLUDE_BLOCK + "\n", ""),
                                      (DESIGN, 'extern "C" {\n#endif\n', 'extern "C" {\n#endif\n' + INCLUDE_BLOCK + "\n"))

    def test_an_include_appendix_a_does_not_have(self):
        self.assert_catches("signatures", (CLIPBOARD, "#ifdef __cplusplus", "#include <Foundation/Foundation.h>\n#ifdef __cplusplus"))

    def test_an_include_of_common_outside_the_block(self):
        self.assert_catches("signatures", (CLIPBOARD, "#ifdef __cplusplus", "#include <IosLibraryCApi/NativeToolkitC/Common.h>\n#ifdef __cplusplus"))

    def test_a_second_relative_include_in_appendix_a(self):
        self.assert_catches_in_design("shape", (DESIGN, INCLUDE_BLOCK + "\n", INCLUDE_BLOCK + '\n#include "Common.h"\n'))

    def test_only_the_relative_include_in_appendix_a(self):
        self.assert_catches_in_design("shape", (DESIGN, INCLUDE_BLOCK, '#include "Common.h"'))

    def test_the_include_block_in_the_common_h_of_appendix_a(self):
        self.assert_catches_in_design("shape", (DESIGN, "#include <stddef.h>", INCLUDE_BLOCK + "\n#include <stddef.h>"))

    def test_another_include_form_in_appendix_a(self):
        self.assert_catches_in_design("shape", (DESIGN, "__has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)", "__has_include(<NativeToolkitC/Common.h>)"))

    def test_another_version_whose_parts_agree(self):
        self.assert_catches("signatures", (COMMON, "#define NTK_VERSION_MAJOR 2", "#define NTK_VERSION_MAJOR 3"),
                            (COMMON, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x030000"))

    # What the reading cannot place fails: it is not left out of the comparison.

    def test_a_function_without_ntk_call(self):
        self.assert_catches("signatures", (SHARE, "#ifdef __cplusplus\n}", "ntk_share_error ntk_share_undesigned(void);\n#ifdef __cplusplus\n}"))

    def test_a_variable(self):
        self.assert_catches("signatures", (SHARE, "#ifdef __cplusplus\n}", "extern int ntk_share_global;\n#ifdef __cplusplus\n}"))

    def test_a_struct_without_its_typedef(self):
        self.assert_catches("signatures", (SHARE, "#ifdef __cplusplus\n}", "struct ntk_share_plain { int a; };\n#ifdef __cplusplus\n}"))

    def test_an_inline_function(self):
        self.assert_catches("signatures", (SHARE, "#ifdef __cplusplus\n}", "static inline int ntk_share_inl(void) { return 0; }\n#ifdef __cplusplus\n}"))

    def test_an_enum_value_outside_the_prefix(self):
        self.assert_catches("signatures", (SHARE, "#ifdef __cplusplus\n}", "enum { OTHER_THING = 3 };\n#ifdef __cplusplus\n}"))

    def test_an_enum_value_with_no_initializer(self):
        self.assert_catches("signatures", (SHARE, "NTK_SHARE_ERROR_ACTIVITY_FAILED = 21", "NTK_SHARE_ERROR_ACTIVITY_FAILED = 21,\n    NTK_SHARE_ERROR_NEW_IMPLICIT"))

    def test_an_initializer_that_adds(self):
        self.assert_catches("signatures", (SHARE, "NTK_SHARE_ERROR_ACTIVITY_FAILED = 21", "NTK_SHARE_ERROR_ACTIVITY_FAILED = 21 + 1"))

    def test_a_bit_with_more_after_it(self):
        self.assert_catches("signatures", (CLIPBOARD, "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2", "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2 | 1"))

    def test_a_value_appendix_a_cannot_give(self):
        # The same in both, so nothing differs: it fails because it is not read.
        self.assert_catches("signatures", (DESIGN, "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2", "NTK_CLIPBOARD_PATTERN_NUMBER = (1u << 2)"),
                            (CLIPBOARD, "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2", "NTK_CLIPBOARD_PATTERN_NUMBER = (1u << 2)"))

    def test_appendix_a_with_an_initializer_it_cannot_read(self):
        self.assert_catches_in_design("shape", (DESIGN, "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2", "NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2 | 1"))

    # --- operations ---------------------------------------------------------

    def test_8_1_naming_a_function_appendix_a_lacks(self):
        self.assert_catches("operations", (DESIGN, "| `ntk_clipboard_clear_async(scope, ...)` |", "| `ntk_clipboard_clear_all_async(scope, ...)` |"))

    def test_a_gap_in_the_operations(self):
        self.assert_catches("operations", (DESIGN, "| OP-46 | `IosShareManager", "| OP-47 | `IosShareManager"))

    def test_a_count_of_operations_that_disagrees(self):
        self.assert_catches("operations", (DESIGN, "8.1 の 46 操作", "8.1 の 45 操作"))

    def test_two_operations_naming_one_function(self):
        self.assert_catches("operations", (DESIGN, "| `ntk_clipboard_append_async(content, scope, ...)` |", "| `ntk_clipboard_copy_async(content, scope, ...)` |"))

    # --- the Swift entries of 8.1 -------------------------------------------

    APPEND = "final public func append(_ content: IosLibrary.ClipboardContent, scope: IosLibrary.PasteboardScope = .general, completion:"

    def test_a_swift_entry_that_was_renamed(self):
        self.assert_catches("swift", (SWIFT, self.APPEND, self.APPEND.replace("func append", "func appendItems")))

    def test_a_swift_label_that_changed(self):
        self.assert_catches("swift", (SWIFT, self.APPEND, self.APPEND.replace("completion:", "done:")))

    def test_a_swift_entry_left_only_in_a_comment(self):
        self.assert_catches("swift", (SWIFT, "  @_Concurrency.MainActor final public func stopObserving()",
                                      "  // func stopObserving()\n  @_Concurrency.MainActor final public func stopEverything()"))

    def test_a_swift_entry_on_another_type(self):
        self.assert_catches("swift", (SWIFT, "  @_Concurrency.MainActor final public func stopObserving()", "  @_Concurrency.MainActor final public func stopEverything()"),
                            (SWIFT, "public struct TextInputNotificationAction : Swift.Sendable {",
                             "public struct TextInputNotificationAction : Swift.Sendable {\n  public func stopObserving()"))

    def test_a_swift_entry_only_in_a_nested_type(self):
        self.assert_catches("swift", (SWIFT, "  @_Concurrency.MainActor final public func stopObserving()", "  @_Concurrency.MainActor final public func stopEverything()"),
                            (SWIFT, "  @_Concurrency.MainActor public static let shared: IosLibrary.IosClipboardManager",
                             "  @_Concurrency.MainActor public static let shared: IosLibrary.IosClipboardManager\n"
                             "  public struct Inner {\n    public func stopObserving()\n  }"))

    def test_a_static_entry_only_the_instance_form_keeps(self):
        self.assert_catches("swift", (SWIFT, "  nonisolated public static func cancelLoad(_ box: IosLibrary.RequestBox)\n", ""))

    def test_an_entry_that_is_no_longer_async(self):
        self.assert_catches("swift", (SWIFT, "? = nil)\n  #endif\n  final public func setBadgeCount(_ count: Swift.Int) async throws",
                                      "? = nil)\n  #endif\n  final public func setBadgeCount(_ count: Swift.Int)"))

    def test_a_row_that_says_async_of_a_callback_form(self):
        self.assert_catches("swift", (DESIGN, "`clear(scope:completion:)`", "`clear(scope:completion:) async throws`"))

    def test_a_property_entry_whose_property_is_gone(self):
        self.assert_catches("swift", (SWIFT, "final public var settingsRequests:", "final public var settingsAsks:"))

    def test_a_property_entry_whose_type_lost_the_function(self):
        self.assert_catches("swift", (SWIFT, "final public class NotificationEventHub<Event> where Event : Swift.Sendable {\n  @discardableResult\n"
                                             "  @_Concurrency.MainActor final public func addListener(",
                                      "final public class NotificationEventHub<Event> where Event : Swift.Sendable {\n  @discardableResult\n"
                                      "  @_Concurrency.MainActor final public func add(",))

    def test_a_manager_that_is_gone(self):
        self.assert_catches("swift", (SWIFT, "final public class IosShareManager", "final public class IosSharing"))

    def test_the_same_as_above_rows_read_the_row_above(self):
        self.assert_catches("swift", (DESIGN, "`IosDialogManager.show(_:presenter:requestBox:completion:)`", "`IosDialogManager.show(_:presenter:box:completion:)`"))

    def test_the_same_as_above_under_a_row_with_no_entry(self):
        self.assert_catches("swift", (DESIGN, "| OP-18 | `IosDialogManager.show(_:presenter:requestBox:completion:)` |", "| OP-18 | 同上 |"))

    def test_a_row_of_the_ledger_that_is_not_a_listener(self):
        self.assert_catches("swift", (DESIGN, "| OP-06 | `clear(scope:completion:)` |", "| OP-06 | （受け口の帳簿） |"))

    def test_a_listener_row_called_the_ledger(self):
        # A listener has the shape of a row of the ledger; 8.1's list says it is not one.
        self.assert_catches("swift", (DESIGN, "| OP-42 | `responses.addListener(_:)` |", "| OP-42 | （受け口の帳簿） |"))

    def test_a_list_of_the_ledger_that_disagrees(self):
        self.assert_catches("swift", (DESIGN, "「（受け口の帳簿）」の行は OP-16、OP-17、OP-44", "「（受け口の帳簿）」の行は OP-16、OP-17"))

    def test_a_row_of_the_ledger_listed_that_is_not_a_listener(self):
        self.assert_catches("swift", (DESIGN, "| OP-06 | `clear(scope:completion:)` |", "| OP-06 | （受け口の帳簿） |"),
                            (DESIGN, "「（受け口の帳簿）」の行は OP-16、", "「（受け口の帳簿）」の行は OP-06、OP-16、"))

    def test_no_list_of_the_ledger(self):
        self.assert_catches("swift", (DESIGN, "「（受け口の帳簿）」の行は OP-16、OP-17、OP-44 だけで、Swift の口を呼ばない（2a が読む）。", ""))

    def test_a_swift_entry_left_only_in_a_block_comment(self):
        self.assert_catches("swift", (SWIFT, "  @_Concurrency.MainActor final public func stopObserving()",
                                      "  /*\n  func stopObserving()\n  */\n  @_Concurrency.MainActor final public func stopEverything()"))

    def test_a_row_with_no_entry(self):
        self.assert_catches("swift", (DESIGN, "| OP-06 | `clear(scope:completion:)` |", "| OP-06 | - |"))

    def test_a_row_that_is_not_an_entry(self):
        self.assert_catches("swift", (DESIGN, "| OP-06 | `clear(scope:completion:)` |", "| OP-06 | `clear scope` |"))

    def test_a_missing_swiftinterface_fails(self):
        output, code = self.run_checker(removed=(SWIFT,))
        self.assertEqual(code, 1, output)
        for name in ("swift", "cases"):
            self.assertTrue(any(line.startswith(f"FAIL {name}:") for line in failures(output)), output)

    # --- behaviours ---------------------------------------------------------

    def test_a_behaviour_naming_an_unknown_operation(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-01 | 内容をコピーする | 操作 | 受け付けた後の完了 | CL-01 | OP-01 |",
                                           "| BH-01 | 内容をコピーする | 操作 | 受け付けた後の完了 | CL-01 | OP-99 |"))

    def test_a_behaviour_with_no_operation(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-01 | 内容をコピーする | 操作 | 受け付けた後の完了 | CL-01 | OP-01 |",
                                           "| BH-01 | 内容をコピーする | 操作 | 受け付けた後の完了 | CL-01 | - |"))

    def test_a_kind_its_prefix_does_not_allow(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-01 | 内容をコピーする | 操作 | 受け付けた後の完了 |",
                                           "| BH-01 | 内容をコピーする | 操作 | 同期の結果 |"))

    def test_a_completion_row_called_sync(self):
        self.assert_catches("behaviours", (DESIGN, "| RG-03 | クリップボードの監視の開始 | 登録と解除 | 受け付けた後の完了 |",
                                           "| RG-03 | クリップボードの監視の開始 | 登録と解除 | 同期の結果 |"))

    def test_a_sync_row_called_a_completion(self):
        self.assert_catches("behaviours", (DESIGN, "| RG-05 | delegate を入れる | 登録と解除 | 同期の結果 |",
                                           "| RG-05 | delegate を入れる | 登録と解除 | 受け付けた後の完了 |"))

    def test_an_event_row_called_a_registration(self):
        self.assert_catches("behaviours", (DESIGN, "| EV-01 | クリップボードの変更 | 自発のイベント | イベント |",
                                           "| EV-01 | クリップボードの変更 | 自発のイベント | 登録と解除 |"))

    def test_a_completion_row_with_a_sync_function(self):
        self.assert_catches("behaviours", (DESIGN, "| CL-01 | OP-01 |", "| CL-01 | OP-01、OP-12 |"))

    def test_a_registration_row_that_adds_no_listener(self):
        self.assert_catches("behaviours", (DESIGN, "| CL-13 | OP-16、OP-17 |", "| CL-13 | OP-17 |"))

    def test_an_event_row_naming_only_the_removal(self):
        self.assert_catches("behaviours", (DESIGN, "| - | OP-43、OP-44 |", "| - | OP-44 |"))

    def test_an_operation_count_readme_disagrees_with(self):
        self.assert_catches("behaviours", (README, "| 計 | 43 | 37 | 6 |", "| 計 | 43 | 38 | 6 |"))

    def test_an_event_readme_lists_and_chapter_10_lacks(self):
        self.assert_catches("behaviours", (README, "| 自発のイベント | Clipboard の変更、", "| 自発のイベント | 新しい変更、Clipboard の変更、"))

    def test_a_count_of_the_bridge_that_disagrees(self):
        self.assert_catches("behaviours", (README, "| 計 | 43 | 37 | 6 |", "| 計 | 44 | 37 | 6 |"))

    def test_a_function_of_the_bridge_no_behaviour_names(self):
        self.assert_catches("behaviours", (DESIGN, "| BH-37 | 共有する | 操作 | 受け付けた後の完了 | SH-01 | OP-46 |", "| BH-37 | 共有する | 操作 | 受け付けた後の完了 | - | OP-46 |"))

    def test_a_row_of_the_bridge_that_is_gone(self):
        self.assert_catches("behaviours", (DESIGN, "| SH-01 | `shareContent` |", "| SH-0x | `shareContent` |"))

    def test_a_gap_in_the_ids(self):
        self.assert_catches("behaviours", (DESIGN, "| EV-03 |", "| EV-04 |"))

    def test_a_completion_row_removed_leaves_its_operation_uncounted(self):
        self.assert_catches("behaviours", (DESIGN, "| PR-03 | 起動のきっかけの通知の取得（追加。D-7） | 問い合わせ | 受け付けた後の完了 | - | OP-45 |\n", ""))

    def test_a_sync_row_removed_leaves_its_operation_uncounted(self):
        self.assert_catches("behaviours", (DESIGN, "| PR-01 | Dialog の要求ごとの取り消し（追加。P1-24） | 操作 | 同期の結果 | - | OP-24 |\n", ""))

    def test_a_listener_no_row_names(self):
        self.assert_catches("behaviours", (DESIGN, "| PR-02 | `openSettingsFor` のイベント（追加。P1-10） | 自発のイベント | イベント | - | OP-43、OP-44 |\n", ""))

    def test_an_operation_that_one_behaviour_no_longer_covers(self):
        self.assert_catches("behaviours", (DESIGN, "| NT-12 | OP-34 |", "| NT-12 | OP-33 |"))

    # --- values -------------------------------------------------------------

    def test_a_header_value_the_table_disagrees_with(self):
        self.assert_catches("tables of chapter 11", (SHARE, "NTK_SHARE_ERROR_ACTIVITY_FAILED = 21", "NTK_SHARE_ERROR_ACTIVITY_FAILED = 22"))

    def test_a_table_value_the_appendix_disagrees_with(self):
        self.assert_catches_in_design("tables of chapter 11", (DESIGN, "| 21 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` |", "| 22 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` |"))

    def test_a_table_naming_a_value_twice(self):
        self.assert_catches("tables of chapter 11", (DESIGN, "| 21 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` | `.activityFailed` |",
                                                     "| 21 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` | `.activityFailed` |\n| 21 | `ACTIVITY_FAILED` | x |"))

    def test_a_shared_value_one_table_moved(self):
        self.assert_catches("0 to 5", (DESIGN, "| 4 | `UNKNOWN` |", "| 4 | `UNKNOWN_ERROR` |"))

    def test_a_shared_value_gone_from_every_table_and_header(self):
        # Every side agrees; what fails is that chapter 11 no longer gives 0 to 5.
        edits = [(DESIGN, "| 5 | `OUT_OF_MEMORY` |", "| x | `OUT_OF_MEMORY` |")]
        for feature in ("DIALOG", "NOTIFICATION", "CLIPBOARD", "SHARE"):
            edits.append((DESIGN, f"    NTK_{feature}_ERROR_OUT_OF_MEMORY = 5,\n", ""))
            edits.append((DESIGN, f"| 5 | `NTK_{feature}_ERROR_OUT_OF_MEMORY`", f"| x | `NTK_{feature}_ERROR_OUT_OF_MEMORY`"))
        self.assert_catches_in_design("0 to 5", *edits)

    def test_a_shared_value_each_feature_moved(self):
        for header, feature in ((DIALOG, "DIALOG"), (f"{INCLUDE}/Notification.h", "NOTIFICATION"), (CLIPBOARD, "CLIPBOARD"), (SHARE, "SHARE")):
            with self.subTest(feature=feature):
                self.assert_catches("0 to 5", (header, f"NTK_{feature}_ERROR_UNKNOWN = 4", f"NTK_{feature}_ERROR_FAILED = 4"))

    # --- the cases of the Swift errors --------------------------------------

    # The anchor is a case of the enumeration, in the baseline and in the source.
    ANCHORS = {"DialogError": "case presentationFailed\n", "NotificationError": "case invalidTrigger\n",
               "ClipboardError": "case cancelled\n", "ShareError": "case noValidItems\n"}

    def new_case(self, enumeration, case, attribute=""):
        """The edits that add a case where both the baseline and the source
        declare it, so that only the table can be behind."""
        anchor = self.ANCHORS[enumeration]
        swift = "  case dismissedBySystem\n  case notForeground\n  " + anchor if enumeration == "DialogError" else "  " + anchor
        return ((SWIFT, swift, swift + f"  {attribute}case {case}\n"), (SOURCES[enumeration], anchor, anchor + f"    {attribute}case {case}\n"))

    def test_a_new_case_of_each_error(self):
        for enumeration in SOURCES:
            with self.subTest(enumeration=enumeration):
                self.assert_catches("does not name", *self.new_case(enumeration, "somethingNew(Swift.String)"))

    def test_a_case_with_labels_in_its_values_is_read_by_its_name(self):
        self.assert_catches("does not name ShareError.tooBig", *self.new_case("ShareError", "tooBig(size: Swift.Int, limit: Swift.Int)"))

    def test_a_case_behind_an_attribute_on_its_line(self):
        self.assert_catches("does not name ShareError.hiddenCase", *self.new_case("ShareError", "hiddenCase", "@available(iOS 99, *) "))

    def test_a_case_only_the_source_has(self):
        self.assert_catches("retake the baseline", (SOURCES["ClipboardError"], "case cancelled\n", "case cancelled\n    case fromTheSource\n"))

    def test_a_case_only_the_baseline_has(self):
        self.assert_catches("retake the baseline", (SWIFT, "  case noValidItems\n", "  case noValidItems\n  case fromTheBaseline\n"))

    def test_a_missing_source_fails(self):
        self.assert_catches("cases", removed=(SOURCES["ShareError"],))

    def test_a_case_the_table_names_and_the_enumeration_lost(self):
        self.assert_catches("which ShareError does not have", (SWIFT, "  case noValidItems\n", ""),
                            (SOURCES["ShareError"], "case noValidItems\n", ""))

    def test_a_case_written_with_no_dot_the_enumeration_lacks(self):
        self.assert_catches("which ClipboardError does not have", (DESIGN, "`CLIPBOARD_EMPTY_CONTENT`（`emptyContent`）", "`CLIPBOARD_EMPTY_CONTENT`（`emptyContent`、`emptyContents`）"))

    def test_a_name_written_like_a_case_that_never_was(self):
        self.assert_catches("cases", (DESIGN, "| 21 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` | `.activityFailed` |", "| 21 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` | `.activityFailed`、`.neverExisted` |"))

    def test_a_table_that_lost_a_case(self):
        self.assert_catches("cases", (DESIGN, "| 19 | `NTK_SHARE_ERROR_SHOW_FAILED` | `.presentationFailed` |",
                                      "| 19 | `NTK_SHARE_ERROR_SHOW_FAILED` | 表示の失敗 |"))

    def test_a_case_named_only_in_another_table(self):
        # `.canceled` is in 11.1; that does not put it in the table of ShareError.
        self.assert_catches("does not name ShareError.canceled", *self.new_case("ShareError", "canceled"))

    def test_a_case_that_only_contains_a_cited_name(self):
        self.assert_catches("does not name DialogError.cancel", *self.new_case("DialogError", "cancel"))

    def test_a_case_written_with_another_type(self):
        self.assert_catches("cases", (DESIGN, "`DialogError.invalidRequest`", "`ShareError.invalidRequest`"))

    def test_a_case_named_outside_the_table_column(self):
        self.assert_catches("cases", (DESIGN, "| `.presentationFailed` |\n\n欠番: 9", "| 表示の失敗 |\n\n欠番: 9 `.presentationFailed`"))

    def test_a_case_named_in_the_name_column(self):
        self.assert_catches("cases", (DESIGN, "| 19 | `NTK_SHARE_ERROR_SHOW_FAILED` | `.presentationFailed` |",
                                      "| 19 | `NTK_SHARE_ERROR_SHOW_FAILED`、`.presentationFailed` | 表示の失敗 |"))

    def test_an_enumeration_that_is_gone(self):
        self.assert_catches("cases", (SWIFT, "public enum ShareError :", "public enum ShareFailure :"))

    def test_the_order_of_the_cases_is_not_compared(self):
        # P2-9 (7): the Swift order is not tied to the C numbers.
        self.assert_passes((SWIFT, "  case canceled\n  case dismissedBySystem\n", "  case dismissedBySystem\n  case canceled\n"))

    # --- the table of numbers (P1-7) ----------------------------------------

    def test_a_number_the_table_moved(self):
        self.assert_catches("numbers", (NUMBERS, '"SHOW_FAILED": 10', '"SHOW_FAILED": 11'))

    def test_an_ios_name_the_table_lacks(self):
        self.assert_catches("numbers", (SHARE, "NTK_SHARE_ERROR_ACTIVITY_FAILED = 21", "NTK_SHARE_ERROR_ACTIVITY_DIED = 21"))

    def test_an_ios_number_used_for_another_name(self):
        self.assert_catches_in_design("numbers", (DESIGN, "NTK_CLIPBOARD_ERROR_EMPTY_PATTERNS = 12", "NTK_CLIPBOARD_ERROR_EMPTY_PATTERNS = 10"))

    def test_an_android_number_the_table_disagrees_with(self):
        self.assert_catches("numbers", (ANDROID_SHARE, "NTK_SHARE_ERROR_NO_SHARE_TARGET = 8", "NTK_SHARE_ERROR_NO_SHARE_TARGET = 18"))

    def test_an_android_name_the_table_lacks(self):
        self.assert_catches("numbers", (ANDROID_CLIPBOARD, "NTK_CLIPBOARD_ERROR_SECURITY = 11", "NTK_CLIPBOARD_ERROR_SECURITY = 11,\n    NTK_CLIPBOARD_ERROR_NEW = 30"))

    def test_an_android_value_taking_a_number_ios_uses(self):
        self.assert_catches("numbers", (ANDROID_CLIPBOARD, "NTK_CLIPBOARD_ERROR_SECURITY = 11", "NTK_CLIPBOARD_ERROR_SECURITY = 11,\n    NTK_CLIPBOARD_ERROR_NEW = 12"))

    def test_a_constant_whose_feature_has_an_underscore(self):
        self.assert_catches("numbers", (ANDROID_SHARE, "NTK_SHARE_ERROR_NO_SHARE_TARGET = 8", "NTK_SHARE_ERROR_NO_SHARE_TARGET = 8,\n    NTK_SHARE_X_ERROR_Y = 30"))

    def test_an_android_value_with_no_initializer(self):
        self.assert_catches("numbers", (ANDROID_SHARE, "NTK_SHARE_ERROR_NO_SHARE_TARGET = 8", "NTK_SHARE_ERROR_NO_SHARE_TARGET = 8,\n    NTK_SHARE_ERROR_IMPLICIT"))

    def test_a_name_neither_os_declares(self):
        self.assert_catches("numbers", (NUMBERS, '"SHOW_FAILED": 10', '"SHOW_FAILED": 10,\n    "NEVER_DECLARED": 11'))

    def test_a_table_that_gives_a_number_two_names(self):
        self.assert_catches("numbers", (NUMBERS, '"SHOW_FAILED": 10', '"SHOW_FAILED": 10,\n    "SHOWN_FAILED": 10'))

    def test_a_table_that_is_not_json(self):
        self.assert_catches("numbers", (NUMBERS, '"SHOW_FAILED": 10', '"SHOW_FAILED": ten'))

    def test_a_missing_table_fails(self):
        self.assert_catches("numbers", removed=(NUMBERS,))

    def test_a_missing_android_header_fails_the_table(self):
        self.assert_catches("numbers", removed=(ANDROID_SHARE,))

    def test_the_android_only_enumeration_is_not_in_the_table(self):
        output = self.assert_passes()
        self.assertTrue((ROOT / ANDROID_INCLUDE / "Android.h").exists())
        self.assertIn("OK   numbers", output)

    # --- names and ASCII ----------------------------------------------------

    def test_a_function_named_against_the_rules(self):
        self.assert_catches("names", (CLIPBOARD, "ntk_clipboard_cancel_load(", "ntk_clipboard_cancelLoad("))

    def test_a_constant_in_the_wrong_header(self):
        self.assert_catches("names", (SHARE, "NTK_SHARE_ERROR_NONE = 0,", "NTK_SHARE_ERROR_NONE = 0,\n    NTK_CLIPBOARD_STRAY = 99,"))

    def test_a_completion_without_async(self):
        self.assert_catches("a function ends in _async", (SHARE, "ntk_share_content_async(", "ntk_share_content("))

    def test_a_sync_function_with_async(self):
        self.assert_catches("a function ends in _async", (DIALOG, "ntk_dialog_cancel(", "ntk_dialog_cancel_async("))

    def test_a_header_that_is_not_ascii(self):
        self.assert_catches("ascii", (CLIPBOARD, "#define NATIVETOOLKITC_CLIPBOARD_H", "#define NATIVETOOLKITC_CLIPBOARD_H /* — */"))

    def test_appendix_a_that_is_not_ascii(self):
        self.assert_catches_in_design("ascii", (DESIGN, "#define NATIVETOOLKITC_CLIPBOARD_H", "#define NATIVETOOLKITC_CLIPBOARD_H /* — */"))

    # --- Common.h across the three OSes (part 1, 5.2) -----------------------

    def test_an_ios_declaration_that_differs(self):
        self.assert_catches("common", (COMMON, "size_t         NTK_CALL ntk_bytes_size(const ntk_bytes* b);",
                                       "uint32_t       NTK_CALL ntk_bytes_size(const ntk_bytes* b);"))

    def test_an_android_declaration_that_differs(self):
        self.assert_catches("common", (ANDROID_COMMON, "size_t         NTK_CALL ntk_bytes_size(const ntk_bytes* b);",
                                       "uint32_t       NTK_CALL ntk_bytes_size(const ntk_bytes* b);"))

    def test_a_windows_declaration_that_differs(self):
        self.assert_catches("common", (WINDOWS_COMMON, "size_t      NTK_CALL ntk_string_size(const ntk_string* s);",
                                       "uint32_t    NTK_CALL ntk_string_size(const ntk_string* s);"))

    def test_an_incomplete_type_only_ios_has(self):
        self.assert_catches("common", (COMMON, "typedef struct ntk_bytes ntk_bytes;", "typedef struct ntk_bytes ntk_bytes;\ntypedef struct ntk_extra ntk_extra;"))

    def test_a_declaration_ios_lacks(self):
        self.assert_catches("common", (COMMON, "uint32_t NTK_CALL ntk_last_system_code(void);\n", ""))

    def test_a_version_that_is_not_its_parts(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020100"))

    def test_a_version_part_that_is_missing(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION_PATCH 0\n", ""))

    def test_a_calling_convention_that_is_not_empty(self):
        self.assert_catches("common", (COMMON, "#else\n#define NTK_CALL\n", "#else\n#define NTK_CALL __attribute__((cdecl))\n"))

    def test_a_calling_convention_under_another_guard(self):
        self.assert_catches("common", (COMMON, "#if defined(_MSC_VER)", "#if defined(_WIN32)"))

    def test_a_system_code_on_ios(self):
        self.assert_catches("common", (COMMON, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020000\n#define NTK_SYSTEM_CODE_E_OUTOFMEMORY 0x8007000E"))

    def test_appendix_a_common_h_is_compared_under_design_only(self):
        self.assert_catches_in_design("common", (DESIGN, "#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020001"))

    def test_a_missing_windows_common_h_fails(self):
        self.assert_catches("common", removed=(WINDOWS_COMMON,))

    def test_a_missing_android_common_h_fails(self):
        self.assert_catches("common", removed=(ANDROID_COMMON,))

    # --- entries (H = E, less what is not implemented yet) --------------------

    ENTRY_ANCHOR = "@c @implementation\npublic func ntk_notification_install"
    LISTED = NOT_IMPLEMENTED_YET[0]

    def test_an_entry_for_a_function_still_listed_as_not_implemented(self):
        self.assert_catches("entries", (NOTIFICATION_ENTRY, self.ENTRY_ANCHOR,
                                        f"@c @implementation public func {self.LISTED}() {{}}\n{self.ENTRY_ANCHOR}"))

    def test_a_function_with_no_entry_that_is_not_listed(self):
        self.assert_catches("entries", (COMMON_ENTRY, "@c @implementation\npublic func ntk_bytes_free(_ b: OpaquePointer?) {\n    Handle.free(b)\n}\n", ""))

    def test_a_listed_function_that_left_the_headers(self):
        output, code = self.run_checker([(SHARE, "void        NTK_CALL ntk_share_result_free(ntk_share_result* result);", "")])
        line = next((l for l in failures(output) if reports(l, "entries")), "")
        self.assertIn("ntk_share_result_free is in NOT_IMPLEMENTED_YET but not in the headers", line)
        self.assertEqual(code, 1)

    def test_an_entry_the_headers_do_not_declare(self):
        self.assert_catches("entries", (NOTIFICATION_ENTRY, self.ENTRY_ANCHOR,
                                        f"@c @implementation public func ntk_helper() {{}}\n{self.ENTRY_ANCHOR}"))

    def test_an_entry_that_lost_public_is_not_an_entry(self):
        self.assert_catches("entries", (COMMON_ENTRY, "public func ntk_version()", "func ntk_version()"))

    def test_an_entry_that_lost_implementation_is_not_an_entry(self):
        edit = (COMMON_ENTRY, "@c @implementation\npublic func ntk_version()", "@c\npublic func ntk_version()")
        self.assert_catches("entries", edit)
        self.assert_catches("public", edit)

    def test_an_entry_on_several_lines_or_elsewhere_in_the_module_is_an_entry(self):
        self.assert_passes((COMMON_ENTRY, "@c @implementation\npublic func ntk_version()", "@c\n@implementation\npublic\nfunc ntk_version()"))
        def moved(root):
            path = root / NOTIFICATION_ENTRY
            text = path.read_text(encoding="utf-8")
            target = root / "ios/IosLibraryCApi/Elsewhere/Moved.swift"
            target.parent.mkdir()
            target.write_text(text, encoding="utf-8")
            path.unlink()
            return []
        self.assert_passes(before=moved)

    def test_a_comment_or_a_string_is_not_an_entry(self):
        comment = f"// @c @implementation public func {self.LISTED}() {{}}\n/* @c @implementation public func {self.LISTED}() {{}} */\n"
        literal = f'let text = "@c @implementation public func {self.LISTED}()"\n'
        self.assert_passes((NOTIFICATION_ENTRY, self.ENTRY_ANCHOR, comment + literal + self.ENTRY_ANCHOR))
        # And a commented-out entry is no entry.
        self.assert_catches("entries", (COMMON_ENTRY, "@c @implementation\npublic func ntk_version() -> UInt32 {\n    UInt32(NTK_VERSION)\n}\n",
                                        "// @c @implementation\n// public func ntk_version() -> UInt32 {\n"))

    def test_no_swift_sources(self):
        def remove(root):
            shutil.rmtree(root / CAPI_SOURCES / "Common")
            shutil.rmtree(root / CAPI_SOURCES / "Notification")
            return []
        self.assert_catches("entries and public", before=remove)

    def test_a_function_listed_twice(self):
        recorded = []
        class Recorder:
            def check(self, condition, name, detail=""):
                recorded.append((bool(condition), detail))
        names = ("ntk_b", "ntk_b")
        with unittest.mock.patch.object(check_c_abi_contract_ios, "NOT_IMPLEMENTED_YET", names):
            check_c_abi_contract_ios.check_entries({"a": "@c @implementation public func ntk_a() {}"},
                                                   {"ntk_a": "", "ntk_b": ""}, Recorder())
        self.assertEqual(recorded, [(False, "NOT_IMPLEMENTED_YET names a function twice")])

    def test_the_list_empties_when_every_function_has_an_entry(self):
        """What TB-10 ends with: E = H, and nothing else passes."""
        recorded = []
        class Recorder:
            def check(self, condition, name, detail=""):
                recorded.append(bool(condition))
        with unittest.mock.patch.object(check_c_abi_contract_ios, "NOT_IMPLEMENTED_YET", ()):
            sources = {"a": "@c @implementation public func ntk_a() {}"}
            check_c_abi_contract_ios.check_entries(sources, {"ntk_a": ""}, Recorder())
            check_c_abi_contract_ios.check_entries(sources, {"ntk_a": "", "ntk_b": ""}, Recorder())
        self.assertEqual(recorded, [True, False])

    # --- complete --------------------------------------------------------------

    def test_require_complete_fails_while_the_list_is_not_empty(self):
        self.assert_catches("complete", arguments=("--require-complete",))
        self.assert_catches("complete", headers=False, arguments=("--design-only", "--require-complete"))

    def test_a_name_added_to_the_list_passes_entries_and_only_complete_stops_it(self):
        recorded = []
        class Recorder:
            def check(self, condition, name, detail=""):
                recorded.append(("check", bool(condition)))
            def skip(self, name, reason):
                recorded.append(("skip", reason))
        sources = {"a": "@c @implementation public func ntk_a() {}"}
        functions = {"ntk_a": "", "ntk_b": ""}
        with unittest.mock.patch.object(check_c_abi_contract_ios, "NOT_IMPLEMENTED_YET", ("ntk_b",)):
            check_c_abi_contract_ios.check_entries(sources, functions, Recorder())
            check_c_abi_contract_ios.check_complete(False, Recorder())
            check_c_abi_contract_ios.check_complete(True, Recorder())
        self.assertEqual(recorded[0], ("check", True))
        self.assertEqual(recorded[1][0], "skip")
        self.assertIn("1 functions", recorded[1][1])
        self.assertEqual(recorded[2], ("check", False))

    def test_an_empty_list_is_complete_with_or_without_the_flag(self):
        recorded = []
        class Recorder:
            def check(self, condition, name, detail=""):
                recorded.append(bool(condition))
            def skip(self, name, reason):
                recorded.append("skip")
        with unittest.mock.patch.object(check_c_abi_contract_ios, "NOT_IMPLEMENTED_YET", ()):
            check_c_abi_contract_ios.check_complete(False, Recorder())
            check_c_abi_contract_ios.check_complete(True, Recorder())
        self.assertEqual(recorded, [True, True])

    # --- settings -------------------------------------------------------------

    @staticmethod
    def both_configurations(old, new):
        """An edit of every configuration of the framework target, since the two write the same lines."""
        def prepare(root):
            path = root / PBXPROJ
            text = path.read_text(encoding="utf-8")
            if old not in text:
                raise AssertionError(f"the test's own anchor is missing: {old}")
            path.write_text(text.replace(old, new), encoding="utf-8")
            return []
        return prepare

    def test_release_with_the_swift_module(self):
        self.assert_catches("settings", before=self.both_configurations("SWIFT_INSTALL_MODULE = NO;", "SWIFT_INSTALL_MODULE = YES;"))

    def test_release_with_the_debug_export(self):
        flags = '\t\t\t\tOTHER_LDFLAGS = (\n\t\t\t\t\t"-Wl,-exported_symbol,_$$s14IosLibraryCApi*",\n\t\t\t\t);\n'
        def prepare(root):
            path = root / PBXPROJ
            text = path.read_text(encoding="utf-8")
            # The second PRODUCT_BUNDLE_IDENTIFIER of the framework's is Release's.
            anchor = "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.jonghyunkim.nativetoolkit.IosLibraryCApi;\n"
            first = text.index(anchor)
            second = text.index(anchor, first + 1)
            path.write_text(text[:second] + flags + text[second:], encoding="utf-8")
            return []
        self.assert_catches("settings", before=prepare)

    def test_debug_without_what_testable_needs(self):
        self.assert_catches("settings", (PBXPROJ, "SWIFT_INSTALL_MODULE = YES;", "SWIFT_INSTALL_MODULE = NO;"))
        self.assert_catches("settings", (PBXPROJ, '"-Wl,-exported_symbol,_$$s14IosLibraryCApi*",', '"-Wl,-exported_symbol,_$$s*",'))

    def test_debug_that_differs_in_anything_else(self):
        self.assert_catches("settings", (PBXPROJ, "MODULEMAP_FILE = IosLibraryCApi/module.modulemap;", "MODULEMAP_FILE = Other/module.modulemap;"))
        self.assert_catches("settings", (PBXPROJ, "EXPORTED_SYMBOLS_FILE = IosLibraryCApi/IosLibraryCApi.exp;", ""))

    def test_each_setting_of_part_1_5_4(self):
        for key, value in check_c_abi_contract_ios.FRAMEWORK_SETTINGS.items():
            if key == "IPHONEOS_DEPLOYMENT_TARGET":
                continue
            with self.subTest(key=key):
                written = f'"{value}"' if re.search(r"[^\w./]", value) else value
                self.assert_catches("settings", before=self.both_configurations(f"{key} = {written};", f"{key} = other;"))

    def test_the_deployment_target_comes_from_the_project(self):
        self.assert_catches("settings", before=self.both_configurations("IPHONEOS_DEPLOYMENT_TARGET = 18.0;", "IPHONEOS_DEPLOYMENT_TARGET = 17.0;"))

    def test_a_setting_by_condition(self):
        # In both configurations, so that it is not caught as a difference between them.
        self.assert_catches("settings", before=self.both_configurations(
            "SWIFT_INSTALL_OBJC_HEADER = NO;", "SWIFT_INSTALL_OBJC_HEADER = NO;\n\t\t\t\t\"SWIFT_INSTALL_MODULE[sdk=iphoneos*]\" = YES;"))

    def test_a_configuration_with_an_xcconfig_is_not_read(self):
        self.assert_catches("settings", (PBXPROJ, "isa = XCBuildConfiguration;", "isa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = AAAAAAAAAAAAAAAAAAAAAAAA;"))

    def test_a_scheme_that_archives_debug(self):
        self.assert_catches("settings", (SCHEME, '<ArchiveAction\n      buildConfiguration = "Release"', '<ArchiveAction\n      buildConfiguration = "Debug"'))

    def test_a_project_or_a_scheme_that_is_missing(self):
        self.assert_catches("settings", removed=(PBXPROJ,))
        self.assert_catches("settings", removed=(SCHEME,))

    def test_a_project_without_the_configurations(self):
        self.assert_catches("settings", (PBXPROJ, 'list for PBXNativeTarget "IosLibraryCApi" */ = {', 'list for PBXNativeTarget "Other" */ = {'))

    # --- install --------------------------------------------------------------

    def test_a_new_case_of_the_install_result(self):
        self.assert_catches("install", (INSTALL_RESULT, "    case notMainThread", "    case notMainThread\n    case another"))

    def test_a_case_the_receiver_lost(self):
        self.assert_catches("install", (RECEIVER, "case .notMainThread:", "case .installed where false:"))
        # A mention that is not a case of the switch does not map it.
        self.assert_catches("install", (RECEIVER, "case .notMainThread:", "case .installed where result == .notMainThread:"))

    def test_an_install_result_with_no_cases_read(self):
        self.assert_catches("install", (INSTALL_RESULT, "public enum NotificationDelegateInstallResult", "public enum Other"))

    def test_an_install_result_that_is_missing(self):
        self.assert_catches("install", removed=(INSTALL_RESULT,))

    # --- public (E = P) -------------------------------------------------------

    def test_anything_public_that_is_not_an_entry(self):
        declarations = ("public func helper() {}", "public struct Thing {}", "public enum Thing {}",
                        "public final class Thing {}", "public let thing = 1", "public var thing = 1",
                        "public typealias Thing = Int", "public extension Handle {}", "public import Foundation",
                        "open class Thing {}", "open\nclass Thing {}")
        for declaration in declarations:
            with self.subTest(declaration=declaration):
                self.assert_catches("public", (HANDLE_SWIFT, "enum Handle {", f"{declaration}\nenum Handle {{"))

    def test_a_public_member_of_an_internal_type(self):
        self.assert_catches("public", (HANDLE_SWIFT, "enum Handle {", "enum Handle {\n    public static func helper() {}"))

    def test_public_in_a_comment_a_string_or_a_method_named_open_passes(self):
        self.assert_passes((HANDLE_SWIFT, "enum Handle {",
                            '// public func helper() {}\nenum Other {\n    static let text = "public func helper()"\n'
                            "    static func open(_ value: Int) {}\n    static func use() { open(1) }\n}\nenum Handle {"))

    # --- modulemap ------------------------------------------------------------

    def test_a_header_the_module_map_does_not_name(self):
        self.assert_catches("modulemap", (MODULE_MAP, '    header "NativeToolkitC/Share.h"\n', ""))

    def test_a_header_the_folder_does_not_have(self):
        self.assert_catches("modulemap", (MODULE_MAP, "    export *", '    header "NativeToolkitC/Ios.h"\n    export *'))

    def test_a_new_header_in_the_folder_without_the_module_map(self):
        def add(root):
            (root / INCLUDE / "Ios.h").write_text("/* new */\n", encoding="utf-8")
            return []
        self.assert_catches("modulemap", before=add)

    def test_a_header_named_twice(self):
        self.assert_catches("modulemap", (MODULE_MAP, "    export *", '    header "NativeToolkitC/Share.h"\n    export *'))

    def test_a_module_map_of_another_form(self):
        cases = (("framework module IosLibraryCApi {", "module IosLibraryCApi {"),
                 ("framework module IosLibraryCApi {", "framework module Other {"),
                 ('    header "NativeToolkitC/Share.h"', '    private header "NativeToolkitC/Share.h"'),
                 ('    header "NativeToolkitC/Share.h"', '    textual header "NativeToolkitC/Share.h"'),
                 ('    header "NativeToolkitC/Share.h"', '    exclude header "NativeToolkitC/Share.h"'),
                 ('    header "NativeToolkitC/Share.h"', '    header "Share.h"'),
                 ("    export *\n", ""))
        for old, new in cases:
            with self.subTest(new=new):
                self.assert_catches("modulemap", (MODULE_MAP, old, new))

    def test_a_module_map_that_is_missing(self):
        self.assert_catches("modulemap", removed=(MODULE_MAP,))

    def test_the_order_and_comments_of_the_module_map_do_not_matter(self):
        self.assert_passes((MODULE_MAP, '    header "NativeToolkitC/Common.h"\n    header "NativeToolkitC/Clipboard.h"\n',
                            '    // The first two.\n    header "NativeToolkitC/Clipboard.h"\n    header "NativeToolkitC/Common.h"\n'))

    # --- compile --------------------------------------------------------------

    COMMON_GUARD = "#ifndef NATIVETOOLKITC_COMMON_H"

    def compile_failure(self, *edits, removed=(), arguments=()):
        output, code = self.run_checker(edits, removed, arguments=arguments)
        self.assertEqual(code, 1, output)
        line = next((l for l in failures(output) if reports(l, "compile")), None)
        self.assertIsNotNone(line, f"compile was not reported: {failures(output)}")
        return line

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_each_language_is_compiled_with_its_own_standard(self):
        cases = (("C99", "defined(__STDC_VERSION__) && __STDC_VERSION__ == 199901L"),
                 ("C11", "defined(__STDC_VERSION__) && __STDC_VERSION__ == 201112L && !defined(__OBJC__)"),
                 ("C++", "defined(__cplusplus) && __cplusplus == 201103L"),
                 ("Objective-C", "defined(__OBJC__)"))
        for language, condition in cases:
            with self.subTest(language=language):
                line = self.compile_failure((COMMON, self.COMMON_GUARD, f"#if {condition}\n#error broken\n#endif\n{self.COMMON_GUARD}"))
                self.assertIn(f"as {language}:", line)
                for other, _ in cases:
                    if other != language:
                        self.assertNotIn(f"as {other}:", line)

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_every_header_is_compiled_alone(self):
        for header in ("Clipboard.h", "Dialog.h", "Notification.h", "Share.h"):
            guard = f"#ifndef NATIVETOOLKITC_{header[:-2].upper()}_H"
            with self.subTest(header=header):
                line = self.compile_failure((f"{INCLUDE}/{header}", guard, f"#error broken\n{guard}"))
                self.assertIn(f"{header} (framework) as C99", line)
                self.assertIn(f"{header} (copy) as C99", line)
                others = {"Clipboard.h", "Common.h", "Dialog.h", "Notification.h", "Share.h"} - {header}
                for other in others:
                    self.assertNotIn(f"{other} (", line)

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_a_header_that_needs_another_it_does_not_include(self):
        line = self.compile_failure((NOTIFICATION, INCLUDE_BLOCK, ""))
        self.assertIn("Notification.h", line)

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_each_branch_of_the_include_is_compiled(self):
        line = self.compile_failure((DIALOG, "#include <IosLibraryCApi/NativeToolkitC/Common.h>", "#include <IosLibraryCApi/NativeToolkitC/Missing.h>"))
        self.assertIn("Dialog.h (framework)", line)
        self.assertNotIn("Dialog.h (copy)", line)
        line = self.compile_failure((DIALOG, '#include "Common.h"', '#include "Missing.h"'))
        self.assertIn("Dialog.h (copy)", line)
        self.assertNotIn("Dialog.h (framework)", line)

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_each_warning_flag_is_on(self):
        cases = (("-Werror", "#warning broken"),
                 ("-Wall", "static inline int ntk_broken(void) { int unused; return 0; }"),
                 ("-Wextra", "static inline int ntk_broken(int unused) { return 0; }"),
                 ("-pedantic", "struct ntk_broken { struct { int x; }; };"))
        for flag, code in cases:
            with self.subTest(flag=flag):
                self.assert_catches("compile", (COMMON, "#define NTK_VERSION_MAJOR 2", f"{code}\n#define NTK_VERSION_MAJOR 2"))
                self.assertIn(flag, check_c_abi_contract_ios.HEADER_WARNINGS)

    def test_a_clang_that_does_not_exist_fails(self):
        self.assert_catches("compile", arguments=("--clang", os.devnull + ".missing"))

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_a_clang_that_fails_fails(self):
        def prepare(root):
            clang = root / "fake_clang"
            clang.write_text("#!/bin/sh\necho 'x: error: broken' >&2\nexit 1\n", encoding="utf-8")
            clang.chmod(clang.stat().st_mode | stat.S_IXUSR)
            return ["--clang", str(clang)]
        self.assert_catches("compile", before=prepare)

    def test_a_clang_that_succeeds_is_what_passes(self):
        """So the failures above come from what the compiler said, not from running one."""
        def prepare(root):
            clang = root / "fake_clang"
            clang.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            clang.chmod(clang.stat().st_mode | stat.S_IXUSR)
            return ["--clang", str(clang)]
        self.assert_passes(before=prepare)

    def test_without_xcode_it_says_skip_unless_it_is_required(self):
        env = {**os.environ, "PATH": ""}
        output, code = self.run_checker(env=env)
        self.assertIn("SKIP compile", output)
        self.assertEqual(code, 0, output)
        output, code = self.run_checker(arguments=("--require-compile",), env=env)
        self.assertTrue(any(reports(line, "compile") for line in failures(output)), output)
        self.assertEqual(code, 1)

    # --- layout ---------------------------------------------------------------

    SLICES = ("arm64-apple-ios18.0", "arm64-apple-ios18.0-simulator", "x86_64-apple-ios18.0-simulator")

    def test_a_struct_without_its_size_row(self):
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_SIZE(ntk_share_item, 24);\n", ""))

    def test_rows_that_cannot_stop_anything(self):
        macro = '#define LAYOUT_SIZE(type, size) _Static_assert(sizeof(type) == (size), "sizeof(" #type ")")'
        cases = ((macro, "#define LAYOUT_SIZE(type, size)"),
                 (macro, macro + "\n#undef LAYOUT_SIZE\n#define LAYOUT_SIZE(type, size)"),
                 (macro, '#define LAYOUT_SIZE(type, size) _Static_assert(sizeof(type) != 0, "sizeof(" #type ")")'),
                 ("LAYOUT_SIZE(ntk_share_item, 24);", "#if 0\nLAYOUT_SIZE(ntk_share_item, 24);\n#endif"),
                 ("LAYOUT_SIZE(ntk_share_item, 24);", "#ifdef NEVER\nLAYOUT_SIZE(ntk_share_item, 24);\n#endif"),
                 ("#include <stddef.h>", "#include <stddef.h>\n#define offsetof(a, b) 0"))
        for old, new in cases:
            with self.subTest(new=new):
                self.assert_catches("layout", (LAYOUT_TEST, old, new))

    def test_the_project_leaving_the_layout_test_out(self):
        self.assert_catches("layout", (PBXPROJ, "IosLibraryCApi.exp,", "IosLibraryCApi.exp,\n\t\t\t\tStructLayoutTests.m,"))

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_a_wrong_number_stops_compile_on_every_slice(self):
        cases = (("LAYOUT_SIZE(ntk_share_item, 24);", "LAYOUT_SIZE(ntk_share_item, 32);"),
                 ("LAYOUT_FIELD(ntk_share_item, value, 16);", "LAYOUT_FIELD(ntk_share_item, value, 8);"))
        for old, new in cases:
            with self.subTest(new=new):
                line = self.compile_failure((LAYOUT_TEST, old, new))
                for target in self.SLICES:
                    self.assertIn(f"StructLayoutTests.m for {target}:", line)

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_each_slice_is_compiled_as_itself(self):
        """Written with what only one target defines: a label alone would not show which target ran."""
        cases = (("x86_64-apple-ios18.0-simulator", "defined(__x86_64__)"),
                 ("arm64-apple-ios18.0-simulator", "defined(__arm64__) && defined(__APPLE_EMBEDDED_SIMULATOR__)"))
        for target, condition in cases:
            with self.subTest(target=target):
                line = self.compile_failure((COMMON, self.COMMON_GUARD, f"#if {condition}\n#error broken\n#endif\n{self.COMMON_GUARD}"))
                self.assertIn(f"StructLayoutTests.m for {target}:", line)
                for other in self.SLICES:
                    if other != target:
                        self.assertNotIn(f"StructLayoutTests.m for {other}:", line)
                self.assertNotIn("Common.h (", line)

    @unittest.skipUnless(XCODE, "no Xcode")
    def test_a_header_that_moves_a_field_stops_compile_on_every_slice(self):
        line = self.compile_failure((SHARE, "    uint32_t            reserved1;\n", ""))
        for target in self.SLICES:
            self.assertIn(f"StructLayoutTests.m for {target}:", line)

    def test_a_field_that_is_an_array_is_read_and_one_that_cannot_be_read_fails(self):
        recorded = []
        class Recorder:
            def check(self, condition, name, detail=""):
                recorded.append((bool(condition), detail))
        text = (ROOT / LAYOUT_TEST).read_text(encoding="utf-8")
        rows = "LAYOUT_SIZE(s, 8);\nLAYOUT_FIELD(s, reserved, 0);\n"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / LAYOUT_TEST).parent.mkdir(parents=True)
            (root / LAYOUT_TEST).write_text(text.split("// Clipboard.h")[0] + rows, encoding="utf-8")
            (root / PBXPROJ).parent.mkdir(parents=True)
            (root / PBXPROJ).write_text("", encoding="utf-8")
            with unittest.mock.patch.object(check_c_abi_contract_ios, "ROOT", root):
                check_c_abi_contract_ios.check_layout({"s": "uint8_t reserved[2]"}, Recorder())
                check_c_abi_contract_ios.check_layout({"s": "void (*fn)(int)"}, Recorder())
        self.assertTrue(recorded[0][0], recorded[0])
        self.assertFalse(recorded[1][0])
        self.assertIn("cannot read the field", recorded[1][1])

    def test_a_field_without_its_row(self):
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_FIELD(ntk_share_item, value, 16);\n", ""))

    def test_a_commented_out_row_is_no_row(self):
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_SIZE(ntk_share_item, 24);", "// LAYOUT_SIZE(ntk_share_item, 24);"))
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_FIELD(ntk_share_item, value, 16);", "/* LAYOUT_FIELD(ntk_share_item, value, 16); */"))

    def test_a_row_of_nothing_the_headers_declare(self):
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_SIZE(ntk_share_item, 24);", "LAYOUT_SIZE(ntk_share_item, 24);\nLAYOUT_SIZE(ntk_share_old, 24);"))
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_FIELD(ntk_share_item, value, 16);", "LAYOUT_FIELD(ntk_share_item, value, 16);\nLAYOUT_FIELD(ntk_share_item, old, 24);"))

    def test_a_row_twice(self):
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_SIZE(ntk_share_item, 24);", "LAYOUT_SIZE(ntk_share_item, 24);\nLAYOUT_SIZE(ntk_share_item, 32);"))
        self.assert_catches("layout", (LAYOUT_TEST, "LAYOUT_FIELD(ntk_share_item, value, 16);", "LAYOUT_FIELD(ntk_share_item, value, 16);\nLAYOUT_FIELD(ntk_share_item, value, 16);"))

    def test_a_struct_or_a_field_added_to_the_headers(self):
        field = "    const char*         value;                   /**< The text, the URL, or the file path. */\n"
        self.assert_catches("layout", (SHARE, field, field + "    const char*         added;\n"), (DESIGN, field, field + "    const char*         added;\n"))
        struct = "typedef struct ntk_share_request {"
        added = "typedef struct ntk_share_added {\n    uint32_t struct_size;\n} ntk_share_added;\n\n"
        self.assert_catches("layout", (SHARE, struct, added + struct), (DESIGN, struct, added + struct))

    def test_a_layout_test_that_is_missing(self):
        self.assert_catches("layout", removed=(LAYOUT_TEST,))

    # --- symbols ------------------------------------------------------------

    # The host's slice, which is all nm lists of a fat binary without -arch all.
    HOST = "arm64"

    @classmethod
    def fake_nm(cls, extra=(), dropped=(), architectures=(), only_in_first=(), empty=(), thin="arm64"):
        """A stand-in for nm that answers as the real one does (see
        test_the_real_nm_*): a fat binary lists every slice under its heading
        with -arch all, an empty slice being a heading alone, and only the
        host's, with no heading, without it. architectures empty makes the
        binary thin. Flags other than -gU and -arch are refused."""
        def prepare(root):
            design = (root / DESIGN).read_text(encoding="utf-8")
            code = c_abi_contract_common.appendix_code(design)
            names = sorted(set(c_abi_contract_common.declarations(code)["function"]) - set(NOT_IMPLEMENTED_YET) - set(dropped))
            lines = [f"0000000000001000 T _{name}\n" for name in names] + [f"0000000000001000 T {name}\n" for name in extra]
            library = root / "IosLibraryCApi"
            cpu = {"arm64": 0x0100000C, "x86_64": 0x01000007}[thin]
            library.write_bytes(b"\xcf\xfa\xed\xfe" + cpu.to_bytes(4, "little"))
            every, host = "".join(lines), ""
            if architectures:
                every = ""
                for index, architecture in enumerate(architectures):
                    section = lines if index == 0 else [line for line in lines if line.split()[-1] not in only_in_first]
                    section = [] if architecture in empty else section
                    every += f"\n{library} (for architecture {architecture}):\n" + "".join(section)
                    host = "".join(section) if architecture == cls.HOST else host
            else:
                host = every
            (root / "every.txt").write_text(every, encoding="utf-8")
            (root / "host.txt").write_text(host, encoding="utf-8")
            nm = root / "fake_nm.py"
            nm.write_text(textwrap.dedent(f"""\
                #!{sys.executable}
                import sys
                flags = sys.argv[1:-1]
                if flags == ["-arch", "all", "-gU"]:
                    sys.stdout.write(open({str(root / "every.txt")!r}).read())
                elif flags == ["-gU"]:
                    sys.stdout.write(open({str(root / "host.txt")!r}).read())
                else:
                    sys.exit("flags this stand-in does not know: " + repr(flags))
                """), encoding="utf-8")
            nm.chmod(nm.stat().st_mode | stat.S_IXUSR)
            return ["--library", str(library), "--nm", str(nm)]
        return prepare

    def test_symbols_that_match_8_2(self):
        output = self.assert_passes(before=self.fake_nm())
        self.assertIn("OK   symbols", output)

    def test_symbols_of_every_architecture_that_match_8_2(self):
        output = self.assert_passes(before=self.fake_nm(architectures=("x86_64", "arm64")))
        self.assertIn("2 architectures", output)

    def test_an_exported_ntk_symbol_8_2_lacks(self):
        self.assert_catches("symbols", before=self.fake_nm(extra=("_ntk_internal_helper",)))

    def test_an_exported_symbol_that_is_not_ntk(self):
        self.assert_catches("symbols", before=self.fake_nm(extra=("_$s14IosLibraryCApi4mainyyF",)))

    def test_a_function_the_library_does_not_export(self):
        self.assert_catches("symbols", before=self.fake_nm(dropped=("ntk_notification_install",)))

    def test_a_function_exported_while_it_is_listed_as_not_implemented(self):
        self.assert_catches("symbols", before=self.fake_nm(extra=(f"_{NOT_IMPLEMENTED_YET[0]}",)))

    def test_a_function_one_architecture_does_not_export(self):
        for architectures in (("x86_64", "arm64"), ("arm64", "x86_64")):
            with self.subTest(architectures=architectures):
                self.assert_catches("symbols", before=self.fake_nm(architectures=architectures, only_in_first=("_ntk_version",)))

    def test_an_architecture_that_exports_nothing(self):
        for empty in ("x86_64", "arm64"):
            with self.subTest(empty=empty):
                self.assert_catches("symbols", before=self.fake_nm(architectures=("x86_64", "arm64"), empty=(empty,)))

    def with_architectures(self, wanted, **options):
        def prepare(root):
            return self.fake_nm(**options)(root) + ["--architectures", wanted]
        return prepare

    def test_the_architectures_asked_for(self):
        self.assert_passes(before=self.with_architectures("arm64,x86_64", architectures=("x86_64", "arm64")))
        self.assert_passes(before=self.with_architectures("arm64"))

    def test_a_slice_that_lost_an_architecture(self):
        self.assert_catches("symbols", before=self.with_architectures("arm64,x86_64", architectures=("arm64",)))

    def test_a_slice_with_an_architecture_not_asked_for(self):
        self.assert_catches("symbols", before=self.with_architectures("arm64", architectures=("x86_64", "arm64")))

    def test_a_thin_binary_of_another_architecture(self):
        self.assert_catches("symbols", before=self.with_architectures("arm64", thin="x86_64"))

    def test_a_library_given_twice_is_a_usage_error(self):
        output, code = self.run_checker(arguments=("--library", "a", "--library", "b"))
        self.assertEqual(code, 2, output)

    def test_nm_or_architectures_without_a_library_is_a_usage_error(self):
        for option in ("--nm", "--architectures"):
            with self.subTest(option=option):
                output, code = self.run_checker(arguments=(option, "x"))
                self.assertEqual(code, 2, output)

    # The real nm, on a macOS library of the same names: the stand-in above
    # must not be the only witness of what nm prints.

    def real_library(self, root, *slices):
        """A binary of the slices (architecture, whether it exports the functions)."""
        design = (root / DESIGN).read_text(encoding="utf-8")
        names = set(c_abi_contract_common.declarations(c_abi_contract_common.appendix_code(design))["function"]) - set(NOT_IMPLEMENTED_YET)
        full = root / "full.c"
        full.write_text("".join(f"void {name}(void) {{}}\n" for name in sorted(names)), encoding="utf-8")
        bare = root / "bare.c"
        bare.write_text("static int nothing;\n", encoding="utf-8")
        built = []
        for architecture, exports in slices:
            built.append(root / f"{architecture}.dylib")
            subprocess.run([CLANG, "-dynamiclib", "-w", "-arch", architecture, str(full if exports else bare), "-o", str(built[-1])], check=True)
        if len(built) == 1:
            return ["--library", str(built[0])]
        library = root / "library.dylib"
        subprocess.run(["lipo", "-create", *map(str, built), "-output", str(library)], check=True)
        return ["--library", str(library)]

    @unittest.skipUnless(CLANG and shutil.which("lipo") and shutil.which("nm"), "no clang, lipo or nm")
    def test_the_real_nm_on_a_fat_binary(self):
        output = self.assert_passes(before=lambda root: self.real_library(root, ("arm64", True), ("x86_64", True)))
        self.assertIn("2 architectures", output)

    @unittest.skipUnless(CLANG and shutil.which("lipo") and shutil.which("nm"), "no clang, lipo or nm")
    def test_the_real_nm_on_a_thin_binary(self):
        def prepare(root):
            return self.real_library(root, ("arm64", True)) + ["--architectures", "arm64"]
        self.assert_passes(before=prepare)

    @unittest.skipUnless(CLANG and shutil.which("lipo") and shutil.which("nm"), "no clang, lipo or nm")
    def test_the_real_nm_on_a_slice_that_exports_nothing(self):
        for arch_full, arch_bare in (("arm64", "x86_64"), ("x86_64", "arm64")):
            with self.subTest(empty=arch_bare):
                self.assert_catches("symbols", before=lambda root: self.real_library(root, (arch_full, True), (arch_bare, False)))

    def test_an_nm_that_lists_nothing(self):
        def prepare(root):
            arguments = self.fake_nm()(root)
            (root / "every.txt").write_text("", encoding="utf-8")
            return arguments
        self.assert_catches("symbols", before=prepare)

    def test_an_nm_that_does_not_exist(self):
        def prepare(root):
            arguments = self.fake_nm()(root)
            arguments[-1] = str(root / "no-nm")
            return arguments
        self.assert_catches("symbols", before=prepare)

    def test_a_library_that_is_missing(self):
        self.assert_catches("symbols", arguments=("--library", os.devnull + ".missing"))


class CommonHeaders(unittest.TestCase):
    """common_header_problems against any number of OSes (README 3.3)."""

    @classmethod
    def setUpClass(cls):
        read = lambda fragment: (ROOT / fragment).read_text(encoding="utf-8")
        design = read(DESIGN)
        cls.ios = c_abi_contract_common.appendix_headers(design)["Common.h"]
        cls.android = read(ANDROID_COMMON)
        cls.windows = read(WINDOWS_COMMON)

    def problems(self, **headers):
        return c_abi_contract_common.common_header_problems(headers)

    def test_the_three_oses_agree(self):
        self.assertEqual(self.problems(Windows=self.windows, Android=self.android, iOS=self.ios), [])

    def test_two_oses_agree(self):
        self.assertEqual(self.problems(Windows=self.windows, Android=self.android), [])

    def test_one_os_has_nothing_to_be_compared_with(self):
        self.assertTrue(any("cannot be compared" in p for p in self.problems(iOS=self.ios)))

    def test_a_struct_or_a_value_in_common_h(self):
        for extra in ("typedef struct ntk_s { int a; } ntk_s;", "enum { NTK_COMMON_VALUE = 1 };"):
            with self.subTest(extra=extra):
                text = self.ios.replace("uint32_t NTK_CALL ntk_version(void);", extra + "\nuint32_t NTK_CALL ntk_version(void);")
                self.assertNotEqual(text, self.ios)
                problems = self.problems(Windows=self.windows, Android=self.android, iOS=text)
                self.assertTrue(any("the iOS Common.h declares" in p for p in problems), problems)

    def test_an_os_with_no_common_function(self):
        problems = self.problems(Windows="", iOS=self.ios)
        self.assertTrue(any("no common function" in p for p in problems), problems)

    def test_a_fourth_os_is_read_like_the_others(self):
        self.assertEqual(self.problems(Windows=self.windows, Android=self.android, iOS=self.ios, Mac=self.ios), [])
        broken = self.ios.replace("uint32_t NTK_CALL ntk_version(void);", "uint64_t NTK_CALL ntk_version(void);")
        self.assertNotEqual(broken, self.ios)
        problems = self.problems(Windows=self.windows, Android=self.android, iOS=self.ios, Mac=broken)
        self.assertTrue(any("ntk_version" in p and "Mac has" in p for p in problems), problems)

    def test_a_declaration_two_of_three_lack_names_who_has_it(self):
        extra = self.ios.replace("uint32_t NTK_CALL ntk_version(void);", "uint32_t NTK_CALL ntk_version(void);\nuint32_t NTK_CALL ntk_more(void);")
        problems = self.problems(Windows=self.windows, Android=self.android, iOS=extra)
        self.assertTrue(any("only in the iOS Common.h" in p for p in problems), problems)

    def test_a_declaration_one_of_three_lacks_names_who_lacks_it(self):
        lacking = self.ios.replace("uint32_t NTK_CALL ntk_version(void);\n", "")
        problems = self.problems(Windows=self.windows, Android=self.android, iOS=lacking)
        self.assertTrue(any("not in the iOS Common.h" in p for p in problems), problems)

    def test_a_constant_only_windows_may_have_stays_allowed_for_windows_alone(self):
        self.assertIn("NTK_SYSTEM_CODE_E_OUTOFMEMORY", self.windows)
        for label in ("iOS", "Android"):
            with self.subTest(label=label):
                text = self.ios.replace("#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020000\n#define NTK_SYSTEM_CODE_X 1")
                problems = c_abi_contract_common.common_header_problems({"Windows": self.windows, label: text})
                self.assertTrue(any("NTK_SYSTEM_CODE_X" in p for p in problems), problems)

    def test_the_table_of_allowed_constants_is_per_os(self):
        text = self.ios.replace("#define NTK_VERSION 0x020000", "#define NTK_VERSION 0x020000\n#define NTK_IOS_ONLY 1")
        headers = {"Android": self.android, "iOS": text}
        self.assertTrue(c_abi_contract_common.common_header_problems(headers))
        self.assertEqual(c_abi_contract_common.common_header_problems(headers, {"iOS": r"^NTK_IOS_\w+$"}), [])


class ErrorNumbers(unittest.TestCase):
    """The table of numbers, read and compared on its own (P1-7)."""

    TABLE = {"dialog": {"NONE": 0, "CANCELED": 1, "HOST_START_FAILED": 2}}

    def read(self, text):
        problems = []
        return c_abi_contract_common.error_numbers(text, problems), problems

    def compare(self, values_by_os, table=None, **options):
        return c_abi_contract_common.error_number_problems(table or self.TABLE, values_by_os, **options)

    def test_the_real_table_reads_without_problems(self):
        table, problems = self.read((ROOT / NUMBERS).read_text(encoding="utf-8"))
        self.assertEqual(problems, [])
        self.assertEqual(sorted(table), ["clipboard", "dialog", "notification", "share"])

    def test_the_last_numbers_are_those_11_5_gives(self):
        table = json.loads((ROOT / NUMBERS).read_text(encoding="utf-8"))
        last = {feature: max(numbers.values()) for feature, numbers in table.items()}
        design = (ROOT / DESIGN).read_text(encoding="utf-8")
        written = re.search(r"今の表の最後は ([^（]+)（", design)
        self.assertIsNotNone(written, "11.5 no longer says what the last numbers are")
        said = {name.lower(): int(number) for name, number in re.findall(r"(\w+) (\d+)", written.group(1))}
        self.assertEqual(last, said)

    def test_names_only_one_os_has(self):
        table = json.loads((ROOT / NUMBERS).read_text(encoding="utf-8"))
        self.assertEqual(table["clipboard"]["CANCELED"], 27)
        self.assertEqual(table["notification"]["WRONG_THREAD"], 16)
        self.assertEqual(table["dialog"]["HOST_START_FAILED"], 9)

    def test_a_name_written_twice_in_a_feature(self):
        _, problems = self.read('{"dialog": {"NONE": 0, "NONE": 0}}')
        self.assertTrue(any("twice" in p for p in problems), problems)

    def test_a_number_with_two_names(self):
        _, problems = self.read('{"dialog": {"NONE": 0, "OTHER": 0}}')
        self.assertTrue(any("both" in p for p in problems), problems)

    def test_a_hole_in_the_numbers(self):
        _, problems = self.read('{"dialog": {"NONE": 0, "OTHER": 2}}')
        self.assertTrue(any("no name has 1" in p for p in problems), problems)

    def test_values_that_are_not_numbers(self):
        for text in ('{"dialog": {"NONE": "0"}}', '{"dialog": {"NONE": 0, "OTHER": true}}', '{"dialog": {"NONE": -1}}', '{"dialog": {"none": 0}}'):
            with self.subTest(text=text):
                self.assertTrue(self.read(text)[1])

    def test_shapes_that_are_not_a_table(self):
        for text in ("", "[]", "{}", '{"dialog": {}}', '{"Dialog": {"NONE": 0}}', '{"dialog": 1}'):
            with self.subTest(text=text):
                self.assertTrue(self.read(text)[1])

    def test_each_os_may_have_a_gap(self):
        self.assertEqual(self.compare({"iOS": {"NTK_DIALOG_ERROR_NONE": 0, "NTK_DIALOG_ERROR_CANCELED": 1},
                                       "Android": {"NTK_DIALOG_ERROR_NONE": 0, "NTK_DIALOG_ERROR_HOST_START_FAILED": 2}},
                                      every_os=True), [])

    def test_the_same_name_with_another_number(self):
        problems = self.compare({"iOS": {"NTK_DIALOG_ERROR_NONE": 0, "NTK_DIALOG_ERROR_CANCELED": 2}})
        self.assertTrue(any("the table says 1" in p for p in problems), problems)

    def test_a_number_used_for_another_name(self):
        problems = self.compare({"iOS": {"NTK_DIALOG_ERROR_NONE": 0, "NTK_DIALOG_ERROR_REFUSED": 1}})
        self.assertTrue(any("REFUSED" in p and "not in the table" in p for p in problems), problems)

    def test_a_feature_the_table_does_not_have(self):
        problems = self.compare({"iOS": {"NTK_DIALOG_ERROR_NONE": 0, "NTK_CAMERA_ERROR_NONE": 0}})
        self.assertTrue(any("belongs to no feature" in p for p in problems), problems)

    def test_an_enumeration_of_one_os_alone_is_left_out(self):
        values = {"NTK_DIALOG_ERROR_NONE": 0, "NTK_ANDROID_ERROR_IN_PROGRESS": 4}
        self.assertTrue(self.compare({"Android": values}))
        self.assertEqual(self.compare({"Android": values}, other_features=("android",)), [])

    def test_constants_that_are_not_errors_are_not_compared(self):
        self.assertEqual(self.compare({"iOS": {"NTK_DIALOG_ERROR_NONE": 0, "NTK_DIALOG_BUTTON_POSITIVE": 7}}), [])

    def test_an_os_with_no_error_of_a_feature(self):
        problems = self.compare({"iOS": {"NTK_DIALOG_BUTTON_POSITIVE": 7}})
        self.assertTrue(any("no header declares an error of dialog" in p for p in problems), problems)

    def test_a_name_no_os_declares_is_stale_only_when_every_os_is_given(self):
        values = {"iOS": {"NTK_DIALOG_ERROR_NONE": 0}}
        self.assertEqual(self.compare(values), [])
        problems = self.compare(values, every_os=True)
        self.assertEqual(len(problems), 2, problems)
        self.assertTrue(all("no OS declares" in p for p in problems), problems)


class SwiftReading(unittest.TestCase):
    """What the checker reads from a swiftinterface, on small inputs."""

    SOURCE = """\
// swift-interface-format-version: 1.0
public enum E : Swift.Error {
  case a
  case b(Swift.String, count: Swift.Int), c
  indirect case d(E)
  public static func == (a: E, b: E) -> Swift.Bool
  public var x: Swift.Int {
    get
  }
}
final public class M {
  public func plain()
  @available(*, deprecated, message: "a { brace")
  public static func stat(_ a: Swift.Int, b c: Swift.Int = 1) async throws -> Swift.Bool
  public func callback(handler: @escaping (Swift.Bool, [Swift.String : Swift.Int]) -> Swift.Void, last: Swift.Int)
  public func generic<T>(_ value: T) where T : Swift.Sendable
  public struct Inner {
    public func nested()
  }
  final public var hub: Module.Hub<Swift.Int> {
    get
  }
}
extension Module.M {
  public func extended()
}
"""

    def setUp(self):
        self.code = check_c_abi_contract_ios.swift_code(self.SOURCE)

    def test_cases(self):
        self.assertEqual(check_c_abi_contract_ios.enum_cases(self.code, "E"), ["a", "b", "c", "d"])

    def test_an_enumeration_that_is_not_there(self):
        self.assertEqual(check_c_abi_contract_ios.enum_cases(self.code, "F"), [])

    def test_a_name_that_only_starts_the_same(self):
        self.assertEqual(check_c_abi_contract_ios.enum_cases(self.code + "public enum EE {\n  case z\n}\n", "E"), ["a", "b", "c", "d"])

    def test_selectors(self):
        selectors = [f[0] for f in check_c_abi_contract_ios.swift_functions(check_c_abi_contract_ios.swift_bodies(self.code, "M"))]
        self.assertEqual(selectors, ["plain()", "stat(_:b:)", "callback(handler:last:)", "generic(_:)", "extended()"])

    def test_traits(self):
        functions = {f[0]: f for f in check_c_abi_contract_ios.swift_functions(check_c_abi_contract_ios.swift_bodies(self.code, "M"))}
        self.assertIn("static", functions["stat(_:b:)"][1])
        self.assertIn("async throws", functions["stat(_:b:)"][2])
        self.assertNotIn("static", functions["plain()"][1])

    def test_the_type_of_a_property(self):
        body = check_c_abi_contract_ios.swift_bodies(self.code, "M")
        self.assertEqual(check_c_abi_contract_ios.swift_property_type(body, "hub"), "Hub")
        self.assertIsNone(check_c_abi_contract_ios.swift_property_type(body, "hu"))

    def test_nm_sections(self):
        sections = check_c_abi_contract_ios.exported_symbols(
            "\nlib (for architecture x86_64):\n0 T _a\n\nlib (for architecture arm64):\n0 T _b\n")
        self.assertEqual(sections, {"x86_64": {"_a"}, "arm64": {"_b"}})
        self.assertEqual(check_c_abi_contract_ios.exported_symbols("0 T _a\n"), {"": {"_a"}})


class DeclarationReading(unittest.TestCase):

    def test_a_bit_is_read_as_its_value(self):
        values = c_abi_contract_common.declarations("enum {\n    NTK_A = 1u << 0,\n    NTK_B = 1u << 5,\n    NTK_C = 0x10,\n    NTK_D = -1\n};\n")["value"]
        self.assertEqual(values, {"NTK_A": 1, "NTK_B": 32, "NTK_C": 16, "NTK_D": -1})

    def test_initializers_outside_the_grammar_are_unread_not_guessed(self):
        for item in ("NTK_A = 1u << 1 | 1", "NTK_A = 21 + 1", "NTK_A = (1)", "NTK_A = OTHER", "NTK_A", "OTHER_A = 3", "NTK_A = 1 << 2 << 3"):
            with self.subTest(item=item):
                found = c_abi_contract_common.declarations(f"enum {{\n    {item}\n}};\n")
                self.assertEqual(found["value"], {})
                self.assertEqual(list(found["unread"]), [c_abi_contract_common.normalise(item)])

    def test_a_trailing_comma_is_not_an_item(self):
        found = c_abi_contract_common.declarations("enum {\n    NTK_A = 1,\n};\n")
        self.assertEqual((found["value"], found["unread"]), ({"NTK_A": 1}, {}))

    def test_statements_of_no_kind_are_unread(self):
        for statement in ("int ntk_a(void);", "extern int ntk_b;", "struct ntk_c { int a; };", "#define X 1\nint ntk_d(void);"):
            with self.subTest(statement=statement):
                self.assertTrue(c_abi_contract_common.declarations(statement + "\n")["unread"])

    def test_every_header_of_the_three_oses_reads_whole(self):
        for fragment in (ANDROID_INCLUDE, "windows/WindowsLibraryCApi/include/NativeToolkitC"):
            for path in sorted((ROOT / fragment).glob("*.h")):
                with self.subTest(path=path.name):
                    self.assertEqual(c_abi_contract_common.declarations(path.read_text(encoding="utf-8"))["unread"], {})

    def test_op_range_reads_each_part(self):
        self.assertEqual(c_abi_contract_common.op_range("OP-01〜OP-02、OP-10"), ["OP-01", "OP-02", "OP-10"])
        self.assertEqual(c_abi_contract_common.op_range("OP-08、OP-09～OP-10"), ["OP-08", "OP-09", "OP-10"])
        self.assertEqual(c_abi_contract_common.op_range("操作（OP-13〜OP-15）"), ["OP-13", "OP-14", "OP-15"])


class IncludeBlocks(unittest.TestCase):
    """directive_problems on the conditional include, without Appendix A to differ from."""

    HEADER = ("#ifndef NATIVETOOLKITC_X_H\n#define NATIVETOOLKITC_X_H\n\n" + INCLUDE_BLOCK +
              '\n\n#ifdef __cplusplus\nextern "C" {\n#endif\n\nint NTK_CALL ntk_x(void);\n\n#ifdef __cplusplus\n}\n#endif\n#endif\n')

    def problems(self, text, blocks=(check_c_abi_contract_ios.COMMON_INCLUDE,)):
        return c_abi_contract_common.directive_problems("X.h", text, blocks)

    def test_the_block_where_it_belongs(self):
        self.assertEqual(self.problems(self.HEADER), [])

    def test_not_allowed_unless_given(self):
        self.assertTrue(self.problems(self.HEADER, ()))

    def test_a_declaration_inside(self):
        problems = self.problems(self.HEADER.replace('#include "Common.h"\n', '#include "Common.h"\nint NTK_CALL ntk_y(void);\n'))
        self.assertTrue(any("inside" in p for p in problems), problems)

    def test_inside_extern_c(self):
        moved = self.HEADER.replace(INCLUDE_BLOCK + "\n", "").replace('extern "C" {\n#endif\n', 'extern "C" {\n#endif\n' + INCLUDE_BLOCK + "\n")
        problems = self.problems(moved)
        self.assertTrue(any('inside extern "C"' in p for p in problems), problems)

    def test_the_bits_of_appendix_a_are_all_different(self):
        design = (ROOT / DESIGN).read_text(encoding="utf-8")
        values = c_abi_contract_common.declarations(c_abi_contract_common.appendix_code(design))["value"]
        patterns = [v for k, v in values.items() if k.startswith("NTK_CLIPBOARD_PATTERN_")]
        self.assertEqual(sorted(patterns), [1 << n for n in range(len(patterns))])
        self.assertEqual(len(patterns), 11)


if __name__ == "__main__":
    unittest.main()
