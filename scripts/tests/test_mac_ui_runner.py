"""Self-tests of scripts/mac_ui_runner.py and the order of scripts/test_mac.sh.

The runner keeps the UI tests off the parts of the user's own Mac they were not allowed to touch and
checks that the VM is the qualified one (macOS UI test design, U-9, 3.4 and 6.3). A runner that
quietly selects too much, or a check that quietly stops checking, looks exactly like one that works,
so every case here breaks one decision on purpose (design chapter 7, the runner's rows) and asserts
that it is caught, next to the near-miss that must pass.

On this Mac nothing here reaches the operating system's real operations: before the runner is imported,
os.kill, os.killpg and every subprocess but `git` and a `/bin/bash` with a PATH of three harmless tools are
replaced by guards that fail the test (review v1: Claude A-3, Codex B-4). The cleanup of run folders is
tested through a fake port (the runner has no way to signal there at all: review v5). The one exception
is RealProcessesInTheVM: only when the two facts of the VM hold (kern.hv_vmm_present 1 and a VirtualMac
model; this Mac skips it), it starts the supervisor perl with sh and sleep and signals those, its own
children only (review v4: Codex B-3; v5: Codex C-1). The script's VM half (`--in-vm`) is never run: a bash with `--in-vm` passes the
guard only for a truncated copy of the prelude whose fact readers are fakes (review v2: Claude B-2,
Codex A-1, B-4). The `--in-vm` path cannot be narrowed by PATH (it starts again with its own PATH). The mutation
harness runs these tests in the VM only (scripts/tests/mac_ui_runner_mutations.py).

The fixtures in fixtures/mac_ui_runner/ are real output of Xcode 26.3 in the VM (macOS 15.8.3), stage
0d (2026-11-23), with the VM's home folder replaced by <home>:
  enumeration.json        -enumerate-tests -test-enumeration-style flat -test-enumeration-format json
                          (the UI tests and MacLibraryExampleTests)
  unit-enumeration.json   the same for the MacLibrary scheme (MacLibraryTests)
  otool-ov.txt, otool-l.txt
                          otool -arch arm64 -ov / -l of MacLibraryExampleUITests.xctest
  xcresult-dialog-tests.json, xcresult-dialog-summary.json
                          xcresulttool get test-results tests / summary of the DialogUITests call
  xcresult-unit-tests.json
                          the same for MacLibraryTests (Swift Testing)

Run: python3 -m unittest scripts/tests/test_mac_ui_runner.py
"""

import io
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
from contextlib import redirect_stderr, redirect_stdout

# --- Guards: no real signal, process list, removal, LaunchServices or ssh from these tests -------------

_REAL_POPEN = subprocess.Popen


class OsOperationReached(AssertionError):
    pass


def _guard_kill(*args, **kwargs):
    raise OsOperationReached("a self-test reached os.kill / os.killpg")


_REAL_SCRIPT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "test_mac.sh"))


def _prelude_copy(path):
    """A truncated copy of the script's VM prelude made by PreludeLauncher: it ends right after the
    prelude and holds nothing of the VM half."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return False
    code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    # Nothing destructive may be in it either, whatever moved in the script (review v3: Claude C-6).
    if re.search(r"\b(rm|pkill|killall|kill|defaults|lsregister|tart|ssh)\b", code):
        return False
    return "PRELUDE-PASSED" in text and "in_vm_main" not in text and "vm_clean" not in text \
        and os.path.realpath(path) != _REAL_SCRIPT


def _allowed_command(args, env):
    argv = [args] if isinstance(args, str) else list(args)
    if not argv:
        return False
    if argv[0] == "git":
        return True
    if argv[0] == "/bin/bash":
        script = next((a for a in argv[1:] if not a.startswith("-")), "")
        if any(a.startswith("--in-vm") for a in argv[1:]):
            # The VM half is never run here (review v2: Claude B-2); only the prelude's truncated copy is.
            return _prelude_copy(script)
        return env is not None and set(env.get("PATH", "").split(":")) <= {env.get("HOME")}
    return False


class _GuardedPopen(_REAL_POPEN):
    def __init__(self, args, *rest, **kwargs):
        if not _allowed_command(args, kwargs.get("env")):
            raise OsOperationReached(f"a self-test reached a subprocess: {args!r}"[:200])
        super().__init__(args, *rest, **kwargs)


os.kill = _guard_kill
os.killpg = _guard_kill
subprocess.Popen = _GuardedPopen

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import mac_ui_runner as r  # noqa: E402


def _guard_libproc(*args, **kwargs):
    raise OsOperationReached("a self-test reached the real process table (libproc)")


# The process table is read through libproc (review v6): on this Mac the self-tests never read it. Only
# RealProcessesInTheVM, in the VM, takes the real one explicitly.
_REAL_LIBPROC = r.LibProc
r.LibProc = _guard_libproc

# Every plan of this Mac needs the VM checks recorded; the tests that approve set them here.
READY = {k: "recorded in a test" for k in r.MAC_RUN_PREREQUISITES}

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "mac_ui_runner"
TESTS_DIR = ROOT / "mac" / "MacLibraryExample" / "MacLibraryExampleUITests"
SAMPLE_DIR = ROOT / "mac" / "MacLibraryExample" / "MacLibraryExample"
PBXPROJ = ROOT / "mac" / "MacLibraryExample" / "MacLibraryExample.xcodeproj" / "project.pbxproj"
SCRIPT = ROOT / "scripts" / "test_mac.sh"
SOURCE_TEXT = (ROOT / "scripts" / "mac_ui_runner.py").read_text()
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


def unit_keys():
    return r.parse_unit_enumeration(fixture("enumeration.json"), (r.EXAMPLE_UNIT_TARGET,)) + \
        r.parse_unit_enumeration(fixture("unit-enumeration.json"), (r.LIBRARY_UNIT_TARGET,))


def mac_plan(allowed=r.MAC_CATEGORIES, audit=None, ready=True):
    old = dict(r.MAC_RUN_PREREQUISITES)
    try:
        if ready:
            r.MAC_RUN_PREREQUISITES.update(READY)
        return r.make_plan("mac", enumeration(), declarations(), allowed, None, "26", "a" * 40, "b" * 64, [], True,
                           audit or {"suites": ["DetectionUseCaseTests"], "expired": False, "hash": "c" * 64},
                           runner_files={"scripts/mac_ui_runner.py": "d" * 64}, declarations_hash="e" * 64,
                           unit_keys=unit_keys(), environment={"osBuild": "25G342", "xcode": "26.6"})
    finally:
        r.MAC_RUN_PREREQUISITES.clear()
        r.MAC_RUN_PREREQUISITES.update(old)


class Approval(unittest.TestCase):
    def test_the_same_plan_is_approved(self):
        plan = mac_plan()
        approval = r.make_approval(plan)
        self.assertEqual(r.approval_problems(approval, plan), [])
        self.assertEqual(approval["unitTests"], ["MacLibraryTests/DetectionUseCaseTests"])
        self.assertTrue(plan["unitInvocations"][0]["expected"])
        self.assertTrue(all(k.startswith("MacLibraryTests/DetectionUseCaseTests/")
                            for k in plan["unitInvocations"][0]["expected"]))

    def test_a_precondition_counts_only_as_an_existing_record(self):
        with tempfile.TemporaryDirectory() as repo:
            pathlib.Path(repo, "artifact").mkdir()
            pathlib.Path(repo, "artifact", "record.md").write_text("checked")
            table = {"a": "artifact/record.md", "b": "artifact/missing.md", "c": "yes", "d": None,
                     "e": "artifact/../outside.md"}
            self.assertEqual(r.prerequisite_status(repo, table),
                             {"a": "artifact/record.md", "b": None, "c": None, "d": None, "e": None})
        self.assertIn("decoyNotificationRoot", r.MAC_RUN_PREREQUISITES)

    def test_an_old_approval_or_unchecked_preconditions_are_refused(self):
        import datetime
        plan = mac_plan()
        approval = r.make_approval(plan)
        later = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=r.APPROVAL_HOURS, minutes=1)
        self.assertTrue(any("older than" in p for p in r.approval_problems(approval, plan, now=later)))
        not_ready = mac_plan(ready=False)
        self.assertTrue(any("not checked yet" in p for p in r.approval_problems(r.make_approval(not_ready), not_ready)))
        self.assertTrue(all(v is None for v in r.MAC_RUN_PREREQUISITES.values()))

    def test_any_change_is_refused(self):
        plan = mac_plan()
        approval = r.make_approval(plan)
        for change in (lambda a: a["tests"].pop(),
                       lambda a: a.__setitem__("allow", ["panels"]),
                       lambda a: a.__setitem__("head", "f" * 40),
                       lambda a: a.__setitem__("extra", 1),
                       lambda a: a.pop("unitTests"),
                       lambda a: a.__setitem__("approvalId", "nothex"),
                       lambda a: a["tests"].reverse(),
                       lambda a: a.__setitem__("baseline", True),
                       lambda a: a["environment"].__setitem__("xcode", "26.3")):
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
            "vmBoottime": "1795358134", "macAddress": "86:44:0f:12:49:26", "tartMacAddress": "86:44:0f:12:49:26",
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
            "identity ": ("vmBoottime", "soon"), "tartIsThePeer": ("macAddress", "86:44:0f:12:49:27"),
            "tartIsThePeer ": ("tartMacAddress", "86:44:0f:12:49:27"),
        }
        for item, (key, value) in cases.items():
            facts = good_facts()
            facts[key] = value
            self.assertIn(item.strip(), self.failing(facts), key)
            facts = good_facts()
            facts.pop(key)
            self.assertIn(item.strip(), self.failing(facts), f"{key} missing")

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

    def test_preconditions_and_runner_names_are_closed_lists(self):
        self.assertEqual(r.public_codes("NTK-PRECONDITION:userHomeIsJohn", VOCABULARY), [])
        good = {"test": "MacLibraryExampleUITests/DialogUITests/testD1_showDialogOK", "result": "failed"}
        for code in ("NTK-PRECONDITION:userHomeIsJohn", "NTK-RUNNER:mailFromAlice"):
            with self.assertRaises(r.RunnerError):
                r.public_record(dict(good, codes=[code]))
        self.assertTrue(r.public_record(dict(good, codes=["NTK-PRECONDITION:notAuthorized", "NTK-RUNNER:noResult"])))

    def test_messages_show_no_paths(self):
        for raw in ("the bundled copy differs: /Users/Alice Smith/private (copy)/x.json",
                    "fatal: '/private/var/folders/a b/x' failed", "see ~/Library/Logs/Alice Smith.log",
                    "/Users/Alice Smith/start", "copy at </Users/Alice Smith/x>", "`~/Alice Smith`", "a|/Users/x"):
            text = r.public_message(raw)
            self.assertEqual(text, r.WITHHELD, raw)  # a fixed code, nothing cut out of the message
            for fragment in ("Users", "Alice", "Smith", "private", "folders", "Library", "start", "(copy)"):
                self.assertNotIn(fragment, text, raw)
        kept = "Support/SampleApp.swift:12: MacLibraryTests/DetectionUseCaseTests and ./relative, 3 problem(s)"
        self.assertEqual(r.public_message(kept), kept)

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
    return json.dumps({"devices": [{"deviceId": "x", "platform": "macOS", "architecture": "arm64"}], "testNodes": [
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

    def test_unit_results_must_be_the_planned_set(self):
        text = fixture("xcresult-unit-tests.json")
        planned = [k for k in unit_keys() if k.startswith("MacLibraryTests/")]
        records = r.unit_records("MacLibraryTests", text, 0, VOCABULARY, planned)
        self.assertFalse([x for x in records if "#" in x["test"]])
        records = r.unit_records("MacLibraryTests", text, 0, VOCABULARY, planned[1:])
        self.assertIn("MacLibraryTests#namedSet", [x["test"] for x in records])
        records = r.unit_records("MacLibraryTests", text, 0, VOCABULARY, planned + ["MacLibraryTests/Gone/test"])
        self.assertIn("MacLibraryTests#namedSet", [x["test"] for x in records])

    def test_unit_shapes_and_folded_names(self):
        def unit(cases):
            return json.dumps({"devices": [{"deviceId": "x", "platform": "macOS", "architecture": "arm64"}], "testNodes": [{"nodeType": "Unit test bundle",
                                                                              "name": "MacLibraryTests", "children": cases}]})
        records = r.unit_records("MacLibraryTests", unit([case("S/t()", "Passed", [{"nodeType": "Repetition"}])]), 0,
                                 VOCABULARY)
        self.assertIn("MacLibraryTests#unknownShape", [x["test"] for x in records])
        records = r.unit_records("MacLibraryTests", unit([case("S/t(a:)", "Passed"), case("S/t(b:)", "Passed")]), 0,
                                 VOCABULARY)
        self.assertIn("MacLibraryTests#readable", [x["test"] for x in records])

    def test_unit_destination_summary_arguments_and_bundles(self):
        text = fixture("xcresult-unit-tests.json")
        good = r.unit_records("MacLibraryTests", text, 0, VOCABULARY)
        self.assertFalse([x for x in good if "#" in x["test"]])
        data = json.loads(text)
        data["devices"] = data.get("devices", []) * 2 or [{"deviceId": "a"}, {"deviceId": "b"}]
        self.assertIn("MacLibraryTests#destination", [x["test"] for x in r.unit_records("MacLibraryTests", json.dumps(data), 0, VOCABULARY)])
        self.assertIn("MacLibraryTests#summary",
                      [x["test"] for x in r.unit_records("MacLibraryTests", text, 0, VOCABULARY, summary_text='{"totalTestCount": 1}')])

        def unit(cases, bundle="MacLibraryTests"):
            return json.dumps({"devices": [{"deviceId": "x", "platform": "macOS", "architecture": "arm64"}], "testNodes": [
                {"nodeType": "Unit test bundle", "name": bundle, "children": cases}]})
        failed_argument = case("S/t(a:)", "Passed", [{"nodeType": "Arguments", "name": "1", "result": "Failed"}])
        self.assertIn("MacLibraryTests#summary", [x["test"] for x in r.unit_records("MacLibraryTests", unit([failed_argument]), 0, VOCABULARY)])
        odd_argument = case("S/t(a:)", "Passed", [{"nodeType": "Arguments", "name": "1", "result": "Passed",
                                                   "children": [{"nodeType": "Repetition"}]}])
        self.assertIn("MacLibraryTests#unknownShape", [x["test"] for x in r.unit_records("MacLibraryTests", unit([odd_argument]), 0, VOCABULARY)])
        self.assertIn("MacLibraryTests#otherBundle",
                      [x["test"] for x in r.unit_records("MacLibraryTests", unit([case("S/t()", "Passed")], "Elsewhere"), 0, VOCABULARY)])
        with self.assertRaises(r.RunnerError):
            r.parse_unit_enumeration(json.dumps({"errors": [], "values": [{"enabledTests": [],
                                                                         "disabledTests": [{"identifier": "x"}]}]}),
                                     ("MacLibraryTests",))

    def test_a_result_of_no_or_two_destinations_stops(self):
        cases = [case(D1 + "()", "Passed")]
        for devices in ([], [{"deviceId": "a"}, {"deviceId": "b"}], [{"deviceId": "a", "platform": "iOS"}],
                        [{"deviceId": "a", "platform": "macOS", "architecture": "x86_64"}]):
            data = json.loads(tests_json(cases))
            data["devices"] = devices
            records, stop = r.record_invocation({"name": "x", "expected": [D1], "timeout": 1}, json.dumps(data),
                                                summary_json(cases), 0, False, VOCABULARY)
            self.assertTrue(stop)
            self.assertTrue(any(x["test"].endswith("#destination") for x in records))

    def test_a_destination_without_its_platform_or_another_in_the_summary(self):
        mac = {"deviceId": "x", "platform": "macOS", "architecture": "arm64"}
        self.assertTrue(r.destination_ok(json.dumps({"devices": [mac]})))
        for device in ({}, {"deviceId": "x"}, {"deviceId": "x", "platform": "macOS"},
                       {"deviceId": "x", "architecture": "arm64"}, dict(mac, deviceId="")):
            self.assertFalse(r.destination_ok(json.dumps({"devices": [device]})), device)  # Codex v3 B-2
        summary = {"devicesAndConfigurations": [{"device": {"deviceId": "y"}}]}
        self.assertFalse(r.destination_ok(json.dumps({"devices": [mac]}), json.dumps(summary)))
        summary = {"devicesAndConfigurations": [{"device": {"deviceId": "x"}}]}
        self.assertTrue(r.destination_ok(json.dumps({"devices": [mac]}), json.dumps(summary)))

    def test_argument_values_never_leave(self):
        tests = json.dumps({"devices": [{"deviceId": "x", "platform": "macOS", "architecture": "arm64"}], "testNodes": [{"nodeType": "Unit test bundle", "name": "MacLibraryTests", "children": [
            case("Suite/check(value:)", "Passed", [{"nodeType": "Arguments", "name": "/Users/x/secret", "result": "Passed"},
                                                   {"nodeType": "Arguments", "name": "2", "result": "Passed"}])]}]})
        records = r.unit_records("MacLibraryTests", tests, 0, VOCABULARY)
        self.assertEqual(records, [{"test": "MacLibraryTests/Suite/check", "result": "passed", "kind": "passed",
                                    "codes": [], "seconds": 1.0, "runs": 2}])

    def test_not_run_records_are_failures(self):
        records = r.not_run_records([{"expected": [D1, D2]}], "notificationStopped")
        self.assertTrue(all(x["result"] == "failed" and x["codes"] == ["NTK-STOP:notificationUI"] for x in records))


class Stale(unittest.TestCase):
    """What of a run still runs (run_processes). Nothing here signals: on this Mac the runner signals only its
    own unreaped children (review v5)."""
    ROOT_DIR = "/private/var/folders/x/T/ntk-test-mac.abc"
    XCODE = "/Applications/Xcode26.6.app/Contents"
    XB = XCODE + "/Developer/usr/bin/xcodebuild"
    SAMPLE = ROOT_DIR + "/dd-ui/Build/Products/Debug/MacLibraryExample.app/Contents/MacOS/MacLibraryExample"

    def marker(self, **change):
        marker = {"boottime": 1000, "created": 5000.0, "root": self.ROOT_DIR, "pgid": 300, "groups": [300],
                  "runId": "20261123T000000Z-abcdef",
                  "writers": [{"pid": 300, "start": 5001, "exe": self.XB, "pgid": 300}]}
        marker.update(change)
        return marker

    def proc(self, pid, start, exe, pgid=None, uid=501, zombie=False):
        return {"pid": pid, "pgid": pgid if pgid is not None else pid, "start": start, "exe": exe, "uid": uid,
                "zombie": zombie}

    def running(self, processes, marker=None, boot=1000, launched=None):
        state = r.run_processes(marker or self.marker(), boot, processes, [self.XCODE], self.ROOT_DIR, 501, launched)
        self.assertIsNone(state["refuse"])
        return state["running"]

    def test_a_recorded_writer_and_its_group(self):
        self.assertEqual(self.running([self.proc(300, 5001, self.XB),
                                       self.proc(301, 5002, self.XCODE + "/Developer/usr/bin/xctest", 300)]),
                         {"xcodebuild": 1, "tool": 1})

    def test_a_writer_whose_executable_cannot_be_read_still_runs(self):
        # Codex v5 A-1: PID and start time are the writer's; an unreadable executable is not "gone".
        self.assertEqual(self.running([self.proc(300, 5001, None)]), {"xcodebuild": 1})
        self.assertEqual(self.running([self.proc(301, 5002, None, 300)]), {"group": 1})

    def test_every_group_the_run_made_is_followed(self):
        # Codex v5 A-2: the first call's group 300 keeps a helper after the second call (group 400) was recorded.
        marker = self.marker(pgid=400, groups=[300, 400],
                             writers=[{"pid": 300, "start": 5001, "exe": self.XB, "pgid": 300},
                                      {"pid": 400, "start": 6001, "exe": self.XB, "pgid": 400}])
        helper = self.proc(302, 5003, self.XCODE + "/Developer/usr/bin/xctest", 300)
        self.assertEqual(self.running([helper], marker), {"tool": 1})
        older = self.marker(pgid=400, groups=[300, 400], writers=[{"pid": 400, "start": 6001, "exe": self.XB}])
        self.assertEqual(self.running([helper], older), {"tool": 1})  # the list of groups alone
        recorded = r.record_writer(r.record_writer({"writers": [], "launching": True},
                                                   {"pid": 300, "pgid": 300, "start": 5001, "exe": self.XB}, "xcodebuild"),
                                   {"pid": 400, "pgid": 400, "start": 6001, "exe": self.XB}, "xcodebuild")
        self.assertEqual(recorded["groups"], [300, 400])
        self.assertEqual([w["pgid"] for w in recorded["writers"]], [300, 400])
        self.assertNotIn("launching", recorded)  # recorded: no longer starting (review v4: Codex A-2)

    def test_a_reused_pid_with_another_start_is_not_the_writer(self):
        self.assertEqual(self.running([self.proc(300, 9000, "/System/Applications/Mail.app/Contents/MacOS/Mail", 900)]), {})

    def test_a_marker_of_an_earlier_boot_runs_nothing(self):
        self.assertEqual(self.running([self.proc(300, 5001, self.XB)], boot=2000), {})

    def test_a_sample_and_an_unreadable_process_of_this_user(self):
        self.assertEqual(self.running([self.proc(310, 5005, self.SAMPLE, 310)]), {"sample": 1})
        self.assertEqual(self.running([self.proc(320, 5006, None, 320)]), {"unknown": 1})
        self.assertEqual(self.running([self.proc(321, 5006, None, 321, uid=0)]), {})       # another user's
        self.assertEqual(self.running([self.proc(322, 4000, None, 322)]), {})              # older than the run
        self.assertEqual(self.running([self.proc(323, 5006, None, 323, zombie=True)]), {})  # a zombie writes nothing
        self.assertEqual(self.running([self.proc(311, 4000, self.SAMPLE, 311)]), {})        # before the marker

    def test_a_launching_marker_follows_the_started_number(self):
        launching = self.marker(launching=True)
        state = r.run_processes(launching, 1000, [], [self.XCODE], self.ROOT_DIR, 501, None)
        self.assertIn("never recorded", state["refuse"])              # the number is not known: refused
        self.assertEqual(self.running([], launching, launched=700), {})  # Claude v5 C-3: it ended, nothing runs
        self.assertEqual(self.running([self.proc(700, 5009, self.XB)], launching, launched=700), {"xcodebuild": 1})
        self.assertEqual(self.running([self.proc(701, 5009, self.XB, 700)], launching, launched=700), {"tool": 1})
        self.assertIsNone(r.run_processes(launching, 2000, [], [self.XCODE], self.ROOT_DIR, 501, None)["refuse"])

    def test_a_malformed_or_foreign_marker_is_refused(self):
        self.assertEqual(r.run_processes({"root": self.ROOT_DIR}, 1000, [], [self.XCODE])["refuse"], "malformed marker")
        self.assertIsNotNone(r.run_processes(self.marker(root="/"), 1000, [], [self.XCODE], self.ROOT_DIR)["refuse"])
        self.assertIsNotNone(r.run_processes(self.marker(), 900, [], [self.XCODE], self.ROOT_DIR)["refuse"])

    def test_the_description_holds_counts_only(self):
        text = r.describe_running({"tool": 1, "xcodebuild": 2})
        self.assertEqual(text, "NTK-STALE:alive 3 process(es) (2 xcodebuild, 1 tool)")


class FakePort:
    """The operating system for clean_run_folder: a process table and a log of what would have been done.
    It has no way to signal, as the real port has none (review v5)."""

    def __init__(self, processes, boot=1000, fail=False):
        self.table = [dict(p) for p in processes]
        self.boot = boot
        self.fail = fail
        self.log = []

    def processes(self):
        if self.fail:
            raise r.RunnerError("the process list could not be read")
        return [dict(p) for p in self.table]

    def boottime(self):
        return self.boot

    def uid(self):
        return 501

    def remove(self, folder):
        self.log.append(("remove", folder))

    def remove_fixture(self, path):
        self.log.append(("fixture", path))

    def unregister(self, app):
        self.log.append(("unregister", app))


class Stopping(unittest.TestCase):
    """The run folders of this Mac are removed only when nothing of their run runs; nothing is signalled."""
    ROOT_DIR = Stale.ROOT_DIR
    XCODE = Stale.XCODE
    XB = Stale.XB
    SAMPLE = Stale.SAMPLE

    def marker(self, **change):
        return Stale.marker(Stale(), **change)

    def test_the_port_cannot_signal(self):
        for name in ("signal", "signal_group", "kill"):
            self.assertFalse(hasattr(r.OsPort, name), name)
        self.assertNotIn("os.kill", SOURCE_TEXT)
        self.assertNotIn("os.killpg", SOURCE_TEXT)

    def test_a_running_writer_keeps_the_folder(self):
        port = FakePort([{"pid": 300, "pgid": 300, "start": 5001, "exe": self.XB, "uid": 501}])
        problem = r.clean_run_folder(self.ROOT_DIR, port, [self.XCODE], lambda folder: self.marker())
        self.assertEqual(problem, "NTK-STALE:alive 1 process(es) (1 xcodebuild)")
        self.assertEqual(port.log, [])

    def test_a_process_list_that_cannot_be_read_is_an_error(self):
        class Lib:
            def __init__(self, pids, short, paths=None, starts=None):
                self._pids, self._short, self.paths, self.starts, self.looked = pids, short, paths or {}, starts or {}, {}

            def pids(self):
                return self._pids

            def short(self, pid):
                self.looked[pid] = self.looked.get(pid, 0) + 1
                value = self._short(pid, self.looked[pid])
                return dict(value) if isinstance(value, dict) else value

            def start(self, pid):
                return self.starts.get(pid, 100.0)

            def path(self, pid):
                return self.paths.get(pid)

        me = os.getuid()
        mine = {"pid": 10, "ppid": 1, "pgid": 10, "uid": me, "zombie": False}
        for lib in (Lib(None, None), Lib([], None), Lib([10], lambda pid, n: None)):
            with self.assertRaises(r.RunnerError):      # never an empty list (review v5: Codex A-1)
                r._processes(lib)
        # A process gone between the listing and the look at it is left out (review v6: Claude A-1).
        self.assertEqual(r._processes(Lib([10, 11], lambda pid, n: dict(mine, pid=pid) if pid == 10 else "gone",
                                          {10: "/bin/x"})), [dict(mine, start=100.0, exe="/bin/x")])
        # Its executable unread: looked at again; gone by then, or another process of that number, left out.
        self.assertEqual(r._processes(Lib([10], lambda pid, n: mine if n == 1 else "gone")), [])
        lib = Lib([10], lambda pid, n: mine)
        self.assertEqual(r._processes(lib), [dict(mine, start=100.0, exe=None)])  # still there: counted
        self.assertEqual(lib.looked[10], 2)
        other = {"pid": 20, "ppid": 1, "pgid": 20, "uid": 0, "zombie": False}
        self.assertEqual(r._processes(Lib([20], lambda pid, n: other, {20: "/usr/sbin/x"})),
                         [dict(other, start=None, exe="/usr/sbin/x")])  # another user's: no start time

    def test_an_unreadable_process_list_keeps_the_folder(self):
        port = FakePort([], fail=True)  # Codex v5 A-1: a list that cannot be read is not an empty one
        self.assertIn("could not be read", r.clean_run_folder(self.ROOT_DIR, port, [self.XCODE], lambda f: self.marker()))
        self.assertEqual(port.log, [])
        self.assertIn("could not be read", r.stale_state(self.ROOT_DIR, port, [self.XCODE], lambda f: self.marker()))

    def test_a_helper_of_an_earlier_call_keeps_the_folder(self):
        marker = self.marker(pgid=400, groups=[300, 400])
        port = FakePort([{"pid": 302, "pgid": 300, "start": 5003, "exe": None, "uid": 501}])
        self.assertIsNotNone(r.clean_run_folder(self.ROOT_DIR, port, [self.XCODE], lambda f: marker))
        self.assertEqual(port.log, [])
        self.assertIsNotNone(r.settle_problem(marker, port.processes(), [self.XCODE], 1000, self.ROOT_DIR))
        self.assertIsNone(r.settle_problem(marker, [{"pid": 310, "pgid": 310, "start": 5005, "exe": self.SAMPLE}],
                                           [self.XCODE], 1000, self.ROOT_DIR))  # settle looks at the groups

    def test_a_folder_without_a_readable_marker_is_never_removed(self):
        def broken(folder):
            raise ValueError("not JSON")
        port = FakePort([])
        self.assertIsNotNone(r.clean_run_folder(self.ROOT_DIR, port, [self.XCODE], broken))
        self.assertEqual(port.log, [])
        self.assertTrue(r.stale_state(self.ROOT_DIR, port, [self.XCODE], broken).startswith("NTK-STALE:refused"))

    def test_a_clean_folder_goes_with_its_fixture(self):
        port = FakePort([])
        self.assertIsNone(r.clean_run_folder(self.ROOT_DIR, port, [self.XCODE], lambda folder: self.marker()))
        self.assertEqual(port.log, [("fixture", "/private/tmp/ntk-uitest-20261123T000000Z-abcdef"),
                                    ("remove", self.ROOT_DIR)])

    def test_a_launching_folder_with_its_pid_file(self):
        with tempfile.TemporaryDirectory(prefix="ntk-test-mac.") as folder:
            root = os.path.realpath(folder)
            marker = self.marker(root=root, launching=True)
            port = FakePort([])
            self.assertIn("never recorded", r.clean_run_folder(root, port, [self.XCODE], lambda f: marker))
            pathlib.Path(root, r.PIDFILE_NAME).write_text("700\n")
            self.assertEqual(r.launched_pid(root), 700)
            port = FakePort([{"pid": 701, "pgid": 700, "start": 5009, "exe": self.XB, "uid": 501}])
            self.assertIsNotNone(r.clean_run_folder(root, port, [self.XCODE], lambda f: marker))
            self.assertEqual(port.log, [])
            port = FakePort([])
            self.assertIsNone(r.clean_run_folder(root, port, [self.XCODE], lambda f: marker))
            self.assertIn(("remove", root), port.log)

    def settle_with(self, tables, seconds=15.0, marker=None):
        """settle() over a list of process tables, one per look, with a clock that the sleeps move."""
        clock = [0.0]
        looks = iter(tables)

        def processes():
            table = next(looks)
            if isinstance(table, Exception):
                raise table
            return table

        def sleep(n):
            clock[0] += n
        return r.settle(lambda f: marker or self.marker(), processes, [self.XCODE], lambda: 1000, lambda: clock[0],
                        sleep, seconds, self.ROOT_DIR), clock[0]

    def test_settle_waits_for_the_group_and_stops_at_its_end(self):
        helper = {"pid": 302, "pgid": 300, "start": 5003, "exe": self.XCODE + "/Developer/usr/bin/xctest", "uid": 501}
        # Left, then gone: settled, and the group is closed (review v6: Claude B-1, C-1; Codex B-2).
        (problem, empty), waited = self.settle_with([[helper], [helper], []])
        self.assertIsNone(problem)
        self.assertEqual((empty, waited), ([300], 1.0))
        # Left until the end: the run stops.
        (problem, empty), waited = self.settle_with([[helper]] * 40, seconds=2.0)
        self.assertIn("NTK-STALE:alive 1 process(es) (1 tool)", problem)
        self.assertIsNone(empty)
        self.assertEqual(waited, 2.0)
        # A table that cannot be read stops it at once.
        (problem, empty), waited = self.settle_with([r.RunnerError("x")])
        self.assertIn("could not be read", problem)
        self.assertEqual(waited, 0.0)

    def test_a_closed_group_is_not_counted(self):
        # A number shown empty by settle may be taken by anything later (review v6: Claude C-1).
        later = {"pid": 301, "pgid": 300, "start": 9000, "exe": "/usr/bin/ditto", "uid": 501}
        self.assertEqual(r.run_processes(self.marker(closed=[300]), 1000, [later], [self.XCODE], self.ROOT_DIR, 501,
                                         None)["running"], {})
        self.assertEqual(r.run_processes(self.marker(), 1000, [later], [self.XCODE], self.ROOT_DIR, 501,
                                         None)["running"], {"group": 1})
        self.assertEqual(r.open_groups(self.marker(groups=[300, 400], closed=[300])), [400])

    def test_the_vm_writes_down_what_is_left(self):
        table = [{"pid": 5, "pgid": 7}, {"pid": 6, "pgid": 7, "zombie": True}, {"pid": 8, "pgid": 8}]
        self.assertEqual(r.group_left(7, table), 1)
        self.assertEqual(r.group_left(9, table), 0)

    def test_a_stale_folder_that_stays_stops_the_run(self):
        alive = FakePort([{"pid": 300, "pgid": 300, "start": 5001, "exe": self.XB, "uid": 501}])
        lines, stop = r.clean_stale([self.ROOT_DIR], alive, [self.XCODE], lambda f: self.marker())
        self.assertIsNotNone(stop)                                   # review v5: nothing is stopped; the run is
        self.assertEqual(alive.log, [])
        self.assertTrue(lines[0].startswith("NTK-STALE:alive 1 process(es)"))
        idle = FakePort([])
        lines, stop = r.clean_stale([self.ROOT_DIR], idle, [self.XCODE], lambda f: self.marker())
        self.assertIsNone(stop)
        self.assertIn(("remove", self.ROOT_DIR), idle.log)

    def test_the_listing_shows_states_not_places(self):
        port = FakePort([{"pid": 300, "pgid": 300, "start": 5001, "exe": self.XB, "uid": 501}])
        listing = r.stale_listing([self.ROOT_DIR], port, [self.XCODE], lambda f: self.marker())
        self.assertEqual([e["state"] for e in listing], ["NTK-STALE:alive 1 process(es) (1 xcodebuild)"])
        self.assertNotIn("/", json.dumps(listing))
        listing = r.stale_listing([self.ROOT_DIR], FakePort([]), [self.XCODE], lambda f: self.marker())
        self.assertEqual([e["state"] for e in listing], ["removable"])

    def test_the_current_folder_is_the_approved_run(self):
        marker = dict(self.marker(), approvalId="a" * 32)
        ledger = "a" * 32 + "\t2026-11-23T00:00:00+00:00\tmac\n"
        self.assertIsNone(r.current_run_problem(marker, {"approvalId": "a" * 32}, ledger))
        self.assertIsNotNone(r.current_run_problem(marker, {"approvalId": "b" * 32}, ledger))
        self.assertIsNotNone(r.current_run_problem(dict(marker, approvalId=None), {"approvalId": "a" * 32}, ledger))
        self.assertIsNotNone(r.current_run_problem(marker, {"approvalId": "a" * 32}, ""))

    def test_the_run_folder_comes_with_its_marker(self):
        with tempfile.TemporaryDirectory() as scan:
            source = pathlib.Path(scan, "approval-source.json")
            source.write_text("{}")
            root = r.make_run_folder(scan, "20261123T000000Z-abcdef", "a" * 32, 1000, 5000.0,
                                     {"approval.approved.json": str(source)})
            self.assertFalse(list(pathlib.Path(scan).glob(r.STAGING_PREFIX + "*")))
            self.assertTrue(pathlib.Path(root, "tmp").is_dir())
            self.assertEqual(oct(os.stat(pathlib.Path(root, "approval.approved.json")).st_mode & 0o777), "0o444")
            self.assertTrue(os.path.basename(root).startswith(r.RUN_FOLDER_PREFIX))
            marker = json.loads(pathlib.Path(root, r.MARKER_NAME).read_text())
            self.assertEqual((marker["approvalId"], marker["root"]), ("a" * 32, os.path.realpath(root)))
            self.assertEqual(oct(os.stat(root).st_mode & 0o777), "0o700")
            with self.assertRaises(r.RunnerError):
                r.make_run_folder(scan, "bad", "a" * 32, 1000, 5000.0)
            # A copy that fails leaves no run folder: the staging folder never got its public name.
            names = sorted(os.listdir(scan))
            with self.assertRaises(OSError):
                r.make_run_folder(scan, "20261123T000001Z-abcdef", "b" * 32, 1000, 5000.0,
                                  {"approval.approved.json": str(pathlib.Path(scan, "missing.json"))})
            new = sorted(set(os.listdir(scan)) - set(names))
            self.assertTrue(all(n.startswith(r.STAGING_PREFIX) for n in new), new)

    def test_private_folders_left_by_a_killed_run(self):
        folders = ["/t/ntk-test-mac-private.a", "/t/ntk-test-mac-private.b", "/t/ntk-test-mac-private.c",
                   "/t/ntk-test-mac-private.d"]
        owners = {folders[0]: ({"pid": 10, "start": 100}, 0.0), folders[1]: ({"pid": 11, "start": 100}, 0.0),
                  folders[2]: (None, 990.0), folders[3]: (None, 100.0)}
        processes = [{"pid": 10, "start": 100}, {"pid": 11, "start": 555}]
        self.assertEqual(r.orphaned_private_folders(folders, owners, processes, now=1000.0),
                         [folders[1], folders[3]])

    def test_a_writer_is_recorded_only_as_the_expected_xcode(self):
        processes = [{"pid": 300, "pgid": 300, "start": 5001, "exe": "/usr/bin/perl"}]
        self.assertIsNone(r.writer_entry(300, processes, "/Applications/Xcode26.6.app/Contents/Developer"))
        processes[0]["exe"] = self.XB
        self.assertEqual(r.writer_entry(300, processes, "/Applications/Xcode26.6.app/Contents/Developer")["pgid"], 300)


class Audit(unittest.TestCase):
    MOCK = "struct MacClipboardManagerTests {}\nrepo.copy(scope: .general)\nrepo.read(scope: .general)\n"

    def audit(self, review=True, **change):
        audit = {"schema": 1, "treeHash": "t", "auditedBy": "Claude (stage 0d)", "auditedModel": "Claude",
                 "suites": [{"suite": "MacClipboardManagerTests", "file": "M.swift",
                             "allowed": [{"word": ".general", "count": 2, "reason": "passed to the mock"}]}],
                 "helpers": [{"file": "Mock/MockRepo.swift", "allowed": []}]}
        audit.update(change)
        audit["review"] = self.review(audit) if review is True else review
        return audit

    def review(self, audit, **change):
        review = {"by": "Codex", "model": "Codex", "file": "artifact/topics/macos-c-abi/reviews/unit-audit-v2.md",
                  "date": "2026-11-24", "treeHash": audit["treeHash"], "tableDigest": r.audit_table_digest(audit)}
        review.update(change)
        return review

    def state(self, audit=None, text=None, helpers=None, tree="t"):
        return r.audit_state(audit or self.audit(), tree, {"M.swift": self.MOCK if text is None else text},
                             {"Mock/MockRepo.swift": "struct MockRepo {}"} if helpers is None else helpers)

    def test_word_counts(self):
        counts = r.audit_word_counts("let p = NSPasteboard.general\nresolve(.general)\nx(scope: .general)\n"
                                     "MacShareManager.shared\nNSSharingServicePicker\nNSGeneralPboard\nNSPasteboard(name: x)")
        self.assertEqual(counts, {"NSPasteboard.general": 1, ".general": 2, "MacShareManager.shared": 1,
                                  "NSSharingService": 1, "NSGeneralPboard": 1, "NSPasteboard(name:": 1})

    def test_allowed_occurrences_must_match(self):
        self.assertEqual(self.state()["suites"], ["MacClipboardManagerTests"])
        for text in (self.MOCK + "PasteboardResolver.resolve(.general)\n", self.MOCK + "MacClipboardManager.shared.copy()\n",
                     "struct MacClipboardManagerTests {}\nrepo.copy(scope: .general)\n",
                     self.MOCK + "NSPasteboard.general.clearContents()\n"):
            self.assertEqual(self.state(text=text)["suites"], [], text)

    def test_the_file_must_declare_the_suite(self):
        self.assertEqual(self.state(text=self.MOCK.replace("MacClipboardManagerTests", "PasteboardResolverTests"))["suites"], [])

    def test_a_suite_twice_or_also_not_listed(self):
        audit = self.audit()
        audit["suites"].append(dict(audit["suites"][0]))
        self.assertEqual(self.state(audit=audit)["suites"], [])
        self.assertEqual(self.state(audit=self.audit(notListed=[{"suite": "MacClipboardManagerTests"}]))["suites"], [])

    def test_helpers_are_counted(self):
        self.assertEqual(self.state(helpers={"Mock/MockRepo.swift": "NSPasteboard.general"})["suites"], [])
        self.assertEqual(self.state(helpers={"Mock/MockRepo.swift": "struct MockRepo {}",
                                             "Mock/Other.swift": "UNUserNotificationCenter.current()"})["suites"], [])

    def test_a_reason_is_required(self):
        audit = self.audit()
        audit["suites"][0]["allowed"][0]["reason"] = ""
        self.assertEqual(self.state(audit=audit)["suites"], [])

    def test_an_expired_or_unreviewed_table_selects_nothing(self):
        state = self.state(tree="other")
        self.assertEqual((state["suites"], state["expired"]), ([], True))
        for review in (None, {"by": "x"}, {"by": "x", "date": "d", "treeHash": "older"}):
            state = self.state(audit=self.audit(review=review))
            self.assertEqual((state["suites"], state["expired"]), ([], True), review)
        good = self.audit()
        for change in ({"treeHash": "older"}, {"tableDigest": "0" * 64}, {"model": "claude "}, {"file": ""},
                       {"file": "somewhere/else.md"}, {"by": ""}):
            audit = dict(good, review=self.review(good, **change))
            self.assertEqual(self.state(audit=audit)["suites"], [], change)  # unit audit review v1: Codex B-3
        changed = dict(good, suites=good["suites"] + [{"suite": "Other", "file": "O.swift", "allowed": []}])
        self.assertFalse(r.audit_reviewed(changed))   # the table changed after its review: stale
        self.assertTrue(r.audit_reviewed(good))
        plan = mac_plan(audit=state)
        self.assertEqual(plan["unitInvocations"], [])
        self.assertEqual(plan["unitExcluded"], [{"target": "MacLibraryTests", "reason": "auditExpired"}])

    def test_every_enumerated_suite_nested_too_is_in_the_table(self):
        keys = ["MacLibraryTests/MacClipboardManagerTests/a", "MacLibraryTests/P/I/b", "MacLibraryTests/P/c",
                "MacLibraryExampleTests/X/d"]
        self.assertEqual(r.enumerated_suites(keys), ["MacClipboardManagerTests", "P", "P.I"])
        listed = self.audit(notListed=[{"suite": "P"}, {"suite": "P.I"}])
        self.assertEqual(r.audit_state(listed, "t", {"M.swift": self.MOCK}, {"Mock/MockRepo.swift": ""},
                                       r.enumerated_suites(keys))["suites"], ["MacClipboardManagerTests"])
        missing = self.audit(notListed=[{"suite": "P"}])  # Codex B-1: the nested one is missing
        state = r.audit_state(missing, "t", {"M.swift": self.MOCK}, {"Mock/MockRepo.swift": ""}, r.enumerated_suites(keys))
        self.assertEqual((state["suites"], state["expired"]), ([], True))
        self.assertIn("P.I: enumerated but not in the table", state["problems"])
        nested = ["MacLibraryTests/MacClipboardManagerTests/Inner/e"]
        inner = self.audit(notListed=[{"suite": "MacClipboardManagerTests.Inner"}])
        self.assertIn("MacClipboardManagerTests.Inner: nested in an allowed suite but not allowed itself",
                      r.audit_inventory_problems(inner, r.enumerated_suites(nested)))

    def test_the_repository_table_is_bound_to_the_tree(self):
        audit = json.loads((ROOT / r.AUDIT_FILE).read_text(encoding="utf-8"))
        self.assertEqual(audit["schema"], 1)
        self.assertTrue(all(a["reason"] for s in audit["suites"] for a in s["allowed"]))
        self.assertNotIn("SharePickerPresenterTests", [s["suite"] for s in audit["suites"]])
        self.assertNotIn("PasteboardResolverTests", [s["suite"] for s in audit["suites"]])
        self.assertIn("mac/UnityMacPlugin/UnityMacPlugin/Clipboard", r.AUDIT_TREE_PATHS)  # Codex B-2
        keys = r.parse_unit_enumeration(fixture("unit-enumeration.json"), ("MacLibraryTests",))
        self.assertEqual(r.audit_inventory_problems(audit, r.enumerated_suites(keys)), [])  # Codex B-1
        if subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--git-dir"], capture_output=True).returncode != 0:
            self.skipTest("not a git checkout (the mutation harness's copy)")
        self.assertEqual(audit["treeHash"], r.tree_hash(ROOT, r.AUDIT_TREE_PATHS),
                         "the audited tree changed: audit the change, then update treeHash and the review")
        state = r._audit_for(ROOT, "mac")
        self.assertFalse([p for p in state["problems"] if "review" not in p], state["problems"])


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

    def test_fewer_expanded_runs_is_lost_coverage(self):
        # Same keys and results, one parameterized test ran 2 of its 3 arguments (review v3: Codex A-3).
        current, baseline = {"MacLibraryTests/S/t(a:)": "passed"}, {"MacLibraryTests/S/t(a:)": "passed"}
        lines, lost = r.compare_with_baseline(current, baseline, set(baseline), None, None,
                                              {"MacLibraryTests/S/t(a:)": 2}, {"MacLibraryTests/S/t(a:)": 3})
        self.assertIn("fewer runs=1", lines[0])
        self.assertIn("  RUNS MacLibraryTests/S/t(a:): 3 -> 2", lines)
        self.assertEqual(lost, ["MacLibraryTests/S/t(a:)"])
        _, lost = r.compare_with_baseline(current, baseline, set(baseline), None, None,
                                          {"MacLibraryTests/S/t(a:)": 3}, {"MacLibraryTests/S/t(a:)": 3})
        self.assertEqual(lost, [])
        # An older baseline without the per-test numbers: the expanded total of the target.
        lines, lost = r.compare_with_baseline(current, baseline, set(baseline), None, None,
                                              {"MacLibraryTests/S/t(a:)": 2}, None, {"MacLibraryTests": 3})
        self.assertIn("  RUNS MacLibraryTests (all): 3 -> 2", lines)
        self.assertEqual(lost, ["MacLibraryTests#expandedRuns"])

    def test_more_runs_are_shown_but_not_lost(self):
        current, baseline = {"MacLibraryTests/S/t(a:)": "passed"}, {"MacLibraryTests/S/t(a:)": "passed"}
        lines, lost = r.compare_with_baseline(current, baseline, set(baseline), None, None,
                                              {"MacLibraryTests/S/t(a:)": 4}, {"MacLibraryTests/S/t(a:)": 3})
        self.assertIn("fewer runs=0, more runs=1", lines[0])        # review v4: Codex B-2
        self.assertIn("  RUNS MacLibraryTests/S/t(a:): 3 -> 4", lines)
        self.assertEqual(lost, [])
        lines, lost = r.compare_with_baseline(current, baseline, set(baseline), None, None,
                                              {"MacLibraryTests/S/t(a:)": 4}, None, {"MacLibraryTests": 3})
        self.assertIn("  RUNS MacLibraryTests (all): 3 -> 4", lines)
        self.assertIn("more runs=1", lines[0])
        self.assertEqual(lost, [])

    def test_the_counts_hold_the_declared_and_the_expanded(self):
        counts = r.baseline_counts({"MacLibraryTests/S/t(a:)": "passed", "MacLibraryTests/S/u()": "passed"},
                                   {"MacLibraryTests/S/t(a:)": 3, "MacLibraryTests/S/u()": 1})
        self.assertEqual(counts["MacLibraryTests"], {"passed": 2, "runs": 4})

    def test_the_runs_this_run_compares(self):
        results = [{"test": "MacLibraryTests/S/t(a:)", "result": "passed", "runs": 3},
                   {"test": "MacLibraryTests/S/u()", "result": "passed"},
                   {"test": "MacLibraryTests#summary", "result": "failed"},
                   {"test": "MacLibraryExampleUITests/DialogUITests/testD1_showDialogOK", "result": "passed"}]
        runs = {"MacLibraryTests/S/t(a:)": 3, "MacLibraryTests/S/u()": 1}
        self.assertEqual(r.runs_to_compare(results, {"runs": {"x": 1}, "expandedRuns": {"MacLibraryTests": 4}}),
                         (runs, {"x": 1}, {}))
        self.assertEqual(r.runs_to_compare(results, {"expandedRuns": {"MacLibraryTests": 4}}),
                         (runs, None, {"MacLibraryTests": 4}))

    def test_the_names_a_run_left_in_tmpdir(self):
        before = ["a", "b"]
        after = ["a", "b", "c", r.RUN_FOLDER_PREFIX + "x", r.PRIVATE_PREFIX + "y", r.STAGING_PREFIX + "z"]
        self.assertEqual(r.tmp_new_names(before, after), ["c"])

    def test_names(self):
        self.assertEqual(r.baseline_name("vm", "15.8.3"), "test_mac.baseline.vm-15.8.3.json")
        for where, version in (("mac", "Mac Studio"), ("simulator", "26.2"), ("vm", "")):
            with self.assertRaises(r.RunnerError):
                r.baseline_name(where, version)

    def test_refusals(self):
        vm_env = {"os": "15.8.3", "osBuild": "24H241", "language": "en-US"}
        full = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], True, None)
        every = keys_of(full["selected"])
        self.assertIsNone(r.baseline_refusal(vm_env, full, False, False, every, []))
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, True, False, every, []))
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, False, True, every, []))
        self.assertIsNotNone(r.baseline_refusal(dict(vm_env, language="ja"), full, False, False, every, []))
        # Every eligible test executed exactly once, and nothing lost (Codex A-7, Claude A-4).
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, False, False, every[1:], []))
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, False, False, every + every[:1], []))
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, False, False, None, []))
        self.assertIsNotNone(r.baseline_refusal(vm_env, full, False, False, every, ["x"]))
        feature = r.make_plan("vm", enumeration(), declarations(), (), "Dialog", "15", "a", "b", [], False, None)
        self.assertIsNotNone(r.baseline_refusal(vm_env, feature, False, False, keys_of(feature["selected"]), []))
        no_unit = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], False, None)
        self.assertIsNotNone(r.baseline_refusal(vm_env, no_unit, False, False, every, []))
        mac_env = {"os": "26.7.3"}
        plan = mac_plan()
        self.assertIsNone(r.baseline_refusal(mac_env, plan, False, False, keys_of(plan["selected"]), []))
        narrow = mac_plan(allowed=("panels",))
        self.assertIsNotNone(r.baseline_refusal(mac_env, narrow, False, False, keys_of(narrow["selected"]), []))
        expired = mac_plan(audit={"suites": [], "expired": True, "hash": None})
        self.assertIsNotNone(r.baseline_refusal(mac_env, expired, False, False, keys_of(expired["selected"]), []))

    def test_completeness(self):
        plan = r.make_plan("vm", enumeration(), declarations(), (), "Dialog", "15", "a", "b", [], False, None)
        records = [{"test": f"MacLibraryExampleUITests/{k}", "result": "passed"} for k in keys_of(plan["selected"])]
        records.append({"test": "MacLibraryExampleUITests#fixture", "result": "passed"})
        self.assertEqual(r.completeness_problems(plan, records), [])
        self.assertTrue(r.completeness_problems(plan, records[1:]))            # a call that gave nothing
        self.assertTrue(r.completeness_problems(plan, records + records[:1]))  # twice
        self.assertTrue(r.completeness_problems(plan, records[:-1]))            # the fixture result is missing
        full = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], True, None,
                           unit_keys=unit_keys())
        records = [{"test": f"MacLibraryExampleUITests/{k}", "result": "passed"} for k in keys_of(full["selected"])]
        records += [{"test": f"MacLibraryExampleUITests#{n}", "result": "passed"}
                    for n in ("fixture", "buttonCoverage", "privacyRestore")]
        self.assertEqual(r.completeness_problems(full, records),
                         ["no record of MacLibraryTests", "no record of MacLibraryExampleTests"])
        units = [{"test": k, "result": "passed"} for u in full["unitInvocations"] for k in u["expected"]]
        self.assertEqual(r.completeness_problems(full, records + units), [])
        self.assertEqual(r.completeness_problems(full, records + units[1:]),
                         ["the records of MacLibraryTests are not exactly its planned tests"])

    def test_the_excluded_map_holds_the_unit_targets(self):
        expired = mac_plan(audit={"suites": [], "expired": True, "hash": None})
        self.assertEqual(r.excluded_map(expired)["MacLibraryTests"], "auditExpired")

    def test_the_latest_baseline_of_the_same_kind(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ("test_mac.baseline.mac-26.7.3.json", "test_mac.baseline.mac-26.10.json",
                         "test_mac.baseline.mac-26.11.2026-11-23.json", "test_mac.baseline.vm-27.json"):
                (pathlib.Path(d) / name).write_text("{}")
            self.assertEqual(r.latest_baseline(d, "mac").name, "test_mac.baseline.mac-26.10.json")
            self.assertIsNone(r.latest_baseline(d + "/none", "mac"))

    def test_the_baseline_keeps_eligible_executed_and_excluded(self):
        plan = r.make_plan("vm", enumeration(), declarations(), (), None, "15", "a", "b", [], True, None)
        results = {"MacLibraryExampleUITests/" + D1: "passed"}
        baseline = r.make_baseline({"os": "15.8.3"}, plan, results, {D1: 3.0}, "2026-11-23T00:00:00+00:00")
        self.assertEqual(len(baseline["eligible"]), 113)
        self.assertEqual(baseline["executed"], [D1])  # the same form as eligible (Codex v2 B-5)
        snapshot = {"scripts/test_mac.sh": "1" * 64}
        named = r.make_baseline({"os": "15.8.3"}, dict(plan, runnerFiles=snapshot), results, {}, "2026-11-23T00:00:00+00:00")
        self.assertEqual(named["source"]["runnerFiles"], snapshot)  # the run's snapshot (review v4: Codex A-3)
        full = {f"MacLibraryExampleUITests/{k}": "passed" for k in keys_of(plan["selected"])}
        whole = r.make_baseline({"os": "15.8.3"}, plan, full, {}, "2026-11-23T00:00:00+00:00")
        self.assertEqual(whole["eligible"], whole["executed"])
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
    def test_the_fixture_is_made_anew_without_following_links(self):
        root = "/private/tmp/ntk-uitest-selftest-" + os.urandom(3).hex()
        try:
            r.fixture_create(root)
            manifest = r.fixture_manifest(root)
            self.assertEqual(sorted(manifest), sorted(r.FIXTURE_ITEMS))
            with self.assertRaises(r.RunnerError):
                r.fixture_create(root)  # never reused
        finally:
            shutil.rmtree(root, ignore_errors=True)
        with tempfile.TemporaryDirectory() as elsewhere:
            os.symlink(elsewhere, root)
            try:
                with self.assertRaises(r.RunnerError):
                    r.fixture_create(root)
                with self.assertRaises(r.RunnerError):
                    r.fixture_manifest(root)
                self.assertEqual(os.listdir(elsewhere), [])
            finally:
                os.unlink(root)

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
            ("DialogUITests.swift", "try alert.typeKey(key)", "try sample.typeKey(key)"),
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


class Calls(unittest.TestCase):
    """The checks right before every xcodebuild on this Mac (Claude A-1, Codex A-2, B-2, Claude B-10)."""
    ROOT_DIR = "/private/var/folders/x/T/ntk-test-mac.abc"
    NAMES = ["MacLibraryExampleUITests/DialogUITests/testD1_showDialogOK()"]

    def test_call(self, *extra, drop=None, names=None):
        args = ["test-without-building", "-xctestrun", self.ROOT_DIR + "/dd-ui/Build/Products/x.xctestrun",
                "-destination", "platform=macOS,arch=arm64"] + ["-only-testing:" + n for n in (names or self.NAMES)] + \
            ["-derivedDataPath", self.ROOT_DIR + "/dd-test", "-resultBundlePath", self.ROOT_DIR + "/ui-0.xcresult"]
        if drop:
            i = args.index(drop)
            del args[i:i + 2]
        return args + list(extra)

    def test_the_planned_call_passes(self):
        self.assertEqual(r.call_problems(self.ROOT_DIR, self.test_call(), "test", self.NAMES), [])
        build = ["build-for-testing", "-workspace", self.ROOT_DIR + "/src/mac/MacWorkspace.xcworkspace", "-scheme",
                 "MacLibraryExample", "-derivedDataPath", self.ROOT_DIR + "/dd-ui"]
        self.assertEqual(r.call_problems(self.ROOT_DIR, build, "build"), [])

    def test_paths_outside_twice_or_missing(self):
        for args in (self.test_call(drop="-derivedDataPath"), self.test_call(drop="-resultBundlePath"),
                     self.test_call("-derivedDataPath", self.ROOT_DIR + "/again"),
                     self.test_call("-derivedDataPath=" + self.ROOT_DIR + "/x"),
                     [a.replace(self.ROOT_DIR + "/dd-test", "/Users/x/Library/Developer/Xcode/DerivedData") for a in self.test_call()],
                     [a.replace(self.ROOT_DIR + "/dd-test", self.ROOT_DIR + "/../escape") for a in self.test_call()],
                     [a.replace(self.ROOT_DIR + "/dd-test", self.ROOT_DIR) for a in self.test_call()],
                     self.test_call("build-for-testing"), self.test_call("test")):
            self.assertTrue(r.call_problems(self.ROOT_DIR, args, "test", self.NAMES), args)

    def test_names_must_be_the_plans(self):
        self.assertTrue(r.call_problems(self.ROOT_DIR, self.test_call(names=[]), "test", self.NAMES)
                        if False else r.call_problems(self.ROOT_DIR, [a for a in self.test_call() if not a.startswith("-only")],
                                                      "test", self.NAMES))
        self.assertTrue(r.call_problems(self.ROOT_DIR, self.test_call(names=["MacLibraryExampleUITests/ShareUITests/testS2_shareTextCopy()"]),
                                        "test", self.NAMES))
        self.assertTrue(r.call_problems(self.ROOT_DIR, self.test_call("-skip-testing:X"), "test", self.NAMES))
        self.assertTrue(r.call_problems(self.ROOT_DIR, self.test_call("-only-testing", "X"), "test", self.NAMES))
        self.assertTrue(r.call_problems(self.ROOT_DIR, self.test_call(), "test", []))
        # No names on either side is still refused: a test call without -only-testing runs everything.
        self.assertTrue(r.call_problems(self.ROOT_DIR, [a for a in self.test_call() if not a.startswith("-only")], "test", []))

    def test_only_the_runners_options_and_values(self):
        for extra in (("-xcconfig", "/tmp/x.xcconfig"), ("-test-iterations", "3"), ("OTHER_SWIFT_FLAGS=-DX",),
                      ("-parallel-testing-enabled", "YES"), ("-collect-test-diagnostics", "on-failure")):
            self.assertTrue(r.call_problems(self.ROOT_DIR, self.test_call(*extra), "test", self.NAMES), extra)
        wrong = [a.replace("platform=macOS,arch=arm64", "platform=macOS,arch=x86_64") for a in self.test_call()]
        self.assertTrue(r.call_problems(self.ROOT_DIR, wrong, "test", self.NAMES))
        self.assertTrue(r.call_problems(self.ROOT_DIR, self.test_call(drop="-destination"), "test", self.NAMES))
        build = ["build-for-testing", "-workspace", self.ROOT_DIR + "/src/mac/MacWorkspace.xcworkspace", "-scheme",
                 "UnityMacPlugin", "-derivedDataPath", self.ROOT_DIR + "/dd-ui"]
        self.assertTrue(r.call_problems(self.ROOT_DIR, build, "build"))

    def test_symlinks_in_the_paths(self):
        with tempfile.TemporaryDirectory() as d:
            root = os.path.realpath(d)
            os.mkdir(root + "/real")
            os.symlink(root + "/real", root + "/dd-test")
            args = ["-derivedDataPath", root + "/dd-test/x"]
            self.assertTrue(r.path_symlink_problems(root, args))
            self.assertEqual(r.path_symlink_problems(root, ["-derivedDataPath", root + "/real/x"]), [])

    def test_unit_names_on_this_mac_are_the_audited_suites(self):
        plan = mac_plan()
        self.assertEqual(r.unit_only_testing_arguments(plan, 0), ["-only-testing:MacLibraryTests/DetectionUseCaseTests"])
        for names in (["MacLibraryTests"], ["MacLibraryTests/PasteboardResolverTests"], ["MacLibraryExampleTests"], []):
            plan["unitInvocations"][0]["onlyTesting"] = names
            with self.assertRaises(r.RunnerError, msg=names):
                r.unit_only_testing_arguments(plan, 0)


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True,
                   env={"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid", "GIT_COMMITTER_NAME": "t",
                        "GIT_COMMITTER_EMAIL": "t@example.invalid", "HOME": str(repo), "PATH": os.environ.get("PATH", "")})


class Gate(unittest.TestCase):
    """R-19 before every xcodebuild on this Mac, and the approval's wiring (Claude B-8), in a temporary git
    repository with a temporary ledger."""

    def setUp(self):
        plan = mac_plan()
        self.repo = pathlib.Path(tempfile.mkdtemp(prefix="ntk-gate."))
        self.addCleanup(shutil.rmtree, self.repo, True)
        for relative in r.RUNNER_FILES:
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("runner file " + relative)
        (self.repo / "mac").mkdir()
        (self.repo / "mac" / "a.txt").write_text("a")
        git(self.repo, "init", "-q")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "x")
        self.head = subprocess.run(["git", "-C", str(self.repo), "rev-parse", "HEAD"], capture_output=True,
                                   text=True).stdout.strip()
        plan["head"] = self.head
        plan["macTree"] = r.tree_hash(self.repo, ["mac"])
        plan["runnerFiles"] = r.runner_file_hashes(self.repo)
        self.plan = plan
        self.approval = r.make_approval(plan)
        self.ledger = self.repo.parent / (self.repo.name + ".ledger")
        r.consume_approval(self.ledger, self.approval["approvalId"])

    def tearDown(self):
        shutil.rmtree(self.repo, ignore_errors=True)
        for path in (self.ledger, self.ledger.with_name(self.ledger.name + ".lock")):
            if path.exists():
                path.unlink()

    def problems(self, plan=None, approval=None, ledger=None):
        return r.gate_problems(plan or self.plan, approval or self.approval, self.repo, self.head, ledger or self.ledger)

    def test_the_approved_plan_passes(self):
        self.assertEqual(self.problems(), [])

    def test_each_change_stops(self):
        changed = json.loads(json.dumps(self.plan))
        changed["invocations"][0]["onlyTesting"].append("x")
        self.assertTrue(self.problems(plan=changed))
        other = self.repo.parent / (self.repo.name + ".other-ledger")
        self.assertTrue(self.problems(ledger=other))
        (self.repo / "scripts" / "mac_ui_runner.py").write_text("changed")
        self.assertTrue(self.problems())
        git(self.repo, "checkout", "--", "scripts/mac_ui_runner.py")
        self.assertEqual(self.problems(), [])
        (self.repo / "mac" / "a.txt").write_text("changed")
        self.assertTrue(self.problems())

    def test_the_approve_command_consumes_only_a_matching_approval(self):
        plan_path = self.repo.parent / (self.repo.name + ".plan.json")
        good = self.repo.parent / (self.repo.name + ".good.json")
        bad = self.repo.parent / (self.repo.name + ".bad.json")
        ledger = self.repo.parent / (self.repo.name + ".approve-ledger")
        for path in (plan_path, good, bad, ledger, ledger.with_name(ledger.name + ".lock")):
            self.addCleanup(lambda p=path: p.exists() and p.unlink())
        plan_path.write_text(json.dumps(self.plan))
        approval = r.make_approval(self.plan)
        good.write_text(json.dumps(approval))
        bad.write_text(json.dumps(dict(approval, allow=["panels"])))
        err = io.StringIO()
        with redirect_stderr(err), redirect_stdout(io.StringIO()):
            base = ["approve", "--plan", str(plan_path), "--repo", str(self.repo), "--ledger-for-self-test", str(ledger)]
            self.assertNotEqual(r.main(base + ["--approved", str(bad)]), 0)
            self.assertFalse(ledger.exists())  # refused: nothing consumed
            self.assertEqual(r.main(base + ["--approved", str(good)]), 0)
            self.assertEqual(r.ledger_ids(ledger.read_text()), [approval["approvalId"]])
            self.assertNotEqual(r.main(base + ["--approved", str(good)]), 0)  # once only
            self.assertEqual(r.ledger_ids(ledger.read_text()), [approval["approvalId"]])

    def test_a_plan_of_other_runner_files_or_another_tree(self):
        # git is clean here; only the hashes tell the plan was made from something else.
        other = json.loads(json.dumps(self.plan))
        other["runnerFiles"] = dict(other["runnerFiles"], **{"scripts/test_mac.sh": "0" * 64})
        self.assertTrue(r.runner_problems(other, self.repo))
        other = json.loads(json.dumps(self.plan))
        other["macTree"] = "0" * 64
        self.assertTrue(r.tree_problems(other, self.repo, self.head))
        self.assertEqual(r.tree_problems(self.plan, self.repo, self.head), [])


    def test_a_baseline_is_saved_only_from_the_planned_tree(self):
        self.assertFalse(r.snapshot_changed(self.repo, self.plan))
        (self.repo / "mac" / "a.txt").write_text("changed and committed")
        git(self.repo, "commit", "-q", "-am", "y")  # clean again, but not the tree the VM built (Codex v3 A-4)
        self.assertTrue(r.snapshot_changed(self.repo, self.plan))


    def test_the_baseline_names_the_runner_the_run_used(self):
        self.assertFalse(r.runner_changed(self.repo, self.plan))
        self.assertTrue(r.runner_changed(self.repo, dict(self.plan, runnerFiles={})))
        (self.repo / "scripts" / "test_mac.sh").write_text("edited while the VM ran")  # review v4: Codex A-3
        self.assertTrue(r.runner_changed(self.repo, self.plan))

    def test_the_vms_copy_of_the_runner_is_the_snapshot(self):
        snapshot = self.repo.parent / (self.repo.name + ".snapshot")
        snapshot.mkdir()
        self.addCleanup(shutil.rmtree, snapshot, True)
        for relative in r.RUNNER_FILES:
            shutil.copyfile(self.repo / relative, snapshot / os.path.basename(relative))
        hashes = r.runner_snapshot_hashes(snapshot)
        self.assertEqual(hashes, self.plan["runnerFiles"])
        vm = {k: v for k, v in hashes.items() if k != "scripts/mac_unit_audit.json"}
        self.assertTrue(r.runner_copy_matches(vm, hashes))
        self.assertFalse(r.runner_copy_matches(dict(vm, **{"scripts/test_mac.sh": "0" * 64}), hashes))
        self.assertFalse(r.runner_copy_matches({"scripts/test_mac.sh": vm["scripts/test_mac.sh"]}, hashes))
        self.assertFalse(r.runner_copy_matches({}, {}))


class Commands(unittest.TestCase):
    def test_the_approval_file_is_read_without_showing_its_place(self):
        with tempfile.TemporaryDirectory(prefix="Example Person (private) ") as folder:
            good = pathlib.Path(folder, "approval list.json")
            good.write_text(json.dumps({"stale": [{"mark": "abc"}]}))
            broken = pathlib.Path(folder, "broken.json")
            broken.write_text("{not json")
            out = pathlib.Path(folder, "stale.json")
            for path in (pathlib.Path(folder, "missing.json"), broken, pathlib.Path(folder)):
                err, std = io.StringIO(), io.StringIO()
                with redirect_stderr(err), redirect_stdout(std):
                    self.assertEqual(r.main(["approval-stale", "--approved", str(path), "--out", str(out)]), 1)
                shown = err.getvalue() + std.getvalue()
                self.assertIn("could not be read as an approval list", shown)  # review v4: Codex A-1
                for fragment in ("Example", "Person", "private", "missing", "broken", "Traceback", "/"):
                    self.assertNotIn(fragment, shown)
            with redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
                self.assertEqual(r.main(["approval-stale", "--approved", str(good), "--out", str(out)]), 0)
            self.assertEqual(json.loads(out.read_text()), [{"mark": "abc"}])

    def test_an_unexpected_error_shows_no_path(self):
        err = io.StringIO()
        with redirect_stderr(err):
            code = r.main(["fixture-compare", "--before", "/nonexistent/before.json", "--after", "/nonexistent/after.json"])
        self.assertEqual(code, 2)
        self.assertNotIn("/nonexistent", err.getvalue())
        self.assertIn("NTK-RUNNER:internal", err.getvalue())

    def test_stale_needs_exactly_one_mode(self):
        err = io.StringIO()
        with redirect_stderr(err):
            self.assertNotEqual(r.main(["stale", "--scan-root", "/nonexistent"]), 0)

    def test_the_guards_are_in_place(self):
        with self.assertRaises(OsOperationReached):
            os.kill(os.getpid(), 0)
        with self.assertRaises(OsOperationReached):
            subprocess.run(["/bin/ps", "-ax"], capture_output=True)
        with self.assertRaises(OsOperationReached):
            r.OsPort().processes()


def _real(args, timeout=90, env=None):
    """A real subprocess, for RealProcessesInTheVM only (it never runs on this Mac)."""
    process = _REAL_POPEN(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    out, err = process.communicate(timeout=timeout)
    return process.returncode, out, err


def _in_the_vm():
    """The same two facts the VM half reads: this is a VM, a VirtualMac (this Mac answers 0 and its model)."""
    try:
        return _real(["/usr/sbin/sysctl", "-n", "kern.hv_vmm_present"])[1].strip() == "1" and \
            _real(["/usr/sbin/sysctl", "-n", "hw.model"])[1].strip().startswith("VirtualMac")
    except OSError:
        return False


@unittest.skipUnless(_in_the_vm(), "real processes and signals run only in the VM (review v4: Codex B-3)")
class RealProcessesInTheVM(unittest.TestCase):
    """The supervisor perl with real processes: only the test's own children (sleep and sh)
    are started and signalled, and only inside the VM (the harness runs these there; this Mac skips them)."""

    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="ntk-real."))
        self.addCleanup(shutil.rmtree, self.dir, True)
        text = SCRIPT.read_text()
        self.perl = text[text.index("CAPPED_PERL='") + len("CAPPED_PERL='"):text.index("'", text.index("CAPPED_PERL='") + len("CAPPED_PERL='"))]
        self.env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.dir), "P": self.perl,
                    "D": str(self.dir), "RUNNER": str(ROOT / "scripts" / "mac_ui_runner.py"), "PY": sys.executable}

    def bash(self, script, timeout=90):
        return _real(["/bin/bash", "-c", script], timeout=timeout, env=self.env)

    def group(self, pgid):
        out = _real(["/bin/ps", "-axo", "pid=,pgid="])[1]
        return [int(a) for a, b in (line.split() for line in out.splitlines()) if int(b) == pgid]

    def wait_for(self, condition, seconds=40):
        deadline = time.time() + seconds
        while time.time() < deadline:
            if condition():
                return True
            time.sleep(0.2)
        return False

    def test_a_pid_file_that_cannot_be_made_starts_nothing(self):
        code, _, _ = self.bash('/usr/bin/perl -e "$P" 30 "$D/no/such/folder/pid" - /bin/sh -c \'touch "$D/started"; sleep 30\'')
        self.assertNotEqual(code, 0)
        time.sleep(1)
        self.assertFalse((self.dir / "started").exists())

    def test_term_stops_the_group_while_the_leader_is_its_own(self):
        code, out, err = self.bash('/usr/bin/perl -e "$P" 60 "$D/pid" - /bin/sh -c "sleep 60 & sleep 60" & w=$!\n'
                                   'for i in $(seq 1 50); do [ -s "$D/pid" ] && break; sleep 0.1; done; sleep 0.5\n'
                                   'kill -TERM "$w"; wait "$w"; echo "rc=$?"')
        self.assertIn("rc=143", out, err)
        self.assertEqual(self.group(int((self.dir / "pid").read_text())), [])

    def test_the_stop_file_stops_the_group(self):
        # How the shell asks on this Mac: it never signals a number (review v5: Codex A-3).
        code, out, err = self.bash('/usr/bin/perl -e "$P" 60 "$D/pid" "$D/stop" /bin/sh -c "sleep 60 & sleep 60" & w=$!\n'
                                   'for i in $(seq 1 50); do [ -s "$D/pid" ] && break; sleep 0.1; done; sleep 0.5\n'
                                   ': > "$D/stop"; wait "$w"; echo "rc=$?"')
        self.assertIn("rc=143", out, err)
        self.assertEqual(self.group(int((self.dir / "pid").read_text())), [])

    def test_a_shell_that_is_gone_leaves_nothing_running(self):
        # perl's parent is a bash that ends after a second, as a runner shell killed without its trap.
        code, out, err = self.bash('/bin/bash -c \'/usr/bin/perl -e "$P" 60 "$D/pid" - /bin/sh -c "sleep 60 & sleep 60" '
                                   '> /dev/null 2>&1 & sleep 1\'')
        pgid = int((self.dir / "pid").read_text())
        self.assertTrue(self.wait_for(lambda: self.group(pgid) == []), "the group of a supervisor whose shell ended")

    def test_nothing_is_sent_after_the_leader_was_reaped(self):
        code, out, err = self.bash('/usr/bin/perl -e "$P" 60 "$D/pid" - /bin/sh -c "/bin/sleep 60 > /dev/null 2>&1 & exit 0"; '
                                   'echo "rc=$?"')
        self.assertIn("rc=0", out, err)
        pgid = int((self.dir / "pid").read_text())
        left = self.group(pgid)
        self.assertEqual(len(left), 1)        # the leader ended and perl sent nothing to the rest of its group
        _real(["/bin/kill", "-TERM", str(left[0])])

    def test_the_time_limit(self):
        code, out, err = self.bash('/usr/bin/perl -e "$P" 1 "$D/pid" - /bin/sh -c "sleep 60"; echo "rc=$?"')
        self.assertIn("rc=142", out, err)
        self.assertEqual(self.group(int((self.dir / "pid").read_text())), [])


@unittest.skipUnless(_in_the_vm(), "the real process table is read only in the VM (review v6: Claude A-1, B-1)")
class RealCleanupInTheVM(unittest.TestCase):
    """The cleanup's judgement over the VM's real process table (libproc): what it removes is logged by a fake
    port (nothing is removed or signalled through it); only the test's own sh and sleep are started, and the
    one sleep left is ended by the test in the VM."""

    def setUp(self):
        self.scan = pathlib.Path(tempfile.mkdtemp(prefix="ntk-real-scan."))
        self.addCleanup(shutil.rmtree, self.scan, True)
        out = _real(["/usr/sbin/sysctl", "-n", "kern.boottime"])[1]
        self.boot = int(re.search(r"sec = (\d+)", out).group(1))
        self.root = r.make_run_folder(str(self.scan), "20261123T000000Z-abcdef", "a" * 32, self.boot, time.time())

    def port(self):
        test = self

        class Port:
            log = []

            def processes(self):
                return r._processes(_REAL_LIBPROC())

            def boottime(self):
                return test.boot

            def uid(self):
                return os.getuid()

            def remove(self, folder):
                self.log.append(("remove", folder))

            def remove_fixture(self, path):
                self.log.append(("fixture", path))

            def unregister(self, app):
                self.log.append(("unregister", app))
        return Port()

    def test_a_folder_with_only_its_marker_can_be_removed(self):
        port = self.port()
        self.assertIsNone(r.clean_run_folder(self.root, port, [], r._read_marker))  # Claude v6 A-1
        self.assertIn(("remove", self.root), port.log)
        table = r._processes(_REAL_LIBPROC())
        self.assertTrue(any(p["pid"] == os.getpid() and p["exe"] for p in table))
        self.assertFalse([p for p in table if p["uid"] == os.getuid() and p["exe"] is None and not p["zombie"]
                          and p["start"] and p["start"] >= r._read_marker(self.root)["created"]])

    def test_a_helper_left_by_its_leader_stops_the_next_call_and_keeps_the_folder(self):
        env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.scan), "ROOT": self.root,
               "RUNNER": str(ROOT / "scripts" / "mac_ui_runner.py"), "PY": sys.executable}
        text = SCRIPT.read_text()
        env["P"] = text[text.index("CAPPED_PERL='") + len("CAPPED_PERL='"):text.index("'", text.index("CAPPED_PERL='") + len("CAPPED_PERL='"))]
        code, out, err = _real(["/bin/bash", "-c",
                                '/usr/bin/perl -e "$P" 60 "$ROOT/xcodebuild.pid" - /bin/sh -c "/bin/sleep 60 > /dev/null 2>&1 & exit 0"'],
                               env=env)
        pgid = int(pathlib.Path(self.root, r.PIDFILE_NAME).read_text())
        marker_path = pathlib.Path(self.root, r.MARKER_NAME)
        marker = r.record_writer(json.loads(marker_path.read_text()), {"pid": pgid, "pgid": pgid, "start": 0.0, "exe": "/bin/sh"},
                                 "xcodebuild")
        marker_path.write_text(json.dumps(marker))
        try:
            code, out, err = _real(["/bin/bash", "-c", '"$PY" "$RUNNER" settle --root "$ROOT" --seconds 2 || exit 1\n'
                                                        'touch "$ROOT/next"'], env=env)
            self.assertEqual(code, 1, err)
            self.assertIn("NTK-STALE:alive 1 process(es) (1 group)", err)
            self.assertFalse(pathlib.Path(self.root, "next").exists())       # the next call never starts
            port = self.port()
            self.assertEqual(r.clean_run_folder(self.root, port, [], r._read_marker),
                             "NTK-STALE:alive 1 process(es) (1 group)")
            self.assertEqual(port.log, [])                                  # the folder stays
        finally:
            for p in r._processes(_REAL_LIBPROC()):
                if p["pgid"] == pgid and p["pid"] != pgid:
                    _real(["/bin/kill", "-TERM", str(p["pid"])])
        time.sleep(0.5)
        code, out, err = _real(["/bin/bash", "-c", '"$PY" "$RUNNER" settle --root "$ROOT" --seconds 5'], env=env)
        self.assertEqual(code, 0, err)
        self.assertIn(pgid, json.loads(marker_path.read_text())["closed"])  # shown empty: closed (Claude v6 C-1)


class PreludeLauncher(unittest.TestCase):
    """The VM prelude's behaviour (review v2: Codex A-1, B-4), run on a truncated copy of it: the copy ends
    right after the prelude with `echo PRELUDE-PASSED`, and its fact readers (/usr/sbin/sysctl,
    /usr/sbin/ioreg) are replaced by fakes in a temporary folder. The real script's VM half is never run."""

    UUID = "11111111-2222-3333-4444-555555555555"

    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="ntk-prelude."))
        self.addCleanup(shutil.rmtree, self.dir, True)
        text = SCRIPT.read_text()
        prelude = text[:text.index("# --- end of the VM prelude ---")]
        sysctl, ioreg = self.dir / "fake-sysctl", self.dir / "fake-ioreg"
        # Each fact is read once before the restart and once after it; `<fact>.after`, when present, is
        # what every read after the first returns (review v3: Codex B-4).
        fact = ('fact() { n=$(cat "%(d)s/$1.count" 2>/dev/null || echo 0); echo $((n + 1)) > "%(d)s/$1.count"; '
                'if [ "$n" -ge 1 ] && [ -f "%(d)s/$1.after" ]; then cat "%(d)s/$1.after"; else cat "%(d)s/$1"; fi; }\n'
                % {"d": self.dir})
        sysctl.write_text('#!/bin/sh\n' + fact + 'case "$2" in kern.hv_vmm_present) fact hv;; hw.model) fact model;; esac\n')
        ioreg.write_text('#!/bin/sh\n' + fact + 'printf \'  "IOPlatformUUID" = "%s"\\n\' "$(fact uuid)"\n')
        for fake in (sysctl, ioreg):
            fake.chmod(0o700)
        self.facts(hv="1", model="VirtualMac2,1", uuid=self.UUID)
        copy = prelude.replace("/usr/sbin/sysctl", str(sysctl)).replace("/usr/sbin/ioreg", str(ioreg))
        self.assertNotIn("/usr/sbin/sysctl", copy)
        self.copy = self.dir / "prelude.sh"
        self.copy.write_text(copy + 'echo "PRELUDE-PASSED $(compgen -e | sort | tr \'\\n\' \' \')"\nexit 0\n')

    def facts(self, hv=None, model=None, uuid=None):
        for name, value in (("hv", hv), ("model", model), ("uuid", uuid)):
            if value is not None:
                (self.dir / name).write_text(value + "\n")

    def run_copy(self, *args, env=None, bash=("/bin/bash",)):
        return subprocess.run([*bash, str(self.copy), *args], capture_output=True, text=True, timeout=30,
                              env=env if env is not None else {"PATH": "/usr/bin:/bin", "HOME": str(self.dir)})

    def test_the_restart_happens_whatever_the_caller_sets(self):
        env = {"PATH": "/usr/bin:/bin", "HOME": str(self.dir), "NTK_IN_VM_CLEAN": "1", "BASH_ENV": "/nonexistent",
               "BASH_FUNC_command%%": "() { echo 1; }", "EXTRA": "x"}
        finished = self.run_copy("--in-vm", "clean", "20261123T000000Z-abcdef", self.UUID, env=env)
        self.assertEqual(finished.returncode, 0, finished.stderr)
        passed = finished.stdout.strip()
        self.assertTrue(passed.startswith("PRELUDE-PASSED"))
        self.assertNotIn("NTK_IN_VM_CLEAN", passed)
        self.assertNotIn("EXTRA", passed)

    def test_the_started_side_refuses_any_other_environment(self):
        args = ("--in-vm-clean", "clean", "20261123T000000Z-abcdef", self.UUID)
        self.assertEqual(self.run_copy(*args).returncode, 96)  # not privileged
        clean = {"HOME": str(self.dir), "USER": "u", "LOGNAME": "u", "LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}
        privileged = ("/bin/bash", "--noprofile", "--norc", "-p")
        self.assertEqual(self.run_copy(*args, env=clean, bash=privileged).returncode, 0)
        self.assertEqual(self.run_copy(*args, env=dict(clean, EXTRA="x"), bash=privileged).returncode, 96)
        self.assertEqual(self.run_copy(*args, env=dict(clean, PATH="/tmp:/usr/bin:/bin:/usr/sbin:/sbin"),
                                       bash=privileged).returncode, 96)

    def test_each_fact_stops_it_before_and_after_the_restart(self):
        args = ("--in-vm", "clean", "20261123T000000Z-abcdef", self.UUID)
        for change in ({"hv": "0"}, {"model": "Mac15,6"}, {"uuid": "00000000-0000-0000-0000-000000000000"}):
            self.facts(**change)
            finished = self.run_copy(*args)
            self.assertEqual(finished.returncode, 96, change)
            self.assertNotIn("PRELUDE-PASSED", finished.stdout)
            self.facts(hv="1", model="VirtualMac2,1", uuid=self.UUID)
        self.assertEqual(self.run_copy("--in-vm", "clean", "20261123T000000Z-abcdef").returncode, 96)  # no UUID

    def test_each_fact_changed_only_after_the_restart_stops_it(self):
        args = ("--in-vm", "clean", "20261123T000000Z-abcdef", self.UUID)
        self.assertEqual(self.run_copy(*args).returncode, 0)
        for name, after in (("hv", "0"), ("model", "Mac15,6"), ("uuid", "00000000-0000-0000-0000-000000000000")):
            for f in self.dir.glob("*.count"):
                f.unlink()
            (self.dir / (name + ".after")).write_text(after + "\n")
            finished = self.run_copy(*args)
            self.assertEqual(finished.returncode, 96, name)
            self.assertNotIn("PRELUDE-PASSED", finished.stdout)
            self.assertIn("2", (self.dir / (name + ".count")).read_text(), name)  # read again after the restart
            (self.dir / (name + ".after")).unlink()

    def test_a_copy_with_anything_destructive_is_never_run(self):
        for line in ("rm -rf \"$HOME/x\"", "pkill -x Finder", "killall Dock", "kill 1", "defaults write a b c",
                     "lsregister -u x"):
            bad = self.dir / "bad.sh"
            bad.write_text(self.copy.read_text().replace("echo \"PRELUDE-PASSED", line + "\necho \"PRELUDE-PASSED", 1))
            with self.assertRaises(OsOperationReached, msg=line):
                subprocess.run(["/bin/bash", str(bad), "--in-vm", "clean", "x", self.UUID], capture_output=True)

    def test_the_guard_refuses_the_real_script_with_in_vm(self):
        with self.assertRaises(OsOperationReached):
            subprocess.run(["/bin/bash", str(SCRIPT), "--in-vm", "clean", "x", "y"], capture_output=True)
        with self.assertRaises(OsOperationReached):
            subprocess.run(["/bin/bash", str(SCRIPT), "--in-vm-clean", "clean", "x", "y"], capture_output=True)


class ShellOrder(unittest.TestCase):
    """The order of the script (design 7 "中断", review v1): read, never run."""

    def setUp(self):
        self.text = SCRIPT.read_text()

    def test_the_vm_half_starts_clean_and_checks_three_facts_first(self):
        lines = [l.strip() for l in self.text.splitlines() if l.strip() and not l.lstrip().startswith("#")]
        self.assertEqual(lines[0], "set -euo pipefail")
        self.assertEqual(lines[1], 'if [[ "${1:-}" == "--in-vm" || "${1:-}" == "--in-vm-clean" ]]; then')
        self.assertTrue(lines[2].startswith('[[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] || {'))
        self.assertTrue(lines[3].startswith('case "$(/usr/sbin/sysctl -n hw.model 2>/dev/null)" in VirtualMac*) ;; *)'))
        self.assertIn('/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice', lines[4])
        self.assertIn('== "$4" ]]', lines[4])
        self.assertTrue(lines[5].endswith("exit 96; }"))
        self.assertEqual(lines[6], 'if [[ "$1" == "--in-vm" ]]; then')
        self.assertTrue(lines[7].startswith("exec /usr/bin/env -i HOME="))
        self.assertIn('/bin/bash --noprofile --norc -p "${BASH_SOURCE[0]}" --in-vm-clean "${@:2}"', lines[8])
        self.assertNotIn("NTK_IN_VM_CLEAN", self.text)  # nothing the caller can set skips the restart (Codex v2 A-1)
        prelude = self.text[:self.text.index("# --- end of the VM prelude ---")]
        self.assertIn('[[ -o privileged && -z "$(declare -F)" && "${PATH}" == "/usr/bin:/bin:/usr/sbin:/sbin"', prelude)
        self.assertIn("HOME|USER|LOGNAME|LC_ALL|PATH|PWD|SHLVL|OLDPWD|_) ;;", prelude)
        body = [l.strip() for l in function_body(self.text, "in_vm_main").splitlines()]
        self.assertTrue(body[0].startswith('[[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] || {'))
        self.assertTrue(body[1].startswith('case "$(/usr/sbin/sysctl -n hw.model 2>/dev/null)" in VirtualMac*) ;; *)'))
        self.assertIn("/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice", body[2])
        self.assertEqual(body[3], '|| { echo "Error: --in-vm runs only in the qualified VM" >&2; exit 96; }')
        self.assertIn('\nif [[ "${1:-}" == "--in-vm-clean" ]]; then shift; in_vm_main "$@"; exit 0; fi\n', self.text)

    def test_the_script_ends_on_lines_that_end_it(self):
        # bash reads a line whole before it runs it: after a long run nothing more is read from the file,
        # however it changed meanwhile (review v5: Claude B-1).
        code = [l for l in self.text.splitlines() if l.strip() and not l.lstrip().startswith("#")]
        self.assertEqual(code[-1], 'main "$@"; exit $?')
        self.assertEqual(code[-2], 'if [[ "${1:-}" == "--in-vm-clean" ]]; then shift; in_vm_main "$@"; exit 0; fi')
        self.assertEqual(code[-3], "}")
        # Every other line at the top is a function, an assignment of a constant, `set` or the prelude.
        top = self.text[:self.text.index("\nmain() {")]
        outside = re.sub(r"^[a-z_]+\(\) \{.*?^\}\n", "", top, flags=re.S | re.M)
        outside = re.sub(r"^CAPPED_PERL='.*?'$", "", outside, flags=re.S | re.M)
        outside = outside[outside.index("# --- end of the VM prelude ---"):]
        for line in outside.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or stripped.startswith(("unset ", "for __name", "case ", "done",
                                                                                 "-p ", "TIME_FLAGS=", "-maximum")):
                continue
            self.assertRegex(stripped, r"^[A-Z_]+=(\"[^\"`]*\"|'[^']*'|\(.*)(; [A-Z_]+=\"[^\"`]*\")*$", stripped)

    def test_nothing_destructive_runs_before_the_vm_dispatch(self):
        top = self.text[:self.text.index('\nif [[ "${1:-}" == "--in-vm-clean" ]]; then shift;')]
        top = top[:top.index("\nmain() {")]
        outside = re.sub(r"^[a-z_]+\(\) \{.*?^\}\n", "", top, flags=re.S | re.M)
        outside = re.sub(r"^CAPPED_PERL='.*?'$", "", outside, flags=re.S | re.M)
        for line in outside.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or re.match(r"^[A-Z_]+=\"[^\"$`]*\"$", stripped):
                continue
            self.assertIsNone(re.search(r"\b(rm|pkill|killall|kill|defaults|lsregister|ssh|tart|xcodebuild|mkdir|tee)\b",
                                        stripped), stripped)

    def test_one_trap_covers_every_exit_before_anything_is_made(self):
        main = function_body(self.text, "main")
        self.assertLess(main.index("trap on_exit EXIT"), main.index('RUN_ID="$(date'))
        self.assertIn("trap 'exit 129' HUP", main)
        self.assertLess(main.index('PRIVATE="$(umask 077; mktemp -d'), main.index("trap on_exit EXIT"))
        self.assertLess(main.index("trap on_exit EXIT"), main.index('runner private --dir "${PRIVATE}" --own "$$"'))
        self.assertLess(main.index('runner private --dir "${PRIVATE}" --own "$$"'),
                        main.index('runner private --scan-root "${SCAN_ROOT}" --dir "${PRIVATE}"'))
        body = function_body(self.text, "on_exit")
        self.assertLess(body.index("mac_cleanup"), body.index('rm -rf "${PRIVATE}"'))
        run_mac = function_body(self.text, "run_mac")
        self.assertLess(run_mac.index("runner approve"), run_mac.index("runner make-run-folder"))
        self.assertNotIn("mktemp", run_mac)
        self.assertLess(run_mac.index("runner make-run-folder"), run_mac.index("mac_xcodebuild "))
        at = run_mac.index("--current-root \"${MAC_TMP}\" --clean")
        stop = run_mac[at:at + 200]
        self.assertIn('--approved "${MAC_TMP}/approval.approved.json" --repo "${ROOT_DIR}"', stop)

    def test_perl_signals_the_group_only_while_its_leader_is_its_own(self):
        perl = self.text[self.text.index("CAPPED_PERL='"):self.text.index("capped_group() {")]
        gone = perl[perl.index("my $gone = sub {"):perl.index("};", perl.index("my $gone = sub {"))]
        self.assertIn("return 1 if $reaped;", gone)
        self.assertIn("my $r = waitpid($pid, POSIX::WNOHANG());", gone)
        self.assertIn("if ($r == $pid) { $status = $?; $reaped = 1; return 1; }", gone)
        self.assertIn("if ($r == -1) { $reaped = 1; return 1; }", gone)
        stop = perl[perl.index("my $stop = sub {"):perl.index("};", perl.index("my $stop = sub {"))]
        self.assertLess(stop.index("return if $gone->();"), stop.index('kill "TERM", -$pid;'))
        self.assertIn("for (1..60) { return if $gone->();", stop)
        kill = stop.index('kill "KILL", -$pid;')
        self.assertEqual(stop[kill - len("return if $gone->();\n    "):kill], "return if $gone->();\n    ")
        self.assertIn("return unless $pid > 0;", stop)
        self.assertEqual(perl.count("kill "), 2)  # only these two, both to its own unreaped child's group
        self.assertNotIn("alarm", perl)

    def test_perl_stops_on_time_on_the_stop_file_and_when_its_shell_is_gone(self):
        perl = self.text[self.text.index("CAPPED_PERL='"):self.text.index("capped_group() {")]
        loop = perl[perl.index("until ($gone->()) {"):]
        self.assertIn("if (time >= $deadline) { $stop->(); exit 142; }", loop)
        self.assertIn('if ($stopfile ne "-" && -e $stopfile) { $stop->(); exit 143; }', loop)  # Codex v5 A-3
        self.assertIn("if (getppid() != $parent) { $stop->(); exit 129; }", loop)

    def test_perl_starts_nothing_it_cannot_record(self):
        perl = self.text[self.text.index("CAPPED_PERL='"):self.text.index("capped_group() {")]
        fork = perl.index("my $child = fork;")
        self.assertLess(perl.index('open($f, ">", $pidfile) or die'), fork)   # review v4: Codex A-2
        self.assertLess(perl.index("for my $name (keys %number) { $SIG{$name}"), fork)
        self.assertLess(perl.index("POSIX::sigprocmask(POSIX::SIG_BLOCK(), $blocked, $before);"), fork)  # Claude v5 C-1
        unblock = perl.index("POSIX::sigprocmask(POSIX::SIG_SETMASK(), $before);\n  if ($f)")
        self.assertLess(perl.index("$pid = $child; setpgrp($pid, $pid);"), unblock)
        self.assertIn('if ($f) { unless ((print {$f} "$pid\\n") && close($f)) { $stop->(); exit 125; } }', perl)

    def test_the_vm_writes_down_what_each_xcodebuild_left(self):
        capped = function_body(self.text, "capped_group")
        self.assertLess(capped.index('/usr/bin/perl -e "${CAPPED_PERL}"'),
                        capped.index('vrunner settle-report --pgid "$(cat "${pidfile}")" --log "${RUN_DIR}/settle.log"'))
        self.assertIn('[[ "${pidfile}" != - ]] || pidfile="${RUN_DIR}/capped.pid"', capped)  # review v6: Claude B-1
        self.assertIn('return "${code}"', capped)
        self.assertIn('  if [[ -s "${pidfile}" ]]; then\n    vrunner settle-report', capped)
        self.assertIn('vrunner settle-summary --log "${RUN_DIR}/settle.log"', function_body(self.text, "vm_finish"))

    def test_the_shell_never_signals_a_number_on_this_mac(self):
        stop = function_body(self.text, "stop_waiter")
        self.assertIn(': > "${MAC_STOPFILE}"\n  wait "${MAC_WAITER}"', stop)   # review v5: Codex A-3
        host = self.text[self.text.index("mac_gate() {"):]
        host = host[:host.index("\nmain() {")]
        for line in host.splitlines():
            if not line.strip().startswith("#"):
                self.assertIsNone(re.search(r"\b(kill|pkill|killall)\b", line), line)
        gate = function_body(self.text, "mac_xcodebuild")
        self.assertIn('"${MAC_PIDFILE}" "${MAC_STOPFILE}" /usr/bin/env -i', gate)
        self.assertLess(gate.index('\n  runner marker --root "${MAC_TMP}" --launching || fail'),
                        gate.index('/usr/bin/perl -e "${CAPPED_PERL}"'))  # review v4: Codex A-2
        wait = gate.index('wait "${MAC_WAITER}" || code=$?')
        self.assertLess(wait, gate.index('runner settle --root "${MAC_TMP}" || exit 1'))  # Codex v5 A-2
        self.assertLess(gate.index("runner settle"), gate.index('rm -f "${MAC_PIDFILE}"\n  return'))
        self.assertLess(function_body(self.text, "mac_cleanup").index("stop_waiter"),
                        function_body(self.text, "mac_cleanup").index("runner stop-current"))
        self.assertNotIn("own-child", self.text)
        self.assertNotIn("MAC_KEEP", self.text)

    def test_the_approval_file_is_read_only_by_the_runner(self):
        self.assertNotIn('open(sys.argv[1])).get("stale")', self.text)          # review v4: Codex A-1
        self.assertIn('runner approval-stale --approved "${APPROVED}" --out "${stale}"', self.text)
        for line in self.text.splitlines():
            if "${APPROVED}" in line and "python3" in line:
                self.fail(line)
        self.assertIn('[[ -f "${APPROVED}" && -r "${APPROVED}" ]] || fail "the approval file does not exist or cannot be read"',
                      self.text)

    def test_the_vm_runs_the_runner_snapshot_the_plan_names(self):
        push = function_body(self.text, "vm_push")
        self.assertLess(push.index('runner runner-hashes --dir "${PRIVATE}/runner-snapshot"'),
                        push.index('(cd "${PRIVATE}/runner-snapshot" && COPYFILE_DISABLE=1 tar'))  # Codex v4 A-3
        self.assertNotIn('cd "${ROOT_DIR}/scripts"', push)
        body = function_body(self.text, "vm_enumeration")
        self.assertLess(body.index('\n  runner runner-hashes-match --vm "$(vm_op runner-hashes "${RUN_ID}")"'),
                        body.index("vm_op clean"))
        self.assertIn('--snapshot "${PRIVATE}/runner-files.json" \\\n    || fail "the VM\'s copy of the runner', body)
        vm_op = self.text[self.text.index("    runner-hashes) "):]
        vm_op = vm_op[:vm_op.index(";;")]
        self.assertEqual(vm_op.count('/usr/bin/shasum -a 256 "${RUN_DIR}/runner/'), 2)  # Claude v5 C-2
        self.assertNotIn("vrunner", vm_op)
        self.assertNotIn("python3", vm_op)
        self.assertNotIn("mac_ui_runner.py runner-hashes", vm_op)
        self.assertEqual(self.text.count('--runner-files "${PRIVATE}/runner-files.json"'), 2)

    def test_the_cleanup_stops_writers_before_anything_goes(self):
        self.assertIn('runner stop-current --root "${MAC_TMP}"', function_body(self.text, "mac_cleanup"))
        self.assertNotIn("pkill", function_body(self.text, "mac_cleanup"))

    def test_every_xcodebuild_of_this_mac_passes_the_gate_and_the_call_check(self):
        body = function_body(self.text, "run_mac")
        direct = [line for line in body.splitlines() if re.search(r"(^|\s)xcodebuild\s", line)
                  and "mac_xcodebuild" not in line and "-version" not in line and not line.strip().startswith("#")]
        self.assertEqual(direct, [])
        gate = function_body(self.text, "mac_xcodebuild")
        start = gate.index('/usr/bin/perl -e "${CAPPED_PERL}"')
        self.assertLess(gate.index("mac_gate"), gate.index("runner check-call"))
        self.assertLess(gate.index("runner check-call"), start)
        self.assertIn("|| exit 97", gate[gate.index("runner check-call"):start])
        self.assertIn('/usr/bin/env -i "${environment[@]}"', gate)   # Claude v2 C-2
        self.assertIn('< /dev/null > "${log}" 2>&1 &\n  MAC_WAITER=$!', gate)  # $! is perl (Claude v2 B-1)
        self.assertIn('TMPDIR="${MAC_TMP}/tmp/"', gate)  # Claude v3 B-1
        self.assertNotIn("capped_group", gate)
        self.assertIn('runner marker --root "${MAC_TMP}" --pid', gate)
        self.assertIn('--expect-under "$(cd -P "${MAC_XCODE_DIR}" && pwd -P)"', gate)
        self.assertNotIn("kill", gate)
        self.assertIn('    stop_waiter\n    fail "the xcodebuild could not be recorded', gate)
        cleanup = function_body(self.text, "mac_cleanup")
        self.assertLess(cleanup.index("stop_waiter"), cleanup.index("runner stop-current"))

    def test_the_vm_builds_the_tree_the_plan_names(self):
        body = function_body(self.text, "vm_enumeration")
        self.assertLess(body.index("vm_push"), body.index('"$(vm_op tree-hash "${RUN_ID}")" == "${mac_tree}"'))
        self.assertLess(body.index('== "${mac_tree}"'), body.index("vm_op clean"))  # before the build (Codex v3 A-4)
        self.assertIn('git -C "${ROOT_DIR}" rev-parse HEAD)" == "${head}"', body)
        self.assertEqual(self.text.count('vm_enumeration "${head}" "${mac_tree}"'), 2)
        self.assertIn('tree-hash) vrunner tree-hash --dir "${RUN_DIR}/src" ;;', self.text)

    def test_tmpdir_names_are_counted_around_the_run(self):
        body = function_body(self.text, "run_mac")
        before = body.index('runner tmp-names --dir "${SCAN_ROOT}" --out "${MAC_TMP}/tmp-before.json"')
        self.assertLess(before, body.index("mac_xcodebuild"))  # Claude v3 B-1
        self.assertLess(body.rindex("mac_xcodebuild"),
                        body.index('runner tmp-names --dir "${SCAN_ROOT}" --compare "${MAC_TMP}/tmp-before.json"'))

    def test_names_are_read_on_their_own(self):
        body = function_body(self.text, "read_only_testing")
        self.assertIn('|| fail "the planned names could not be read"', body)
        self.assertIn('[[ ${#ONLY_TESTING[@]} -gt 0 ]] || fail', body)
        for name in ("vm_unit", "vm_ui"):
            vm_body = function_body(self.text, name)
            self.assertIn('[[ -n "${args}" ]] || exit 1', vm_body)
        self.assertNotIn("$(runner only-testing", function_body(self.text, "run_mac"))

    def test_every_ssh_command_checks_the_vm(self):
        body = function_body(self.text, "vm_ssh")
        self.assertIn('ps -axo args= | runner tart-check --ps - --vm "${VM_NAME}" || exit 96', body)
        self.assertIn("[ \\\"\\$u\\\" = '${VM_UUID}' ] && [ \\\"\\$b\\\" = '${VM_BOOT}' ] || {", body)
        self.assertIn("exit 96; }; $*", body)
        self.assertEqual(function_body(self.text, "vm_op").count("vm_ssh "), 1)
        self.assertIn("--in-vm ${op} ${id} ${VM_UUID}", function_body(self.text, "vm_op"))
        self.assertIn("ssh -F /dev/null", function_body(self.text, "vm_ssh_raw"))

    def test_the_boot_time_is_the_sec_field(self):
        # `{ sec = 1795358134, usec = 232279 } ...`: a greedy `.*sec =` took the usec (found in the VM).
        self.assertEqual(self.text.count("sed -E 's/^\\{ sec = ([0-9]+),.*/\\1/'"), 1)
        self.assertEqual(self.text.count("sed -E 's/^\\\\{ sec = ([0-9]+),.*/\\\\1/'"), 1)
        self.assertNotIn(".*sec = ", self.text)

    def test_raw_things_stay_private(self):
        self.assertNotIn(".ps.txt", self.text)
        body = function_body(self.text, "vm_qualify")
        self.assertIn("ps -axo args= | runner vm-qualify", body)
        self.assertNotIn("${OUT}/.", body)
        self.assertIn('"${PRIVATE}/lsregister.txt"', function_body(self.text, "run_mac"))

    def test_a_call_without_results_stops_the_vm_run(self):
        body = function_body(self.text, "run_vm")
        self.assertIn('    if [[ "${rc}" != 0 || "$((status + passed))" == 0 ]]; then\n', body)
        self.assertIn('[[ "${rc}" != 96 ]] || fail', body)
        self.assertIn('--kind runStopped', body)
        self.assertIn('"${passed}" != 1', body)

    def test_where_is_required(self):
        # The script runs with a PATH that holds only what its argument checks need: whatever a
        # broken check lets through cannot reach ssh, tart, xcodebuild, pkill, defaults or the clock.
        with tempfile.TemporaryDirectory() as tools:
            for name in ("dirname", "basename"):
                found = shutil.which(name)
                if found:
                    os.symlink(found, pathlib.Path(tools) / name)
            # The interpreter itself, not /usr/bin/python3 (in the VM a shim that looks for Xcode).
            os.symlink(os.path.realpath(sys.executable), pathlib.Path(tools) / "python3")
            env = {"PATH": tools, "HOME": tools}

            def run(*args):
                return subprocess.run(["/bin/bash", str(SCRIPT), *args], capture_output=True, text=True, env=env, timeout=60)

            finished = run()
            self.assertNotEqual(finished.returncode, 0)
            self.assertIn("--where vm|mac is required", finished.stderr)
            self.assertIn("--approved", run("--where", "mac").stderr)
            self.assertIn("for --where mac", run("--where", "vm", "--allow", "panels").stderr)
            self.assertIn("separate runs", run("--where", "mac", "--dry-run", "--approved", "x").stderr)
            self.assertIn("not implemented", run("--where", "mac", "--dry-run", "--allow-lsregister").stderr)

if __name__ == "__main__":
    unittest.main()
