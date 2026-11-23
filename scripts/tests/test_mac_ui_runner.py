"""Self-tests of scripts/mac_ui_runner.py and the order of scripts/test_mac.sh.

The runner keeps the UI tests off the parts of the user's own Mac they were not allowed to touch and
checks that the VM is the qualified one (macOS UI test design, U-9, 3.4 and 6.3). A runner that
quietly selects too much, or a check that quietly stops checking, looks exactly like one that works,
so every case here breaks one decision on purpose (design chapter 7, the runner's rows) and asserts
that it is caught, next to the near-miss that must pass. Nothing here starts the VM, a UI test or an
app on this Mac; the stale-run case starts a copy of /bin/sleep in a temporary folder.

The fixtures in fixtures/mac_ui_runner/ are real output of Xcode 26.3 in the VM (macOS 15.8.3), stage
0d (2026-11-23), with the VM's home folder replaced by <home>:
  enumeration.json        -enumerate-tests -test-enumeration-style flat -test-enumeration-format json
  otool-ov.txt, otool-l.txt
                          otool -arch arm64 -ov / -l of MacLibraryExampleUITests.xctest
  xcresult-dialog-tests.json, xcresult-dialog-summary.json
                          xcresulttool get test-results tests / summary of the DialogUITests call
  xcresult-unit-tests.json
                          the same for MacLibraryTests (Swift Testing)

Run: python3 -m unittest discover -s scripts/tests -p 'test_mac_ui_runner.py'
"""

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import mac_ui_runner as r  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "mac_ui_runner"
TESTS_DIR = ROOT / "mac" / "MacLibraryExample" / "MacLibraryExampleUITests"
SAMPLE_DIR = ROOT / "mac" / "MacLibraryExample" / "MacLibraryExample"
PBXPROJ = ROOT / "mac" / "MacLibraryExample" / "MacLibraryExample.xcodeproj" / "project.pbxproj"
SCRIPT = ROOT / "scripts" / "test_mac.sh"
VOCABULARY = r.step_vocabulary((TESTS_DIR / r.STEP_CODE_FILE).read_text(encoding="utf-8"))


def fixture(name):
    return (FIXTURES / name).read_text(encoding="utf-8")


def declarations():
    return r.parse_declarations((TESTS_DIR / r.DECLARATIONS_FILE).read_text(encoding="utf-8"))


def enumeration():
    return r.parse_enumeration(fixture("enumeration.json"))


def ident(key):
    return r.enumeration_id_from_key(key)


def keys_of(identifiers):
    return [r.key_from_enumeration_id(i) for i in identifiers]


def enumeration_json(identifiers, extra=()):
    tests = [{"identifier": i} for i in identifiers] + [{"identifier": e} for e in extra]
    return json.dumps({"errors": [], "values": [{"disabledTests": [], "enabledTests": tests}]})


class Names(unittest.TestCase):
    def test_keys(self):
        self.assertEqual(r.key_from_enumeration_id("MacLibraryExampleUITests/DialogUITests/testD1_x()"), "DialogUITests/testD1_x")
        self.assertEqual(r.key_from_node_id("DialogUITests/testD1_x()"), "DialogUITests/testD1_x")
        for bad in ("MacLibraryExampleTests/A/testB()", "MacLibraryExampleUITests/A/testB", "MacLibraryExampleUITests/A/helper()",
                    "MacLibraryExampleUITests/A/B/testC()"):
            with self.assertRaises(r.RunnerError, msg=bad):
                r.key_from_enumeration_id(bad)


class Enumeration(unittest.TestCase):
    def test_the_real_enumeration_matches_the_declarations(self):
        ids = enumeration()
        self.assertEqual(len(ids), 118)
        self.assertEqual(r.check_enumeration(ids, declarations()), [])

    def test_unit_tests_and_the_base_class_are_dropped(self):
        ids = enumeration()[:2]
        text = enumeration_json(ids, extra=("MacLibraryExampleTests/Foo/testBar()", "MacLibraryExampleUITests/SampleUITestCase"))
        self.assertEqual(r.parse_enumeration(text), ids)

    def test_another_class_without_methods_stops(self):
        with self.assertRaises(r.RunnerError):
            r.parse_enumeration(enumeration_json([], extra=("MacLibraryExampleUITests/Helper",)))

    def test_errors_disabled_and_two_configurations_stop(self):
        for data in ({"errors": ["x"], "values": []},
                     {"errors": [], "values": [{"disabledTests": [{"identifier": "a"}], "enabledTests": []}]},
                     {"errors": [], "values": [{"enabledTests": []}, {"enabledTests": []}]}):
            with self.assertRaises(r.RunnerError):
                r.parse_enumeration(json.dumps(data))

    def test_an_unknown_name_stops(self):
        with self.assertRaises(r.RunnerError):
            r.parse_enumeration(enumeration_json(["MacLibraryExampleUITests/DialogUITests/notATest()"]))

    def test_a_repeated_identifier_is_a_problem(self):
        ids = enumeration()
        self.assertTrue(any("repeats" in p for p in r.check_enumeration(ids + ids[:1], declarations())))

    def test_a_missing_and_an_extra_declaration(self):
        ids = enumeration()
        table = declarations()
        removed = dict(table)
        removed.pop("DialogUITests/testD1_showDialogOK")
        self.assertTrue(any("without a declaration" in p for p in r.check_enumeration(ids, removed)))
        added = dict(table)
        added["DialogUITests/testD99_gone"] = []
        self.assertTrue(any("declarations without a test" in p for p in r.check_enumeration(ids, added)))

    def test_a_new_class_not_listed(self):
        ids = enumeration() + [ident("NewUITests/testA")]
        table = dict(declarations())
        table["NewUITests/testA"] = []
        self.assertTrue(any("classes differ" in p for p in r.check_enumeration(ids, table)))

    def test_class_minimums_and_any_of(self):
        table = dict(declarations())
        table["NotificationColdStartUITests/testNC1_bodyClickLaunches"] = ["notification"]
        self.assertTrue(any("below the minimum" in p for p in r.check_enumeration(enumeration(), table)))
        table = dict(declarations())
        table["ShareUITests/testS1_shareTextPickerEscape"] = []
        self.assertTrue(any("none of" in p for p in r.check_enumeration(enumeration(), table)))

    def test_a_renamed_test_of_a_table_stops(self):
        table = dict(declarations())
        ids = [i for i in enumeration() if "testCB1_" not in i] + [ident("ClipboardPasteUITests/testCB1_renamed")]
        table.pop("ClipboardPasteUITests/testCB1_pasteButtonPastesWithoutConfirmation")
        table["ClipboardPasteUITests/testCB1_renamed"] = ["clipboard"]
        self.assertTrue(any("tables name tests that are not declared" in p for p in r.check_enumeration(ids, table)))

    def test_frozen_methods(self):
        ids = [i for i in enumeration() if "testACallerSuppliedPasteboardNameIsNotShown" not in i]
        table = {k: v for k, v in declarations().items() if "testACallerSupplied" not in k}
        self.assertTrue(any("frozen list" in p for p in r.check_enumeration(ids, table)))

    def test_declarations_reject_repeats_and_unknown_categories(self):
        for text in ('{"schema": 1, "tests": {"A/testA": [], "A/testA": []}}',
                     '{"schema": 1, "tests": {"A/testA": ["camera"]}}',
                     '{"schema": 1, "tests": {"A/testA": ["panels", "panels"]}}',
                     '{"schema": 2, "tests": {}}',
                     '{"schema": 1, "tests": {"A/helper": []}}'):
            with self.assertRaises(r.RunnerError, msg=text):
                r.parse_declarations(text)


class Selection(unittest.TestCase):
    def mac(self, allowed=r.MAC_CATEGORIES, feature=None, verified=None, qualification=None):
        return r.select_tests(enumeration(), declarations(), "mac", "26", allowed, feature, verified, qualification)

    def test_this_mac_never_selects_vm_only_or_deferred_tests(self):
        selected, excluded = self.mac()
        keys = set(keys_of(selected))
        table = declarations()
        self.assertFalse([k for k in keys if set(table[k]) & set(r.VM_ONLY_CATEGORIES)])
        self.assertFalse(keys & set(r.MAC_DEFERRED_TESTS))
        self.assertEqual(len(selected), 99)
        reasons = {r.key_from_enumeration_id(i): reason for i, _, reason in excluded}
        self.assertEqual(reasons["NotificationPermissionUITests/testNP1_requestPermissionAllow"], "vmOnly")
        self.assertEqual(reasons["ShareUITests/testS2_shareTextCopy"], "ownerUnverified")
        self.assertEqual(reasons["NotificationEventUITests/testN24_replyAction"], "macDeferred")
        self.assertTrue(all(reason in r.EXCLUSION_REASONS for reason in reasons.values()))

    def test_every_declared_category_must_be_allowed(self):
        # N18 declares badge and notification: badge alone is not enough ("all", not "any").
        selected, excluded = self.mac(allowed=("badge",))
        self.assertNotIn(ident("NotificationUITests/testN18_setBadgeCount"), selected)
        selected, _ = self.mac(allowed=("badge", "notification"))
        self.assertIn(ident("NotificationUITests/testN18_setBadgeCount"), selected)

    def test_nothing_allowed_runs_only_undeclared_tests(self):
        selected, _ = self.mac(allowed=())
        table = declarations()
        self.assertTrue(selected)
        self.assertFalse([i for i in selected if table[r.key_from_enumeration_id(i)]])

    def test_vm_only_categories_cannot_be_allowed_here(self):
        for category in r.VM_ONLY_CATEGORIES:
            with self.assertRaises(r.RunnerError):
                self.mac(allowed=("panels", category))
        with self.assertRaises(r.RunnerError):
            self.mac(allowed=("camera",))

    def test_the_vm_takes_no_allow_and_runs_everything_of_its_os(self):
        with self.assertRaises(r.RunnerError):
            r.select_tests(enumeration(), declarations(), "vm", "15", ["panels"])
        selected, excluded = r.select_tests(enumeration(), declarations(), "vm", "15", [])
        self.assertEqual(len(selected), 113)
        self.assertEqual(sorted(keys_of(i for i, _, _ in excluded)), sorted(r.OS_ONLY_TESTS))
        self.assertTrue(all(reason == "osOnly" for _, _, reason in excluded))

    def test_where_is_vm_or_mac_only(self):
        with self.assertRaises(r.RunnerError):
            r.select_tests(enumeration(), declarations(), "simulator", "15", [])

    def test_an_unchecked_target_keeps_a_test_deferred(self):
        selected, _ = self.mac(verified={"pickerCopy"})
        self.assertIn(ident("ShareUITests/testS2_shareTextCopy"), selected)
        self.assertNotIn(ident("NotificationEventUITests/testN24_replyAction"), selected)
        selected, _ = self.mac(verified={"notificationMenuItem"})
        self.assertIn(ident("NotificationEventUITests/testN23_openAction"), selected)
        self.assertNotIn(ident("NotificationEventUITests/testN24_replyAction"), selected)
        selected, _ = self.mac(verified={"notificationMenuItem", "replyInBanner"})
        self.assertIn(ident("NotificationEventUITests/testN24_replyAction"), selected)

    def test_feature_keeps_the_common_classes(self):
        selected, _ = self.mac(feature="Dialog")
        classes = {r.class_of(k) for k in keys_of(selected)}
        self.assertEqual(classes, {"DialogUITests", "SupportRuleTests", "NavigationUITests", "IdentifierInventoryUITests"})

    def test_the_watch_comes_first_and_only_with_notification(self):
        selected, _ = self.mac()
        invocations = r.build_invocations(enumeration(), selected, "mac")
        self.assertEqual(invocations[0]["stage"], "watch")
        self.assertEqual(invocations[0]["expected"], [r.WATCH_TEST])
        self.assertTrue(all(len(inv["expected"]) == 1 for inv in invocations))
        selected, _ = self.mac(allowed=(), feature="Dialog")
        invocations = r.build_invocations(enumeration(), selected, "mac", "Dialog")
        self.assertFalse([inv for inv in invocations if inv["stage"] == "watch"])
        self.assertNotIn(r.WATCH_TEST, [k for inv in invocations for k in inv["expected"]])

    def test_a_plan_with_notification_tests_needs_the_watch(self):
        without_watch = [i for i in enumeration() if i != ident(r.WATCH_TEST)]
        with self.assertRaises(r.RunnerError):
            r.make_plan("mac", without_watch, declarations(), r.MAC_CATEGORIES, None, "26", "h", "t", [], False, None)
        # Without notification allowed, N1 and N17 (declaring nothing) run without the watch.
        plan = r.make_plan("mac", without_watch, declarations(), (), None, "26", "h", "t", [], False, None)
        self.assertIn(ident("NotificationUITests/testN1_permissionIsAuthorized"), plan["selected"])

    def test_make_plan_refuses_an_empty_selection_on_this_mac(self):
        table = {k: (["notification"] if not v else v) for k, v in declarations().items()}
        with self.assertRaises(r.RunnerError):
            r.make_plan("mac", enumeration(), table, (), None, "26", "h", "t", [], False, None)

    def test_vm_invocations_follow_6_3(self):
        selected, _ = r.select_tests(enumeration(), declarations(), "vm", "15", [])
        invocations = r.build_invocations(enumeration(), selected, "vm")
        stages = [inv["stage"] for inv in invocations]
        self.assertEqual(stages[:3], ["permission"] * 3)
        self.assertEqual([inv["name"].split("/")[1] for inv in invocations[:3]], list(r.PERMISSION_ORDER))
        self.assertTrue(all(inv["prepare"] == ["ncreset"] for inv in invocations[:3]))
        self.assertEqual(stages[-1], "privacy")
        notification = [inv for inv in invocations if inv["class"] in r.NOTIFICATION_CLASSES]
        self.assertTrue(all(len(inv["expected"]) == 1 for inv in notification))
        self.assertEqual(notification[0]["expected"], [r.WATCH_TEST])
        self.assertEqual([inv["prepare"] for inv in notification if inv["prepare"]], [["ncui"]] * 3)
        share = [inv for inv in invocations if inv["class"] == "ShareUITests"]
        self.assertEqual(share[-1]["after"], ["stopMail"])
        named = sorted(k for inv in invocations for k in inv["expected"])
        self.assertEqual(named, sorted(keys_of(selected)))

    def test_name_each_test_in_the_vm(self):
        selected, _ = r.select_tests(enumeration(), declarations(), "vm", "15", [])
        invocations = r.build_invocations(enumeration(), selected, "vm", name_each_test=True)
        self.assertTrue(all(len(inv["expected"]) == 1 for inv in invocations if inv["stage"] != "privacy"))

    def test_only_testing_is_never_empty_or_a_class(self):
        with self.assertRaises(r.RunnerError):
            r.only_testing_arguments({"name": "x", "onlyTesting": []})
        with self.assertRaises(r.RunnerError):
            r.only_testing_arguments({"name": "x", "onlyTesting": ["MacLibraryExampleUITests/DialogUITests"]})
        self.assertEqual(r.only_testing_arguments({"name": "x", "onlyTesting": [ident("DialogUITests/testD1_showDialogOK")]}),
                         ["-only-testing:" + ident("DialogUITests/testD1_showDialogOK")])

    def test_the_second_check_before_xcodebuild(self):
        self.assertTrue(r.mac_selection_leaks([ident("ShareUITests/testS2_shareTextCopy")], ["clipboard", "sharepicker"]))
        self.assertFalse(r.mac_selection_leaks([ident("ShareUITests/testS1_shareTextPickerEscape")], ["sharepicker"]))

    def test_qualification_tests_are_only_in_their_stage(self):
        old = r.QUALIFICATION_ONLY_TESTS
        try:
            r.QUALIFICATION_ONLY_TESTS = {"mac26": frozenset({"DialogUITests/testD1_showDialogOK"}), "mac26-reply": frozenset(),
                                          "vm-ja": frozenset()}
            selected, excluded = self.mac()
            self.assertNotIn(ident("DialogUITests/testD1_showDialogOK"), selected)
            selected, _ = self.mac(qualification="mac26")
            self.assertEqual(selected, [ident("DialogUITests/testD1_showDialogOK")])
        finally:
            r.QUALIFICATION_ONLY_TESTS = old


def mac_plan(allowed=r.MAC_CATEGORIES, audit=None):
    return r.make_plan("mac", enumeration(), declarations(), allowed, None, "26", "a" * 40, "b" * 64, [], True,
                       audit or {"suites": ["DetectionUseCaseTests"], "expired": False, "hash": "c" * 64},
                       runner_files={"scripts/mac_ui_runner.py": "d" * 64}, declarations_hash="e" * 64)


class Approval(unittest.TestCase):
    def test_the_same_plan_is_approved(self):
        plan = mac_plan()
        approval = r.make_approval(plan)
        self.assertEqual(r.approval_problems(approval, plan), [])
        self.assertEqual(approval["unitTests"], ["MacLibraryTests/DetectionUseCaseTests"])

    def test_any_change_is_refused(self):
        plan = mac_plan()
        approval = r.make_approval(plan)
        for change in (lambda a: a["tests"].pop(),
                       lambda a: a.__setitem__("allow", ["panels"]),
                       lambda a: a.__setitem__("head", "f" * 40),
                       lambda a: a.__setitem__("extra", 1),
                       lambda a: a.pop("unitTests"),
                       lambda a: a.__setitem__("approvalId", "nothex"),
                       lambda a: a["tests"].reverse()):
            changed = json.loads(json.dumps(approval))
            change(changed)
            self.assertTrue(r.approval_problems(changed, plan), change)

    def test_another_plan_is_refused(self):
        approval = r.make_approval(mac_plan())
        self.assertTrue(r.approval_problems(approval, mac_plan(allowed=("panels",))))

    def test_a_changed_trusted_part_is_refused(self):
        plan = r.make_plan("mac", enumeration(), declarations(), r.MAC_CATEGORIES, None, "26", "a", "b",
                           [("Support/SampleApp.swift", "x", "y")], False, None)
        self.assertTrue(any("trusted part" in p for p in r.approval_problems(r.make_approval(plan), plan)))

    def test_the_vm_has_no_approval(self):
        plan = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], True, None)
        with self.assertRaises(r.RunnerError):
            r.make_approval(plan)

    def test_the_digest_covers_the_invocations(self):
        plan = mac_plan()
        digest = r.plan_digest(plan)
        plan["invocations"][0]["onlyTesting"].append(ident("ShareUITests/testS2_shareTextCopy"))
        self.assertNotEqual(r.plan_digest(plan), digest)


class Ledger(unittest.TestCase):
    def test_an_id_runs_once(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = pathlib.Path(d) / "ledger.log"
            r.consume_approval(ledger, "a" * 32)
            with self.assertRaises(r.RunnerError):
                r.consume_approval(ledger, "a" * 32)
            r.consume_approval(ledger, "b" * 32)
            self.assertEqual(r.ledger_ids(ledger.read_text()), ["a" * 32, "b" * 32])

    def test_a_broken_ledger_refuses(self):
        for text in ("aaaa\n", "a" * 32 + "\t2026-11-23T00:00:00+00:00\tmac", "a" * 32 + "\tyesterday\tmac\n"):
            with self.assertRaises(r.RunnerError):
                r.ledger_ids(text)

    def test_the_ledger_lives_under_the_account_home(self):
        self.assertTrue(str(r.DEFAULT_LEDGER).endswith("Library/Application Support/native-toolkit/test_mac-approvals.log"))


def good_facts():
    return {"hvVmmPresent": "1", "hwModel": "VirtualMac2,1", "osVersion": "15.8.3", "osBuild": "24H241",
            "mobileMeAccounts": "absent", "virtiofsMounts": "0", "xcodeVersion": "26.3", "xcodeBuild": "17C529",
            "language": "en-US", "platformUUID": "B8805D5E-AF5A-4C28-B721-5D49A04BCCE4", "arch": "arm64",
            "accounts": [{"type": "com.apple.account.iTunesStore", "authenticated": "0"},
                         {"type": "com.apple.account.HolidayCalendar", "authenticated": "1"},
                         {"type": "com.apple.account.OnMyDevice", "authenticated": "0"}],
            "tartProblems": []}


TART_PS = "/opt/homebrew/Cellar/tart/2.30.1/libexec/tart.app/Contents/MacOS/tart run ntk-vm --no-graphics --no-clipboard\n" \
          "/bin/zsh -c tart run ntk-vm --no-graphics --no-clipboard > log\n"


class VMQualification(unittest.TestCase):
    def failing(self, facts):
        return [name for name, ok in r.vm_qualification(facts) if not ok]

    def test_the_vm_as_it_is_passes(self):
        self.assertEqual(self.failing(good_facts()), [])
        self.assertIsNone(r.vm_language_problem(good_facts()))

    def test_each_fact_that_does_not_hold_fails_its_item(self):
        cases = {
            "hvVmmPresent": ("hvVmmPresent", "0"), "hwModelVirtualMac": ("hwModel", "Mac15,6"),
            "osVersion": ("osVersion", "15.8.2"), "noAppleAccount": ("mobileMeAccounts", "present"),
            "noSharedFolder": ("virtiofsMounts", "1"), "xcode": ("xcodeBuild", "17F113"),
            "identity": ("platformUUID", "not-a-uuid"), "tartRunArgs": ("tartProblems", ["x"]),
        }
        for item, (key, value) in cases.items():
            facts = good_facts()
            facts[key] = value
            self.assertIn(item, self.failing(facts), key)
            facts = good_facts()
            facts.pop(key)
            self.assertIn(item, self.failing(facts), f"{key} missing")

    def test_accounts(self):
        for accounts in ([], None,
                         [{"type": "com.apple.account.IMAP", "authenticated": "1"}],
                         [{"type": "com.apple.account.AppleAccount", "authenticated": "0"}],
                         [{"type": "com.apple.account.iTunesStore", "authenticated": "1"}],
                         [{"type": "com.apple.account.HolidayCalendar", "authenticated": "?"}]):
            facts = good_facts()
            facts["accounts"] = accounts
            self.assertIn("accountsOnlySystem", self.failing(facts), accounts)

    def test_tart_run_arguments(self):
        self.assertEqual(r.tart_run_problems(TART_PS, "ntk-vm"), [])
        self.assertTrue(r.tart_run_problems(TART_PS.replace(" --no-clipboard", "", 1), "ntk-vm"))
        self.assertTrue(r.tart_run_problems(TART_PS.replace("--no-graphics", "--dir=x:/Users", 1), "ntk-vm"))
        self.assertTrue(r.tart_run_problems(TART_PS.replace("--no-graphics", "--net-bridged=en0", 1), "ntk-vm"))
        self.assertTrue(r.tart_run_problems(TART_PS + TART_PS.splitlines()[0] + "\n", "ntk-vm"))
        self.assertTrue(r.tart_run_problems(TART_PS, "other-vm"))
        # The zsh line that only mentions `tart run` is not the tart process, nor is another program
        # whose arguments read `run <vm>`.
        self.assertTrue(r.tart_run_problems(TART_PS.splitlines()[1], "ntk-vm"))
        self.assertEqual(r.tart_run_problems(TART_PS + "/usr/local/bin/tartlike run ntk-vm --dir=x:/Users\n", "ntk-vm"), [])

    def test_language_is_the_environment(self):
        facts = good_facts()
        facts["language"] = "ja"
        self.assertIsNotNone(r.vm_language_problem(facts))
        self.assertIsNone(r.vm_language_problem(facts, "vm-ja"))


class OutputBoundary(unittest.TestCase):
    def test_codes_pass_and_text_does_not(self):
        message = ("NTK-STEP:overlay /Users/someone/secret.txt Mail from Alice NTK-STEP:notAStep "
                   "NTK-PRECONDITION:notAuthorized NTK-GATED:panels NTK-GATED:camera NTK-INTERRUPTED")
        codes = r.public_codes(message, VOCABULARY)
        self.assertEqual(codes, ["NTK-STEP:overlay", "NTK-GATED:panels", "NTK-PRECONDITION:notAuthorized", "NTK-INTERRUPTED"])
        self.assertFalse([c for c in codes if "secret" in c or "Alice" in c])

    def test_a_record_with_anything_else_is_refused(self):
        good = {"test": "MacLibraryExampleUITests/DialogUITests/testD1_showDialogOK", "result": "failed",
                "kind": "failed", "codes": ["NTK-STEP:alert"], "seconds": 3.5}
        self.assertEqual(r.public_record(good), good)
        for change in ({"message": "x"}, {"test": "/Users/x/y"}, {"codes": ["Mail from Alice"]},
                       {"codes": ["NTK-STEP:x y"]}, {"result": "maybe"}, {"reason": "because"}, {"seconds": "1"},
                       {"kind": "other"}, {"invocation": "a b"}, {"runs": 0}, {"runs": "2"}):
            record = dict(good)
            record.update(change)
            with self.assertRaises(r.RunnerError, msg=change):
                r.public_record(record)

    def test_the_step_vocabulary_comes_from_the_trusted_file(self):
        self.assertIn("overlay", VOCABULARY)
        self.assertEqual(len(VOCABULARY), len(set(VOCABULARY)))
        with self.assertRaises(r.RunnerError):
            r.step_vocabulary("enum Other {}")


def case(node, result, children=(), seconds=1.0):
    entry = {"nodeType": "Test Case", "nodeIdentifier": node, "result": result, "durationInSeconds": seconds,
             "children": [{"nodeType": "Failure Message", "name": c} if isinstance(c, str) else c for c in children]}
    return entry


def tests_json(cases, bundle="MacLibraryExampleUITests"):
    return json.dumps({"devices": [{"deviceId": "x"}], "testNodes": [
        {"nodeType": "Test Plan", "children": [{"nodeType": "UI test bundle", "name": bundle, "children": [
            {"nodeType": "Test Suite", "children": list(cases)}]}]}]})


def summary_json(cases):
    count = {"Passed": 0, "Failed": 0, "Skipped": 0, "Expected Failure": 0}
    for c in cases:
        count[c["result"]] = count.get(c["result"], 0) + 1
    return json.dumps({"totalTestCount": len(cases), "passedTests": count["Passed"], "failedTests": count["Failed"],
                       "skippedTests": count["Skipped"], "expectedFailures": count["Expected Failure"]})


D1 = "DialogUITests/testD1_showDialogOK"
D2 = "DialogUITests/testD2_showDialogCancel"


class Results(unittest.TestCase):
    def invocation(self, keys=(D1, D2)):
        return {"name": "DialogUITests", "expected": list(keys), "timeout": 60}

    def test_a_clean_run(self):
        cases = [case(D1 + "()", "Passed"), case(D2 + "()", "Failed", ["NTK-STEP:alert /Users/x/private.txt"])]
        records, stop = r.record_invocation(self.invocation(), tests_json(cases), summary_json(cases), 1, False, VOCABULARY)
        self.assertFalse(stop)
        self.assertEqual([(x["test"], x["result"]) for x in records],
                         [("MacLibraryExampleUITests/" + D1, "passed"), ("MacLibraryExampleUITests/" + D2, "failed")])
        self.assertEqual(records[1]["codes"], ["NTK-STEP:alert"])
        self.assertNotIn("private", json.dumps(records))

    def test_results_must_be_exactly_the_names(self):
        cases = [case(D1 + "()", "Passed")]
        records, stop = r.record_invocation(self.invocation(), tests_json(cases), summary_json(cases), 0, False, VOCABULARY)
        self.assertTrue(stop)
        self.assertTrue(any(x["test"].endswith("#namedSet") for x in records))
        cases = [case(D1 + "()", "Passed"), case(D1 + "()", "Passed")]
        records, stop = r.record_invocation(self.invocation([D1]), tests_json(cases), summary_json(cases), 0, False, VOCABULARY)
        self.assertTrue(stop)

    def test_shapes_the_runner_does_not_know_stop(self):
        cases = [case(D1 + "()", "Passed", [{"nodeType": "Repetition", "name": "1"}])]
        records, stop = r.record_invocation(self.invocation([D1]), tests_json(cases), summary_json(cases), 0, False, VOCABULARY)
        self.assertTrue(stop)
        self.assertTrue(any(x["test"].endswith("#unknownShape") for x in records))
        cases = [case("DialogUITests/helper", "Passed")]
        _, stop = r.record_invocation(self.invocation([D1]), tests_json(cases), summary_json(cases), 0, False, VOCABULARY)
        self.assertTrue(stop)
        cases = [case(D1 + "()", "Passed")]
        _, stop = r.record_invocation(self.invocation([D1]), tests_json(cases, "Other"), summary_json(cases), 0, False, VOCABULARY)
        self.assertTrue(stop)

    def test_no_bundle_time_out_and_summary(self):
        records, stop = r.record_invocation(self.invocation(), None, None, 65, False, VOCABULARY)
        self.assertTrue(stop)
        cases = [case(D1 + "()", "Passed")]
        _, stop = r.record_invocation(self.invocation([D1]), tests_json(cases), summary_json(cases), 142, True, VOCABULARY)
        self.assertTrue(stop)
        bad_summary = json.dumps({"totalTestCount": 2, "passedTests": 2})
        _, stop = r.record_invocation(self.invocation([D1]), tests_json(cases), bad_summary, 0, False, VOCABULARY)
        self.assertTrue(stop)

    def test_classification(self):
        self.assertEqual(r.classify(D1, "Passed", None), "passed")
        for result, reason in (("Skipped", "NTK-GATED:panels"), ("Skipped", "NTK-PRECONDITION:notAuthorized"),
                               ("Skipped", "anything"), ("Expected Failure", None), ("Mixed", None)):
            self.assertEqual(r.classify(D1, result, reason), "failed", (result, reason))

    def test_the_real_dialog_results(self):
        tests = fixture("xcresult-dialog-tests.json")
        summary = fixture("xcresult-dialog-summary.json")
        cases, _ = r.parse_xcresult_tests(tests)
        keys = [r.key_from_node_id(c["node"]) for c in cases]
        records, stop = r.record_invocation({"name": "DialogUITests", "expected": keys, "timeout": 60}, tests, summary, 0,
                                            False, VOCABULARY)
        self.assertFalse(stop)
        self.assertEqual(len(records), 17)
        self.assertTrue(all(x["result"] == "passed" and x["seconds"] > 0 for x in records))

    def test_the_real_unit_results(self):
        records = r.unit_records("MacLibraryTests", fixture("xcresult-unit-tests.json"), 0, VOCABULARY)
        self.assertGreater(len(records), 300)
        self.assertTrue(all(x["result"] == "passed" for x in records))
        self.assertEqual(len({x["test"] for x in records}), len(records))
        # Nested suites keep three parts; parameterized tests count their expanded runs.
        self.assertTrue(any(x["test"].count("/") == 3 for x in records))
        self.assertEqual(sum(x["runs"] for x in records), 352)
        self.assertEqual(len(records), 308)

    def test_argument_values_never_leave(self):
        tests = json.dumps({"testNodes": [{"nodeType": "Unit test bundle", "name": "MacLibraryTests", "children": [
            case("Suite/check(value:)", "Passed", [{"nodeType": "Arguments", "name": "/Users/x/secret"},
                                                   {"nodeType": "Arguments", "name": "2"}])]}]})
        records = r.unit_records("MacLibraryTests", tests, 0, VOCABULARY)
        self.assertEqual(records, [{"test": "MacLibraryTests/Suite/check", "result": "passed", "kind": "passed",
                                    "codes": [], "seconds": 1.0, "runs": 2}])

    def test_not_run_records_are_failures(self):
        records = r.not_run_records([{"expected": [D1, D2]}], "notificationStopped")
        self.assertTrue(all(x["result"] == "failed" and x["codes"] == ["NTK-STOP:notificationUI"] for x in records))


class Stale(unittest.TestCase):
    ROOT_DIR = "/private/var/folders/x/T/ntk-test-mac.abc"
    XCODE = "/Applications/Xcode26.6.app/Contents"

    def marker(self, **change):
        marker = {"boottime": 1000, "created": 5000.0, "root": self.ROOT_DIR, "pgid": 300,
                  "writers": [{"pid": 300, "start": 5001, "exe": self.XCODE + "/Developer/usr/bin/xcodebuild"}]}
        marker.update(change)
        return marker

    def proc(self, pid, start, exe, pgid=None):
        return {"pid": pid, "pgid": pgid if pgid is not None else pid, "start": start, "exe": exe}

    def test_a_writer_alive_is_stopped_with_its_group(self):
        processes = [self.proc(300, 5001, self.XCODE + "/Developer/usr/bin/xcodebuild"),
                     self.proc(301, 5003, self.ROOT_DIR + "/dd-ui/Build/Products/Debug/MacLibraryExample.app/Contents/MacOS/MacLibraryExample", 300)]
        plan = r.stale_plan(self.marker(), 1000, processes, [self.XCODE])
        self.assertEqual(plan["signal"], [300, 301])
        self.assertEqual(plan["group"], 300)

    def test_a_reused_pid_with_another_executable_is_left_alone(self):  # (a)
        plan = r.stale_plan(self.marker(), 1000, [self.proc(300, 5001, "/usr/bin/vim")], [self.XCODE])
        self.assertEqual(plan["signal"], [])
        self.assertTrue(plan["removeOnly"])

    def test_a_reused_pid_with_another_start_is_left_alone(self):  # (b)
        plan = r.stale_plan(self.marker(), 1000, [self.proc(300, 6000, self.XCODE + "/Developer/usr/bin/xcodebuild")],
                            [self.XCODE])
        self.assertEqual(plan["signal"], [])

    def test_a_marker_of_an_earlier_boot_only_removes(self):  # (c)
        processes = [self.proc(300, 5001, self.XCODE + "/Developer/usr/bin/xcodebuild")]
        plan = r.stale_plan(self.marker(), 2000, processes, [self.XCODE])
        self.assertEqual((plan["signal"], plan["removeOnly"]), ([], True))
        self.assertIsNotNone(r.stale_plan(self.marker(), 500, processes, [self.XCODE])["refuse"])

    def test_a_group_with_a_stranger_is_not_signalled_as_a_group(self):  # (d)
        processes = [self.proc(300, 5001, self.XCODE + "/Developer/usr/bin/xcodebuild"),
                     self.proc(302, 4000, "/Applications/Safari.app/Contents/MacOS/Safari", 300)]
        plan = r.stale_plan(self.marker(), 1000, processes, [self.XCODE])
        self.assertIsNone(plan["group"])
        self.assertEqual(plan["signal"], [300])

    def test_a_sample_woken_by_a_notification_is_a_writer(self):  # (e)
        exe = self.ROOT_DIR + "/dd-ui/Build/Products/Debug/MacLibraryExample.app/Contents/MacOS/MacLibraryExample"
        plan = r.stale_plan(self.marker(), 1000, [self.proc(900, 5100, exe, 900)], [self.XCODE])
        self.assertEqual(plan["signal"], [900])
        before = r.stale_plan(self.marker(), 1000, [self.proc(900, 4000, exe, 900)], [self.XCODE])
        self.assertEqual(before["signal"], [])

    def test_a_malformed_marker_is_refused(self):
        self.assertIsNotNone(r.stale_plan({"root": "x"}, 1000, [], [])["refuse"])

    def test_a_real_left_process_is_found_stopped_and_its_folder_removed(self):
        scan = pathlib.Path(tempfile.mkdtemp(prefix="ntk-stale-scan."))
        try:
            folder = scan / (r.RUN_FOLDER_PREFIX + "selftest")
            folder.mkdir()
            self.assertEqual(r.main(["marker", "--root", str(folder), "--run-id", "x"]), 0)
            time.sleep(1.1)
            sleeper = folder / "sleeper"
            # A copy of /bin/sleep is killed by code signing; a fresh ad-hoc build runs.
            built = subprocess.run(["xcrun", "clang", "-x", "c", "-o", str(sleeper), "-"], capture_output=True,
                                   input=b"#include <unistd.h>\nint main(void) { sleep(60); return 0; }\n")
            if built.returncode != 0:
                self.skipTest("no C compiler to build the stand-in writer")
            child = subprocess.Popen([str(sleeper)])
            try:
                time.sleep(0.5)
                out = folder.parent / "list.json"
                self.assertEqual(r.main(["stale", "--scan-root", str(scan), "--list", "--out", str(out)]), 0)
                self.assertEqual(json.loads(out.read_text()), [{"processes": 1}])
                self.assertEqual(r.main(["stale", "--scan-root", str(scan)]), 0)
                self.assertIsNotNone(child.wait(timeout=40))
                self.assertFalse(folder.exists())
            finally:
                if child.poll() is None:
                    child.kill()
        finally:
            shutil.rmtree(scan, ignore_errors=True)


class Audit(unittest.TestCase):
    def audit(self, **change):
        audit = {"schema": 1, "treeHash": "t", "review": {"by": "another model"},
                 "suites": [{"suite": "MacClipboardManagerTests", "file": "M.swift",
                             "allowed": [{"word": ".general", "count": 2, "reason": "passed to the mock"}]}]}
        audit.update(change)
        return audit

    def test_word_counts(self):
        counts = r.audit_word_counts("let p = NSPasteboard.general\nresolve(.general)\nx(scope: .general)\nMacShareManager.shared")
        self.assertEqual(counts, {"NSPasteboard.general": 1, ".general": 2, "MacShareManager.shared": 1})

    def test_allowed_occurrences_must_match(self):
        mock = "repo.copy(scope: .general)\nrepo.read(scope: .general)\n"
        self.assertEqual(r.audit_state(self.audit(), "t", {"M.swift": mock})["suites"], ["MacClipboardManagerTests"])
        for text in (mock + "PasteboardResolver.resolve(.general)\n", mock + "MacClipboardManager.shared.copy()\n",
                     "repo.copy(scope: .general)\n", mock + "NSPasteboard.general.clearContents()\n"):
            self.assertEqual(r.audit_state(self.audit(), "t", {"M.swift": text})["suites"], [], text)

    def test_a_reason_is_required(self):
        audit = self.audit()
        audit["suites"][0]["allowed"][0]["reason"] = ""
        self.assertEqual(r.audit_state(audit, "t", {"M.swift": "a(.general)\nb(.general)\n"})["suites"], [])

    def test_an_expired_or_unreviewed_table_selects_nothing(self):
        mock = "repo.copy(scope: .general)\nrepo.read(scope: .general)\n"
        state = r.audit_state(self.audit(), "other", {"M.swift": mock})
        self.assertEqual((state["suites"], state["expired"]), ([], True))
        state = r.audit_state(self.audit(review=None), "t", {"M.swift": mock})
        self.assertEqual((state["suites"], state["expired"]), ([], True))
        plan = mac_plan(audit=state)
        self.assertEqual(plan["unitInvocations"], [])
        self.assertEqual(plan["unitExcluded"], [{"target": "MacLibraryTests", "reason": "auditExpired"}])

    def test_the_repository_table_is_bound_to_the_tree(self):
        audit = json.loads((ROOT / r.AUDIT_FILE).read_text(encoding="utf-8"))
        self.assertEqual(audit["schema"], 1)
        self.assertTrue(all(a["reason"] for s in audit["suites"] for a in s["allowed"]))
        self.assertNotIn("SharePickerPresenterTests", [s["suite"] for s in audit["suites"]])
        self.assertNotIn("PasteboardResolverTests", [s["suite"] for s in audit["suites"]])


class ReplyState(unittest.TestCase):
    ROOT_FRAME = (100, 100, 300, 80)
    MARGIN = 8

    def classify(self, before=None, after=None, fields=None, root=None, margin=None):
        return r.classify_reply_state(root if root is not None else self.ROOT_FRAME,
                                      before if before is not None else [[96, 96, 308, 88]],
                                      after if after is not None else [[96, 96, 308, 88]],
                                      fields if fields is not None else [{"inRoot": True, "focused": True}],
                                      self.MARGIN if margin is None else margin)

    def test_reply_inside_the_banner(self):
        self.assertEqual(self.classify(), "banner")

    def test_the_margin_boundary(self):
        self.assertEqual(self.classify(after=[[92, 92, 316, 96]]), "banner")
        self.assertEqual(self.classify(after=[[91, 92, 317, 96]]), "list")

    def test_a_new_window_or_growth_is_the_list(self):
        self.assertEqual(self.classify(after=[[96, 96, 308, 88], [0, 0, 400, 900]]), "list")
        self.assertEqual(self.classify(after=[[96, 96, 308, 400]]), "list")

    def test_the_field_must_be_one_focused_in_the_root(self):
        for fields in ([], [{"inRoot": True, "focused": False}],
                       [{"inRoot": True, "focused": True}, {"inRoot": True, "focused": False}],
                       [{"inRoot": False, "focused": True}], [{"inRoot": True}]):
            self.assertEqual(self.classify(fields=fields), "unknown", fields)

    def test_a_large_window_holding_the_banner_is_unknown(self):
        # The list may open inside one big window without changing the count or the frame.
        big = [[0, 0, 1200, 900]]
        self.assertEqual(self.classify(before=big, after=big), "unknown")

    def test_missing_values_are_unknown(self):
        self.assertEqual(self.classify(root=[1, 2, 3]), "unknown")
        self.assertEqual(self.classify(before=[[1, 2, 3, None]]), "unknown")
        self.assertEqual(self.classify(before=[]), "unknown")
        self.assertEqual(self.classify(margin=-1), "unknown")
        self.assertEqual(r.classify_reply_state(self.ROOT_FRAME, None, [], [], 8), "unknown")

    def test_a_window_that_lost_the_root_is_unknown(self):
        self.assertEqual(self.classify(after=[[600, 600, 10, 10]]), "unknown")


class Baseline(unittest.TestCase):
    def test_changed_added_removed_and_excluded(self):
        lines, lost = r.compare_with_baseline({"a": "passed", "b": "failed", "d": "passed"},
                                              {"a": "passed", "b": "passed", "c": "passed"}, {"c"},
                                              {"x": "osOnly"}, {"x": "osOnly", "y": "vmOnly"})
        self.assertTrue(lines[0].startswith("changed=1, added=1, removed=1"))
        self.assertIn("excluded changed=1", lines[0])
        self.assertEqual(lost, ["c"])

    def test_lost_coverage_by_a_skip(self):
        _, lost = r.compare_with_baseline({"a": "skipped"}, {"a": "passed"}, set())
        self.assertEqual(lost, ["a"])

    def test_names(self):
        self.assertEqual(r.baseline_name("vm", "15.8.3"), "test_mac.baseline.vm-15.8.3.json")
        for where, version in (("mac", "Mac Studio"), ("simulator", "26.2"), ("vm", "")):
            with self.assertRaises(r.RunnerError):
                r.baseline_name(where, version)

    def test_refusals(self):
        vm_env = {"os": "15.8.3", "osBuild": "24H241", "language": "en-US"}
        full = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], True, None)
        self.assertIsNone(r.baseline_refusal(vm_env, full, False, False))
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, True, False))
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, False, True))
        self.assertIsNotNone(r.baseline_refusal(dict(vm_env, language="ja"), full, False, False))
        feature = r.make_plan("vm", enumeration(), declarations(), (), "Dialog", "15", "a", "b", [], False, None)
        self.assertIsNotNone(r.baseline_refusal(vm_env, feature, False, False))
        no_unit = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], False, None)
        self.assertIsNotNone(r.baseline_refusal(vm_env, no_unit, False, False))
        mac_env = {"os": "26.7.3"}
        self.assertIsNone(r.baseline_refusal(mac_env, mac_plan(), False, False))
        self.assertIsNotNone(r.baseline_refusal(mac_env, mac_plan(allowed=("panels",)), False, False))
        expired = mac_plan(audit={"suites": [], "expired": True, "hash": None})
        self.assertIsNotNone(r.baseline_refusal(mac_env, expired, False, False))

    def test_the_baseline_keeps_eligible_executed_and_excluded(self):
        plan = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], True, None)
        results = {"MacLibraryExampleUITests/" + D1: "passed"}
        baseline = r.make_baseline({"os": "15.8.3"}, plan, results, {D1: 3.0}, "2026-11-23T00:00:00+00:00")
        self.assertEqual(len(baseline["eligible"]), 113)
        self.assertEqual(baseline["executed"], ["MacLibraryExampleUITests/" + D1])
        self.assertEqual(sorted(baseline["excluded"]), sorted(r.OS_ONLY_TESTS))
        self.assertEqual(baseline["source"]["head"], "a")

    def test_the_estimate_reads_the_baseline_seconds(self):
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / "test_mac.baseline.vm-15.8.3.json").write_text(json.dumps({"seconds": {D1: 7.0}}))
            durations = r._durations(d, "26.7.3", "mac")
            plan = mac_plan()
            keys = [k for inv in plan["invocations"] for k in inv["expected"]]
            self.assertIn(D1, keys)
            self.assertEqual(r.estimate_seconds([D1], durations, per_call=0), 7)

    def test_the_estimate(self):
        self.assertEqual(r.estimate_seconds(["a", "b"], {"a": 10}, default=60, per_call=5), 80)


class Coverage(unittest.TestCase):
    def test_the_buttons_come_from_the_sample(self):
        buttons = r.expected_buttons({n: (SAMPLE_DIR / f).read_text() for n, f in (
            ("dialog", "DialogSampleView.swift"), ("notification", "NotificationSampleView.swift"),
            ("share", "ShareSampleView.swift"))})
        self.assertEqual(len(buttons), 43)
        self.assertIn("notification.button.SetBadgeCount1", buttons)

    def write(self, d, name, value):
        (pathlib.Path(d) / name).write_text(value)

    def test_every_test_one_attachment_and_every_button(self):
        with tempfile.TemporaryDirectory() as d:
            self.write(d, "1.json", json.dumps(["dialog.button.A"]))
            self.write(d, "2.json", json.dumps(["dialog.button.B"]))
            manifest = [{"testIdentifier": D1 + "()", "attachments": [
                {"suggestedHumanReadableName": "ntk-button-coverage-v1_0_ABC.json", "exportedFileName": "1.json"}]},
                {"testIdentifier": D2 + "()", "attachments": [
                    {"suggestedHumanReadableName": "ntk-button-coverage-v1.json", "exportedFileName": "2.json"}]}]
            buttons = ["dialog.button.A", "dialog.button.B"]
            self.assertEqual(r.coverage_problems(manifest, d, [D1, D2], buttons), [])
            self.assertTrue(r.coverage_problems(manifest, d, [D1, D2], buttons + ["dialog.button.C"]))
            self.assertTrue(r.coverage_problems(manifest[:1], d, [D1, D2], buttons[:1]))
            self.write(d, "2.json", "{broken")
            self.assertTrue(r.coverage_problems(manifest, d, [D1, D2], buttons[:1]))
            twice = manifest + [manifest[0]]
            self.assertTrue(r.coverage_problems(twice, d, [D1], buttons[:1]))


class Fixture(unittest.TestCase):
    def make(self):
        root = pathlib.Path("/private/tmp/ntk-uitest-selftest-" + os.urandom(3).hex())
        (root / "dirA").mkdir(parents=True)
        (root / "dirB").mkdir()
        for name in ("a.txt", "b.txt", "note.md", "pic.png", "default.txt"):
            (root / name).write_text(name)
        return root

    def test_the_ds_store_aside_any_change_is_found(self):
        root = self.make()
        try:
            before = r.fixture_manifest(root)
            (root / ".DS_Store").write_text("panel")
            self.assertEqual(r.fixture_problems(before, r.fixture_manifest(root)), [])
            (root / "default.txt").write_text("written")
            self.assertTrue(r.fixture_problems(before, r.fixture_manifest(root)))
            (root / "default.txt").write_text("default.txt")
            (root / "new-file.txt").write_text("")
            self.assertTrue(r.fixture_problems(before, r.fixture_manifest(root)))
            (root / "new-file.txt").unlink()
            os.symlink("/etc", root / "dirA" / "link")
            self.assertTrue(r.fixture_problems(before, r.fixture_manifest(root)))
        finally:
            shutil.rmtree(root)

    def test_a_symlink_fails_even_when_unchanged(self):
        manifest = {name: "x" for name in r.FIXTURE_ITEMS}
        manifest["dirA/link"] = "symlink"
        self.assertTrue(r.fixture_problems(manifest, dict(manifest)))
        manifest.pop("dirA/link")
        self.assertEqual(r.fixture_problems(manifest, dict(manifest)), [])

    def test_only_the_fixture_folder(self):
        with self.assertRaises(r.RunnerError):
            r.fixture_manifest("/Users/someone")


LSDUMP = """bundle id:   1
path:        /Users/me/Library/Developer/Xcode/DerivedData/MacWorkspace-abc/Build/Products/Debug/MacLibraryExample.app (0x1)
identifier:  com.jonghyunkim.mac.nativetoolkit.example
----------------------------------------------------------------
bundle id:   2
path:        /private/var/folders/T/ntk-test-mac.x/dd-ui/Build/Products/Debug/MacLibraryExample.app (0x2)
identifier:  com.jonghyunkim.mac.nativetoolkit.example
----------------------------------------------------------------
bundle id:   3
path:        /Applications/Safari.app (0x3)
identifier:  com.apple.Safari
----------------------------------------------------------------
bundle id:   4
path:        /Users/me/repo/mac/MacLibraryExample/build/x/MacLibraryExampleUITests-Runner.app (0x4)
identifier:  mac.library.example.MacLibraryExampleUITests.xctrunner
"""


class LaunchServices(unittest.TestCase):
    def test_copies_outside_this_run_with_marks_only(self):
        copies = r.lsregister_copies(LSDUMP, (r.SAMPLE_BUNDLE_ID, r.RUNNER_BUNDLE_ID), "/private/var/folders/T/ntk-test-mac.x",
                                     "/Users/me/repo", "/Users/me/Library/Developer/Xcode/DerivedData")
        self.assertEqual([c["place"] for c in copies], ["derivedData", "repository"])
        self.assertTrue(all(re.fullmatch(r"[0-9a-f]{12}", c["mark"]) for c in copies))

    def test_the_copy_mark(self):
        self.assertTrue(re.fullmatch(r"copy=[0-9a-f]{12}", r.copy_mark("/private/tmp")))


def copy_tests():
    d = tempfile.mkdtemp(prefix="ntk-mac-tests.")
    shutil.copytree(TESTS_DIR, pathlib.Path(d) / "tests")
    return pathlib.Path(d), pathlib.Path(d) / "tests"


class SourceRules(unittest.TestCase):
    def test_the_real_folder_passes(self):
        self.assertEqual(r.check_test_folder(TESTS_DIR, PBXPROJ.read_text()), [])
        self.assertEqual(r.frozen_file_problems(TESTS_DIR), [])
        self.assertEqual(r.trusted_part_changes(TESTS_DIR), [])

    def problems_after(self, relative, old, new):
        base, tests = copy_tests()
        try:
            path = tests / relative
            if old is None:
                path.write_text(new)
            else:
                text = path.read_text()
                self.assertEqual(text.count(old), 1, old)
                path.write_text(text.replace(old, new))
            return r.check_test_folder(tests, PBXPROJ.read_text()) + r.frozen_file_problems(tests), \
                r.trusted_part_changes(tests)
        finally:
            shutil.rmtree(base)

    def test_breaking_a_test_file(self):
        cases = [
            ("DialogUITests.swift", "import XCTest\n", "import XCTest\n#if DEBUG\n#endif\n"),
            ("DialogUITests.swift", "final class DialogUITests", "class DialogUITests"),
            ("DialogUITests.swift", "import XCTest\n", "import XCTest\nimport AppKit\n"),
            ("DialogUITests.swift", "import XCTest\n", "import XCTest\nlet x = supportRoot\n"),
            ("DialogUITests.swift", "import XCTest\n", "import XCTest\nfunc f(e: XCUIElement) { e.typeText(\"a\") }\n"),
            ("DialogUITests.swift", "import XCTest\n", "import XCTest\nlet s = \"dialog.button.ShowDialog\"\n"),
            ("DialogUITests.swift", "import XCTest\n", "import XCTest\nfunc g() { XCTExpectFailure(\"x\") }\n"),
            ("DialogUITests.swift", "import XCTest\n", "import XCTest\nextension DialogUITests {}\n"),
            ("NavigationUITests.swift", "    func testM1a_menuOpensEachScreen() throws {",
             "    func testM1a_menuOpensEachScreen() async throws {"),
        ]
        for relative, old, new in cases:
            problems, _ = self.problems_after(relative, old, new)
            self.assertTrue(problems, new)

    def test_breaking_a_frozen_file(self):
        problems, _ = self.problems_after("ClipboardSampleWaitRuleTests.swift", "import XCTest\n", "import XCTest\n\n")
        self.assertTrue(any("frozen" in p for p in problems))

    def test_breaking_the_trusted_part(self):
        _, changes = self.problems_after("Support/SampleApp.swift", "import AppKit\n", "import AppKit\n\n")
        self.assertEqual([c[0] for c in changes], ["Support/SampleApp.swift"])
        problems, _ = self.problems_after("Support/Extra.swift", None, "import Foundation\n")
        self.assertTrue(any("not in the trusted table" in p for p in problems))

    def test_regex_literals_and_division(self):
        tokens = r.lex('let m = text.firstMatch(of: /let name = "([^"]+)"/)\nlet q = a / b / c\nlet e = #/x"y/#\n')
        self.assertEqual([t.text for t in tokens if t.kind == "regex"], ['/let name = "([^"]+)"/', '#/x"y/#'])
        self.assertFalse([t for t in tokens if t.kind == "string"])
        self.assertEqual(sum(1 for t in tokens if t.kind == "punct" and t.text == "/"), 2)

    def test_a_bundle_table_that_differs(self):
        with tempfile.TemporaryDirectory() as d:
            copy = pathlib.Path(d) / "DeviceRequirements.json"
            copy.write_text((TESTS_DIR / r.DECLARATIONS_FILE).read_text() + " ")
            self.assertTrue(r.bundle_declaration_problems(TESTS_DIR / r.DECLARATIONS_FILE, [copy]))
            self.assertTrue(r.bundle_declaration_problems(TESTS_DIR / r.DECLARATIONS_FILE, []))


class BinaryInventory(unittest.TestCase):
    def test_the_real_bundle_holds_the_enumerated_tests(self):
        keys = r.binary_test_keys(r.parse_otool_classes(fixture("otool-ov.txt"), fixture("otool-l.txt")))
        self.assertEqual(r.binary_inventory_problems(keys, enumeration()), [])
        self.assertTrue(r.binary_inventory_problems(keys[1:], enumeration()))
        self.assertTrue(r.binary_inventory_problems(keys + [keys[0]], enumeration()))


def function_body(text, name):
    m = re.search(r"^" + re.escape(name) + r"\(\) \{[^\n]*\n(.*?)^\}\n", text, re.S | re.M)
    assert m, name
    return m.group(1)


class ShellOrder(unittest.TestCase):
    """Design 7 "中断": the trap before the first xcodebuild, HUP included, the children stopped
    before the folder goes; every xcodebuild of this Mac behind the gate."""

    def setUp(self):
        self.text = SCRIPT.read_text()

    def test_the_trap_comes_before_the_first_xcodebuild_of_this_mac(self):
        body = function_body(self.text, "run_mac")
        trap = body.index("trap mac_cleanup EXIT")
        self.assertLess(trap, body.index("mac_xcodebuild "))
        self.assertLess(body.index("trap 'exit 129' HUP"), body.index("mac_xcodebuild "))
        self.assertLess(body.index("runner approve"), trap)

    def test_the_cleanup_stops_before_it_removes(self):
        body = function_body(self.text, "mac_cleanup")
        self.assertLess(body.index('kill -TERM "-${pid}"'), body.index('rm -rf "${MAC_TMP}"'))
        self.assertLess(body.index("pkill -KILL"), body.index('rm -rf "${MAC_TMP}"'))
        self.assertLess(body.index('"${LSREGISTER}" -u'), body.index('rm -rf "${MAC_TMP}"'))

    def test_every_xcodebuild_of_this_mac_passes_the_gate(self):
        body = function_body(self.text, "run_mac")
        direct = [line for line in body.splitlines() if re.search(r"(^|\s)xcodebuild\s", line)
                  and "mac_xcodebuild" not in line and "-version" not in line]
        self.assertEqual(direct, [])
        gate = function_body(self.text, "mac_xcodebuild")
        self.assertLess(gate.index("mac_gate"), gate.index("capped_group"))

    def test_every_ssh_command_checks_the_identity(self):
        body = function_body(self.text, "vm_ssh")
        self.assertIn("IOPlatformUUID", body)
        self.assertIn("[ \\\"\\$u\\\" = '${VM_UUID}' ] || {", body)
        self.assertIn("exit 96; }; $*", body)
        self.assertEqual(function_body(self.text, "vm_op").count("vm_ssh "), 1)

    def test_the_in_vm_half_refuses_this_mac(self):
        body = function_body(self.text, "in_vm_main")
        self.assertIn('sysctl -n kern.hv_vmm_present', body.splitlines()[1])

    def test_where_is_required(self):
        # The script runs with a PATH that holds only what its argument checks need: whatever a
        # broken check (or a mutation) lets through cannot reach ssh, tart, xcodebuild, pkill, defaults
        # or the clock. The in-VM half is never run here (the check above reads it instead).
        with tempfile.TemporaryDirectory() as tools:
            for name in ("dirname", "basename", "python3"):
                found = shutil.which(name)
                if found:
                    os.symlink(found, pathlib.Path(tools) / name)
            env = {"PATH": tools, "HOME": tools}

            def run(*args):
                return subprocess.run(["/bin/bash", str(SCRIPT), *args], capture_output=True, text=True, env=env, timeout=60)

            finished = run()
            self.assertNotEqual(finished.returncode, 0)
            self.assertIn("--where vm|mac is required", finished.stderr)
            self.assertIn("--approved", run("--where", "mac").stderr)
            self.assertIn("for --where mac", run("--where", "vm", "--allow", "panels").stderr)
            self.assertIn("separate runs", run("--where", "mac", "--dry-run", "--approved", "x").stderr)


if __name__ == "__main__":
    unittest.main()
