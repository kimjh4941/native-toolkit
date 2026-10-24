"""Self-tests of scripts/ios_ui_runner.py and the device guards of scripts/test_ios.sh.

The runner is what keeps the UI tests off the parts of the user's private iPhone they were not
allowed to touch (iOS UI test design, U-9 and 6.3). A runner that quietly selects too much, or a
check that quietly stops checking, would look exactly like one that works, so every case here
breaks one decision on purpose (design chapter 7, the runner's rows) and asserts that it is
caught, next to the near-miss that must pass.

The fixtures in fixtures/ios_ui_runner/ are copied from real output of Xcode 26.3 on the
iPhone 17 (iOS 26.2) simulator, stage 0d (2026-10-24); paths are replaced and the simctl lists
are cut down to four simulators:
  enumeration.json             -enumerate-tests ... -test-enumeration-format json (the full tree)
  otool-ov-device.txt, otool-l-device.txt
                               otool -ov / -l of IosLibraryExampleUITests.xctest built for
                               generic/platform=iOS (arm64, unsigned; no device involved)
  otool-ov-probe.txt, otool-l-probe.txt
                               the same for a probe built with swiftc for iphoneos from:
                                 class ProbeBase: XCTestCase { func testInheritedPlain() {} }
                                 final class ProbeChild: ProbeBase {
                                     func testPlain() {}; func testThrows() throws {}
                                     @MainActor func testMainActorPlain() {}
                                     @MainActor func testMainActorThrows() throws {}
                                     func helper(_ x: Int) {} }
  xcresult-d1-*.json           xcresulttool get test-results tests/summary of a run that named
                               DialogUITests/testD1_showAlertOK() and a test that does not exist
  xcresult-dialog-*.json       the same for the DialogUITests class (15 tests) run by test_ios.sh
  xcresult-unit-example-tests.json
                               IosLibraryExampleTests (Swift Testing)
  attachments-d1/              xcresulttool export attachments of the D1 run (button coverage)

Run: python3 -m unittest discover -s scripts/tests
"""

import json
import os
import plistlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import ios_ui_runner as r  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "ios_ui_runner"
TESTS_DIR = ROOT / "ios" / "IosLibraryExample" / "IosLibraryExampleUITests"
SAMPLE_DIR = ROOT / "ios" / "IosLibraryExample" / "IosLibraryExample"
PBXPROJ = ROOT / "ios" / "IosLibraryExample" / "IosLibraryExample.xcodeproj" / "project.pbxproj"
SCRIPT = ROOT / "scripts" / "test_ios.sh"
SIMULATOR = "73A3F720-16B5-45F6-A743-E9D853C92424"
FAKE_DEVICE = "11111111-2222-3333-4444-555555555555"
HEAD = "c70be7d4c70be7d4c70be7d4c70be7d4c70be7d4"


def fixture(name):
    return (FIXTURES / name).read_text(encoding="utf-8")


def enumeration():
    return r.parse_enumeration(fixture("enumeration.json"))


def declarations():
    return r.parse_declarations((TESTS_DIR / r.DECLARATIONS_FILE).read_text(encoding="utf-8"))


def ident(key):
    return r.enumeration_id_from_key(key)


RUNNER = ROOT / "scripts" / "ios_ui_runner.py"
REPO_TESTS = pathlib.Path("ios") / "IosLibraryExample" / "IosLibraryExampleUITests"


def cli(*args):
    return subprocess.run([sys.executable, str(RUNNER), *map(str, args)], capture_output=True, text=True)


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), "-c", "commit.gpgsign=false", "-c", "user.email=t@example.com",
                           "-c", "user.name=t", *args], check=True, capture_output=True, text=True).stdout.strip()


def make_repo(directory):
    """A git repository with one committed file under ios/ (for the R-9 tree checks)."""
    repo = directory / "repo"
    (repo / REPO_TESTS).mkdir(parents=True)
    (repo / REPO_TESTS / "A.swift").write_text("import XCTest\n")
    (repo / "scripts").mkdir()
    for relative in r.RUNNER_FILES:
        shutil.copy(ROOT / relative, repo / relative)
    git(repo, "init", "-q")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "init")
    return repo


def write_device_plan(repo, allowed=("systemui",), selected_change=None):
    plan = r.make_plan("device", FAKE_DEVICE, SIMULATOR, enumeration(), declarations(), list(allowed), None,
                       git(repo, "rev-parse", "HEAD"), r.tests_folder_hash(repo / REPO_TESTS), [], False,
                       runner_files=r.runner_file_hashes(repo))
    plan_path, approval_path = repo.parent / "plan.json", repo.parent / "approval.json"
    plan_path.write_text(json.dumps(plan))
    approval = r.make_approval(plan)
    if selected_change:
        selected_change(approval)
    approval_path.write_text(json.dumps(approval))
    return plan_path, approval_path, plan


def approve_args(repo, plan_path, approval_path):
    return ["--plan", plan_path, "--approved", approval_path, "--repo", repo, "--head", git(repo, "rev-parse", "HEAD"),
            "--tests-dir", repo / REPO_TESTS, "--ledger-for-self-test", repo.parent / "ledger.log"]


class Destination(unittest.TestCase):

    def setUp(self):
        self.sims = r.simulator_udids(fixture("simctl-devices.json"))

    def test_a_listed_udid_is_a_simulator(self):
        self.assertEqual(r.classify_destination(SIMULATOR, self.sims), "simulator")

    def test_an_unlisted_udid_is_the_device(self):
        # Mutation 7 "柱 1（判定）": "not in simctl list -> simulator" (fail open) would land here.
        self.assertEqual(r.classify_destination(FAKE_DEVICE, self.sims), "device")
        self.assertEqual(r.classify_destination(SIMULATOR.lower(), self.sims), "device")

    def test_an_empty_udid_is_refused(self):
        with self.assertRaises(r.RunnerError):
            r.classify_destination("", self.sims)

    def test_the_enumeration_always_goes_to_a_simulator(self):
        # Mutation 7 "柱 1（列挙）": enumerating on the device.
        self.assertEqual(r.enumeration_destination("device", FAKE_DEVICE, SIMULATOR, self.sims), SIMULATOR)
        for bad in (FAKE_DEVICE, "", "00000000-0000-0000-0000-000000000000"):
            with self.subTest(enumerate_udid=bad), self.assertRaises(r.RunnerError):
                r.enumeration_destination("device", FAKE_DEVICE, bad, self.sims)
        self.assertEqual(r.enumeration_destination("simulator", SIMULATOR, "", self.sims), SIMULATOR)

    def test_the_environment_of_the_simulator(self):
        env = r.simulator_environment(SIMULATOR, fixture("simctl-devices.json"), fixture("simctl-runtimes.json"), "en-JP")
        self.assertEqual((env["model"], env["os"], env["osBuild"]), ("iPhone 17", "26.2", "23C54"))
        self.assertEqual(r.baseline_name(env), "test_ios.baseline.iPhone_17-26.2.json")
        self.assertEqual(r.environment_warnings(env, None), [])
        env["language"] = "ja-JP"
        self.assertTrue(r.environment_warnings(env, {"osBuild": "23C54"}))

    def test_devicectl_must_name_the_same_device(self):
        info = {"result": {"hardwareProperties": {"udid": FAKE_DEVICE, "marketingName": "iPhone XS"},
                           "deviceProperties": {"osVersionNumber": "18.7.2", "osBuildUpdate": "22H124"}}}
        env = r.device_environment(FAKE_DEVICE, json.dumps(info))
        self.assertEqual(r.baseline_name(env), "test_ios.baseline.iPhone_XS-18.7.2.json")
        with self.assertRaises(r.RunnerError):
            r.device_environment("99999999-2222-3333-4444-555555555555", json.dumps(info))


class Names(unittest.TestCase):

    def test_the_three_shapes_give_one_key(self):
        key = "DialogUITests/testD1_showAlertOK"
        self.assertEqual(r.key_from_enumeration_id("IosLibraryExampleUITests/DialogUITests/testD1_showAlertOK()"), key)
        self.assertEqual(r.key_from_node_id("DialogUITests/testD1_showAlertOK()"), key)
        self.assertEqual(r.key_from_self_name("-[DialogUITests testD1_showAlertOK]"), key)

    def test_other_shapes_are_refused(self):
        for bad in ("IosLibraryExampleUITests/DialogUITests/testD1", "Other/DialogUITests/testD1()",
                    "IosLibraryExampleUITests/DialogUITests/helper()"):
            with self.subTest(bad=bad), self.assertRaises(r.RunnerError):
                r.key_from_enumeration_id(bad)
        for bad in ("-[IosLibraryExampleUITests.DialogUITests testD1]", "DialogUITests/testD1"):
            with self.subTest(bad=bad), self.assertRaises(r.RunnerError):
                r.key_from_self_name(bad) if bad.startswith("-[") else r.key_from_node_id(bad)


class Enumeration(unittest.TestCase):

    def test_the_real_enumeration_matches_the_table(self):
        identifiers = enumeration()
        self.assertEqual(len(identifiers), 99)
        self.assertNotIn("IosLibraryExampleUITests/SampleUITestCase", identifiers)
        self.assertEqual(r.check_enumeration(identifiers, declarations()), [])

    def test_a_class_without_methods_other_than_the_base_stops(self):
        data = json.loads(fixture("enumeration.json"))
        data["values"][0]["enabledTests"].append({"identifier": "IosLibraryExampleUITests/HelperBase"})
        with self.assertRaises(r.RunnerError):
            r.parse_enumeration(json.dumps(data))

    def test_enumeration_errors_stop(self):
        data = json.loads(fixture("enumeration.json"))
        data["errors"] = ["something"]
        with self.assertRaises(r.RunnerError):
            r.parse_enumeration(json.dumps(data))

    def test_a_test_without_a_declaration_stops(self):
        table = declarations()
        del table["DialogUITests/testD1_showAlertOK"]
        self.assertTrue(any("without a declaration" in p for p in r.check_enumeration(enumeration(), table)))

    def test_a_declaration_without_a_test_stops(self):
        table = declarations()
        table["DialogUITests/testD99_unknown"] = []
        self.assertTrue(any("without a test" in p for p in r.check_enumeration(enumeration(), table)))

    def test_a_misspelled_category_stops(self):
        text = (TESTS_DIR / r.DECLARATIONS_FILE).read_text(encoding="utf-8").replace('["sharesheet", "clipboard"]',
                                                                                     '["sharesheet", "clipbaord"]', 1)
        with self.assertRaises(r.RunnerError):
            r.parse_declarations(text)

    def test_a_duplicated_key_stops_although_json_accepts_it(self):
        text = (TESTS_DIR / r.DECLARATIONS_FILE).read_text(encoding="utf-8").replace(
            '"DialogUITests/testD2_showConfirmDialogYes": [],',
            '"DialogUITests/testD2_showConfirmDialogYes": [],\n    "DialogUITests/testD1_showAlertOK": ["systemui"],')
        with self.assertRaises(r.RunnerError):
            r.parse_declarations(text)

    def test_a_repeated_enumeration_entry_stops(self):
        identifiers = enumeration()
        identifiers.append(identifiers[0])
        self.assertTrue(any("repeats" in p for p in r.check_enumeration(identifiers, declarations())))

    def test_a_class_not_in_ui_classes_stops(self):
        # Mutation 7 "柱 2（照合）": a new test class not written into UI_CLASSES.
        identifiers = enumeration() + [ident("ExtraUITests/testX1_new")]
        table = dict(declarations(), **{"ExtraUITests/testX1_new": []})
        self.assertTrue(any("UI_CLASSES" in p for p in r.check_enumeration(identifiers, table)))

    def test_a_declaration_below_the_class_minimum_stops(self):
        # Mutation 7 "柱 2（下限）".
        table = declarations()
        table["ShareUITests/testS2_shareTextClose"] = []
        self.assertTrue(any("below the minimum" in p for p in r.check_class_minimums(table)))
        table = declarations()
        table["NotificationPermissionUITests/testNP1_allowPermission"] = ["systemui"]
        self.assertTrue(r.check_class_minimums(table))

    def test_a_new_method_in_the_frozen_class_stops(self):
        identifiers = enumeration() + [ident("ClipboardUITests/testU22_added")]
        table = dict(declarations(), **{"ClipboardUITests/testU22_added": []})
        problems = r.check_enumeration(identifiers, table)
        self.assertTrue(any("frozen 22" in p for p in problems))
        self.assertTrue(any("below the minimum" in p for p in problems))

    def test_frozen_methods_under_another_class_stop(self):
        # `class Foo: ClipboardUITests {}` would run the 22 again under Foo.
        keys = [r.key_from_enumeration_id(i) for i in enumeration()] + \
            ["ClipboardPasteUITests/testU1_navigatesToClipboardScreenAndShowsSections"]
        self.assertTrue(any("under another class" in p for p in r.check_frozen_clipboard(keys)))


class Selection(unittest.TestCase):

    def setUp(self):
        self.ids = enumeration()
        self.table = declarations()

    def test_the_simulator_runs_everything(self):
        selected, excluded = r.select_tests(self.ids, self.table, "simulator", [])
        self.assertEqual((len(selected), excluded), (99, []))

    def test_the_device_runs_only_tests_whose_categories_are_all_allowed(self):
        # Mutation 7 "柱 1（選び方）": "all" turned into "any".
        selected, excluded = r.select_tests(self.ids, self.table, "device", ["systemui"])
        self.assertNotIn(ident("ShareUITests/testS1_shareTextCopy"), selected)
        self.assertNotIn(ident("ClipboardUITests/testU10a_namedPasteboardSurvivesBackgroundAndDiesOnExplicitRemoval"),
                         selected)
        self.assertIn(ident("NotificationUITests/testN4_showImmediateShowsForegroundBanner"), selected)
        for identifier in selected:
            self.assertLessEqual(set(self.table[r.key_from_enumeration_id(identifier)]), {"systemui"})
        self.assertEqual(len(selected) + len(excluded), 99)
        selected, _ = r.select_tests(self.ids, self.table, "device", ["clipboard"])
        self.assertNotIn(ident("ShareUITests/testS1_shareTextCopy"), selected)
        selected, _ = r.select_tests(self.ids, self.table, "device", ["clipboard", "sharesheet"])
        self.assertIn(ident("ShareUITests/testS1_shareTextCopy"), selected)

    def test_nothing_allowed_on_the_device_selects_only_undeclared_tests(self):
        selected, _ = r.select_tests(self.ids, self.table, "device", [])
        self.assertTrue(selected)
        self.assertTrue(all(self.table[r.key_from_enumeration_id(i)] == [] for i in selected))

    def test_unknown_categories_and_simulator_allowances_are_refused(self):
        with self.assertRaises(r.RunnerError):
            r.select_tests(self.ids, self.table, "device", ["systemUI"])
        with self.assertRaises(r.RunnerError):
            r.select_tests(self.ids, self.table, "simulator", ["clipboard"])

    def test_feature_keeps_its_classes_and_the_common_ones(self):
        selected, _ = r.select_tests(self.ids, self.table, "simulator", [], "Dialog")
        classes = {r.class_of(r.key_from_enumeration_id(i)) for i in selected}
        self.assertEqual(classes, {"DialogUITests", "NavigationUITests", "IdentifierInventoryUITests"})

    def test_the_simulator_names_classes_and_the_device_names_tests(self):
        selected, _ = r.select_tests(self.ids, self.table, "simulator", [])
        sim = r.build_invocations(self.ids, selected, "simulator")
        self.assertEqual([i["name"] for i in sim][:4], ["NotificationPermissionUITests/testNP2_denyPermission",
                                                         "NotificationPermissionUITests/testNP1_allowPermission",
                                                         "NavigationUITests", "IdentifierInventoryUITests"])
        self.assertTrue(all(i["uninstallBefore"] == (i["stage"] == "permission") for i in sim))
        self.assertEqual(sim[-1]["stage"], "cb2")
        dialog = next(i for i in sim if i["name"] == "DialogUITests")
        self.assertEqual(dialog["onlyTesting"], ["IosLibraryExampleUITests/DialogUITests"])
        self.assertEqual(len(dialog["expected"]), 15)
        selected, _ = r.select_tests(self.ids, self.table, "device", ["systemui", "reinstall"])
        device = r.build_invocations(self.ids, selected, "device")
        self.assertEqual(r.device_names_tests_only(device), [])
        self.assertEqual(sorted(k for i in device for k in i["expected"]),
                         sorted(r.key_from_enumeration_id(i) for i in selected))

    def test_naming_a_class_on_the_device_is_caught(self):
        # Mutation 7 "柱 1（名指し）": a class passed to -only-testing on the device.
        selected, _ = r.select_tests(self.ids, self.table, "simulator", [])
        sim = r.build_invocations(self.ids, selected, "simulator")
        problems = r.device_names_tests_only(sim)
        self.assertTrue(problems)
        self.assertIn("IosLibraryExampleUITests/DialogUITests", " ".join(problems))

    def test_an_empty_selection_never_builds_an_xcodebuild_call(self):
        # Mutation 7 "柱 1（名指し）": an empty -only-testing list runs every test.
        self.assertEqual(r.build_invocations(self.ids, [], "device"), [])
        with self.assertRaises(r.RunnerError):
            r.only_testing_arguments({"name": "DialogUITests", "onlyTesting": []})
        with self.assertRaises(r.RunnerError):
            r.only_testing_arguments({"name": "DialogUITests"})
        with self.assertRaises(r.RunnerError):
            r.only_testing_arguments({"name": "x", "onlyTesting": ["IosLibraryTests/Foo/testBar()"]})
        self.assertEqual(r.only_testing_arguments({"name": "x", "onlyTesting": [ident("DialogUITests/testD1_showAlertOK")]}),
                         ["-only-testing:IosLibraryExampleUITests/DialogUITests/testD1_showAlertOK()"])

    def test_the_permission_and_cb2_stages_follow_the_feature(self):
        selected, _ = r.select_tests(self.ids, self.table, "simulator", [], "Dialog")
        stages = {i["stage"] for i in r.build_invocations(self.ids, selected, "simulator", "Dialog")}
        self.assertEqual(stages, {"ui"})
        selected, _ = r.select_tests(self.ids, self.table, "simulator", [], "Clipboard")
        stages = [i["stage"] for i in r.build_invocations(self.ids, selected, "simulator", "Clipboard")]
        self.assertEqual(stages[-1], "cb2")
        self.assertNotIn("permission", stages)

    def test_the_device_permission_stage_needs_reinstall(self):
        selected, _ = r.select_tests(self.ids, self.table, "device", ["systemui"])
        self.assertNotIn("permission", {i["stage"] for i in r.build_invocations(self.ids, selected, "device")})


class Plan(unittest.TestCase):

    def plan(self, allowed=("systemui",), changes=()):
        return r.make_plan("device", FAKE_DEVICE, SIMULATOR, enumeration(), declarations(), list(allowed), None, HEAD,
                           "folderhash", list(changes), False)

    def test_the_approval_of_the_same_plan_matches(self):
        plan = self.plan()
        approval = r.make_approval(plan)
        self.assertRegex(approval["approvalId"], r"^[0-9a-f]{32}$")
        self.assertNotEqual(approval["approvalId"], r.make_approval(plan)["approvalId"])
        self.assertEqual(r.approval_problems(approval, plan), [])

    def test_a_test_removed_from_the_approval_is_refused(self):
        # Mutation 7 "柱 3（利用者の許可）".
        plan = self.plan()
        approval = r.make_approval(plan)
        approval["tests"].pop()
        self.assertTrue(r.approval_problems(approval, plan))

    def test_a_test_added_to_the_approval_is_refused(self):
        plan = self.plan()
        approval = r.make_approval(plan)
        approval["tests"].append({"id": ident("ShareUITests/testS1_shareTextCopy"), "categories": []})
        self.assertTrue(r.approval_problems(approval, plan))

    def test_another_device_allow_is_refused(self):
        approval = r.make_approval(self.plan(("systemui",)))
        self.assertTrue(any("deviceAllow" in p for p in r.approval_problems(approval, self.plan(("systemui", "files")))))

    def test_another_commit_folder_or_device_is_refused(self):
        plan = self.plan()
        for field, value in (("head", "0" * 40), ("testsFolderHash", "other"), ("udid", SIMULATOR), ("feature", "Dialog")):
            approval = r.make_approval(plan)
            approval[field] = value
            with self.subTest(field=field):
                self.assertTrue(r.approval_problems(approval, plan))

    def test_a_malformed_approval_id_is_refused(self):
        plan = self.plan()
        approval = r.make_approval(plan, approval_id="1234")
        self.assertTrue(any("approval ID" in p for p in r.approval_problems(approval, plan)))

    def test_a_changed_trusted_part_cannot_be_approved(self):
        # Mutation 7 "信頼する部分".
        plan = self.plan(changes=[("Support/SampleApp.swift", "pinned", "actual")])
        approval = r.make_approval(plan)
        self.assertFalse(approval["trustedPart"]["unchanged"])
        self.assertTrue(any("trusted part" in p for p in r.approval_problems(approval, plan)))

    def test_approvals_are_for_the_device(self):
        plan = r.make_plan("simulator", SIMULATOR, SIMULATOR, enumeration(), declarations(), [], None, HEAD, "h", [], True)
        with self.assertRaises(r.RunnerError):
            r.make_approval(plan)


class Ledger(unittest.TestCase):

    def test_an_approval_id_is_used_once(self):
        # Mutation 7 "柱 3": the same --approved file a second time.
        with tempfile.TemporaryDirectory() as directory:
            ledger = pathlib.Path(directory) / "sub" / "approvals.log"
            r.consume_approval(ledger, "a" * 32, FAKE_DEVICE)
            with self.assertRaises(r.RunnerError):
                r.consume_approval(ledger, "a" * 32, FAKE_DEVICE)
            r.consume_approval(ledger, "b" * 32, FAKE_DEVICE)
            self.assertEqual(len(ledger.read_text().splitlines()), 2)
            with self.assertRaises(r.RunnerError):
                r.consume_approval(ledger, "not-an-id", FAKE_DEVICE)

    def test_the_approve_command_consumes_and_then_refuses(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = make_repo(pathlib.Path(directory))
            plan_path, approval_path, _ = write_device_plan(repo)
            first = cli("approve", *approve_args(repo, plan_path, approval_path))
            second = cli("approve", *approve_args(repo, plan_path, approval_path))
            self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
            self.assertEqual(second.returncode, 1)
            self.assertIn("already used", second.stderr)

    def test_a_broken_ledger_line_refuses_the_device(self):
        # Review R-7: a line cut off by a crash must not read as "this ID is unused".
        with tempfile.TemporaryDirectory() as directory:
            ledger = pathlib.Path(directory) / "approvals.log"
            r.consume_approval(ledger, "a" * 32, FAKE_DEVICE)
            for broken in ("a" * 32 + "\t2026-10-24T00:00:00+00:00\t" + FAKE_DEVICE + "\nbbbb",
                           "a" * 31 + "\t2026-10-24T00:00:00+00:00\t" + FAKE_DEVICE + "\n",
                           "a" * 32 + " 2026-10-24T00:00:00+00:00 " + FAKE_DEVICE + "\n", "\n",
                           "a" * 32 + "\t2026-10-24T00:00:00+00:00\t" + FAKE_DEVICE):
                with self.subTest(broken=broken):
                    ledger.write_text(broken)
                    with self.assertRaises(r.RunnerError):
                        r.consume_approval(ledger, "c" * 32, FAKE_DEVICE)
                    self.assertEqual(ledger.read_text(), broken)
            ledger.unlink()
            (pathlib.Path(directory) / "elsewhere").write_text("")
            ledger.symlink_to(pathlib.Path(directory) / "elsewhere")
            with self.assertRaises(r.RunnerError):
                r.consume_approval(ledger, "c" * 32, FAKE_DEVICE)

    def test_the_ledger_is_rewritten_whole_and_leaves_no_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = pathlib.Path(directory) / "approvals.log"
            r.consume_approval(ledger, "a" * 32, FAKE_DEVICE, now="2026-10-24T00:00:00+00:00")
            r.consume_approval(ledger, "b" * 32, FAKE_DEVICE, now="2026-10-24T00:00:01+00:00")
            self.assertEqual(r.ledger_ids(ledger.read_text()), ["a" * 32, "b" * 32])
            self.assertEqual(sorted(p.name for p in pathlib.Path(directory).iterdir()),
                             ["approvals.log", "approvals.log.lock"])

    def test_the_ledger_place_cannot_be_moved_from_outside(self):
        # Review R-6: neither an environment variable nor $HOME moves the ledger, and test_ios.sh
        # never passes the self-tests' path.
        import inspect
        self.assertNotIn("environ", inspect.getsource(r.cmd_approve))
        self.assertNotIn("environ", inspect.getsource(r.consume_approval))
        printed = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); "
                                  "import ios_ui_runner as r; print(r.DEFAULT_LEDGER)", str(ROOT / "scripts")],
                                 capture_output=True, text=True, env=dict(os.environ, HOME="/tmp/elsewhere",
                                                                         NTK_TEST_IOS_APPROVAL_LEDGER="/dev/null"))
        self.assertEqual(printed.stdout.strip(), str(r.DEFAULT_LEDGER))
        self.assertFalse(printed.stdout.startswith("/tmp/elsewhere"))
        self.assertNotIn("ledger-for-self-test", SCRIPT.read_text(encoding="utf-8"))
        self.assertNotIn("NTK_TEST_IOS_APPROVAL_LEDGER", SCRIPT.read_text(encoding="utf-8"))


class BinaryInventory(unittest.TestCase):

    def keys(self, name):
        return r.binary_test_keys(r.parse_otool_classes(fixture(f"otool-ov-{name}.txt"), fixture(f"otool-l-{name}.txt")))

    def test_the_device_build_has_exactly_the_enumerated_tests(self):
        keys = self.keys("device")
        self.assertEqual(len(keys), 99)
        self.assertEqual(r.binary_inventory_problems(keys, enumeration()), [])

    def test_throwing_tests_are_read_through_and_return_error(self):
        # Mutation 7 "柱 2（実機のバイナリ）": not stripping `AndReturnError:`. Every test of the
        # tree throws, so none would match.
        self.assertEqual(r.normalize_test_selector("testD1_showAlertOKAndReturnError:"), "testD1_showAlertOK")
        self.assertEqual(r.normalize_test_selector("testPlain"), "testPlain")
        for not_a_test in ("setUpAfterGateAndReturnError:", "testWith:arg:", "testSession:", "helper:"):
            self.assertIsNone(r.normalize_test_selector(not_a_test), not_a_test)
        classes = r.parse_otool_classes(fixture("otool-ov-device.txt"), fixture("otool-l-device.txt"))
        selectors = [s for c in classes.values() for s in c["selectors"] if s.startswith("testD1_")]
        self.assertEqual(selectors, ["testD1_showAlertOKAndReturnError:"])

    def test_plain_main_actor_and_inherited_tests_of_the_probe(self):
        self.assertEqual(sorted(self.keys("probe")), sorted([
            "ProbeBase/testInheritedPlain", "ProbeChild/testInheritedPlain", "ProbeChild/testPlain",
            "ProbeChild/testThrows", "ProbeChild/testMainActorPlain", "ProbeChild/testMainActorThrows"]))

    def test_ivars_named_test_are_not_tests(self):
        # The base class has an ivar `testSession`; only method lists hold tests.
        self.assertFalse(any(k.endswith("/testSession") for k in self.keys("device")))

    def test_a_test_only_in_the_device_build_stops(self):
        # Mutation 7 "柱 2（閉じた形の規則と実機のバイナリ）": a `#if !targetEnvironment(simulator)` test.
        identifiers = [i for i in enumeration() if "testD1_" not in i]
        problems = r.binary_inventory_problems(self.keys("device"), identifiers)
        self.assertTrue(problems)
        self.assertIn("DialogUITests/testD1_showAlertOK", problems[0])
        problems = r.binary_inventory_problems([k for k in self.keys("device") if "testD2_" not in k], enumeration())
        self.assertIn("only in the enumeration ['DialogUITests/testD2_showConfirmDialogYes']", problems[0])


class Results(unittest.TestCase):

    def invocation(self, expected):
        return {"name": "DialogUITests", "stage": "ui", "timeout": 1800, "onlyTesting": ["x"], "expected": expected}

    def dialog_keys(self):
        return [r.key_from_enumeration_id(i) for i in enumeration() if "/DialogUITests/" in i]

    def test_the_dialog_run_matches_its_names(self):
        records, stop = r.record_invocation(self.invocation(self.dialog_keys()), fixture("xcresult-dialog-tests.json"),
                                            fixture("xcresult-dialog-summary.json"), 0, False, SIMULATOR)
        self.assertFalse(stop)
        self.assertEqual(len(records), 15)
        self.assertTrue(all(rec["result"] == "passed" for rec in records))
        self.assertEqual(records[0]["test"].split("/")[0], "IosLibraryExampleUITests")

    def test_a_name_that_does_not_exist_is_caught(self):
        # xcodebuild ignores the unknown name and exits 0 (0a section 8); the comparison catches it.
        expected = ["DialogUITests/testD1_showAlertOK", "DialogUITests/testNope_doesNotExist"]
        records, stop = r.record_invocation(self.invocation(expected), fixture("xcresult-d1-tests.json"),
                                            fixture("xcresult-d1-summary.json"), 0, False, SIMULATOR)
        self.assertTrue(stop)
        self.assertTrue(any(rec["test"].endswith("#namedSet") and "testNope" in rec["message"] for rec in records))

    def _with_cases(self, mutate):
        data = json.loads(fixture("xcresult-dialog-tests.json"))
        suite = data["testNodes"][0]["children"][0]["children"][0]
        mutate(suite["children"])
        return json.dumps(data)

    def _summary(self, total, passed):
        data = json.loads(fixture("xcresult-dialog-summary.json"))
        data["totalTestCount"], data["passedTests"] = total, passed
        return json.dumps(data)

    def test_an_extra_result_is_caught(self):
        extra = {"name": "testZ_extra()", "nodeIdentifier": "DialogUITests/testZ_extra()", "nodeType": "Test Case",
                 "result": "Passed"}
        text = self._with_cases(lambda cases: cases.append(extra))
        records, stop = r.record_invocation(self.invocation(self.dialog_keys()), text, self._summary(16, 16), 0, False,
                                            SIMULATOR)
        self.assertTrue(stop)
        self.assertTrue(any("not named" in rec["message"] for rec in records if rec["test"].endswith("#namedSet")))

    def test_a_duplicated_result_is_caught(self):
        # Mutation 7 "結果の読み方": the same test twice in the results array.
        text = self._with_cases(lambda cases: cases.append(dict(cases[0])))
        records, stop = r.record_invocation(self.invocation(self.dialog_keys()), text, self._summary(16, 16), 0, False,
                                            SIMULATOR)
        self.assertTrue(stop)
        self.assertTrue(any("repeat" in rec["message"] for rec in records if rec["test"].endswith("#namedSet")))
        self.assertTrue(r.ran_exactly_problems(["A/testA", "A/testA"], ["A/testA"]))
        self.assertTrue(r.ran_exactly_problems(["A/testA"], ["A/testA", "A/testA"]))

    def test_a_missing_result_is_caught(self):
        text = self._with_cases(lambda cases: cases.pop())
        records, stop = r.record_invocation(self.invocation(self.dialog_keys()), text, self._summary(14, 14), 0, False,
                                            SIMULATOR)
        self.assertTrue(stop)

    def test_another_destination_is_caught(self):
        records, _ = r.record_invocation(self.invocation(self.dialog_keys()), fixture("xcresult-dialog-tests.json"),
                                         fixture("xcresult-dialog-summary.json"), 0, False, FAKE_DEVICE)
        self.assertTrue(any(rec["test"].endswith("#destination") for rec in records))

    def test_a_summary_that_disagrees_is_caught(self):
        records, _ = r.record_invocation(self.invocation(self.dialog_keys()), fixture("xcresult-dialog-tests.json"),
                                         self._summary(16, 15), 0, False, SIMULATOR)
        self.assertTrue(any(rec["test"].endswith("#summary") for rec in records))

    def test_no_result_bundle_or_a_timeout_fails_the_class(self):
        records, stop = r.record_invocation(self.invocation(self.dialog_keys()), None, None, 65, True, SIMULATOR)
        self.assertTrue(stop)
        self.assertEqual({rec["test"].split("#")[1] for rec in records}, {"timeout", "noResult"})

    def test_a_zero_exit_code_with_a_failed_test_is_still_a_failure(self):
        text = self._with_cases(lambda cases: cases[0].update(result="Failed"))
        summary = json.loads(fixture("xcresult-dialog-summary.json"))
        summary["passedTests"], summary["failedTests"] = 14, 1
        records, _ = r.record_invocation(self.invocation(self.dialog_keys()), text, json.dumps(summary), 0, False,
                                         SIMULATOR)
        self.assertEqual([rec["result"] for rec in records].count("failed"), 1)

    def test_unit_results_keep_their_target(self):
        records = r.unit_records("IosLibraryExampleTests", fixture("xcresult-unit-example-tests.json"), 0)
        self.assertEqual(len(records), 10)
        self.assertIn("IosLibraryExampleTests/IosLibraryExampleTests/example", [rec["test"] for rec in records])
        self.assertTrue(r.unit_records("IosLibraryTests", fixture("xcresult-unit-example-tests.json"), 0)[0]["test"]
                        .endswith("#zeroTests"))


class Classification(unittest.TestCase):

    U10B = "ClipboardUITests/testU10b_namedPasteboardAfterProcessTermination"

    def test_expected_failure_is_a_failure(self):
        self.assertEqual(r.classify("DialogUITests/testD1_showAlertOK", "Expected Failure", None)[0], "failed")

    def test_gated_and_precondition_skips_are_failures(self):
        self.assertEqual(r.classify("DialogUITests/testD12_loginReportsCredentials", "Skipped", "NTK-GATED:credentials")[0],
                         "failed")
        self.assertEqual(r.classify("NotificationUITests/testN4_showImmediateShowsForegroundBanner", "Skipped",
                                    "NTK-PRECONDITION:notDetermined")[0], "failed")

    def test_only_listed_skips_with_their_reason_are_skips(self):
        # Mutation 7 "結果の読み方": an XCTSkip added to D1.
        reason = "M-08 could not be decided here: after a preflight-verified fresh create, ..."
        self.assertEqual(r.classify(self.U10B, "Skipped", reason)[0], "skipped")
        self.assertEqual(r.classify("DialogUITests/testD1_showAlertOK", "Skipped", reason)[0], "failed")
        self.assertEqual(r.classify(self.U10B, "Skipped", "something else")[0], "failed")
        self.assertEqual(r.classify(self.U10B, "Skipped", "NTK-GATED:clipboard " + reason)[0], "failed")
        self.assertEqual(r.classify(self.U10B, "Weird", reason)[0], "failed")

    def test_a_skip_reason_is_read_from_the_failure_message(self):
        data = json.loads(fixture("xcresult-d1-tests.json"))
        case = data["testNodes"][0]["children"][0]["children"][0]["children"][0]
        case["result"] = "Skipped"
        case["children"] = [{"name": "Test skipped - NTK-GATED:probe", "nodeType": "Failure Message"}]
        cases, _ = r.parse_xcresult_tests(json.dumps(data))
        self.assertEqual(cases[0]["skipReason"], "NTK-GATED:probe")


class Baseline(unittest.TestCase):

    def test_lost_coverage_inside_the_run_fails_and_outside_is_reported(self):
        base = {"T/A/testA": "passed", "T/A/testB": "passed", "T/A/testC": "passed", "T/B/testX": "passed",
                "T/A/testD": "failed"}
        current = {"T/A/testA": "passed", "T/A/testB": "skipped", "T/A/testD": "passed", "T/A/testE": "passed"}
        lines, lost = r.compare_with_baseline(current, base, in_scope={"T/A/testA", "T/A/testB", "T/A/testC", "T/A/testD"})
        self.assertEqual(lost, ["T/A/testB", "T/A/testC"])
        self.assertIn("outside this run=1", lines[0])
        self.assertTrue(any("ADDED T/A/testE" in line for line in lines))
        self.assertTrue(any("CHANGED T/A/testD: failed -> passed" in line for line in lines))

    def test_the_scope_of_a_run(self):
        ids = enumeration()
        plan = r.make_plan("simulator", SIMULATOR, SIMULATOR, ids, declarations(), [], "Dialog", HEAD, "h", [], False)
        self.assertTrue(r.in_run_scope("IosLibraryExampleUITests/DialogUITests/testD16_deletedSince", plan))
        self.assertTrue(r.in_run_scope("IosLibraryExampleUITests/IdentifierInventoryUITests/testI1a_dialogIdentifiers", plan))
        self.assertFalse(r.in_run_scope("IosLibraryExampleUITests/ShareUITests/testS1_shareTextCopy", plan))
        self.assertFalse(r.in_run_scope("IosLibraryExampleUITests/GoneUITests/testG1_x", plan))
        self.assertFalse(r.in_run_scope("IosLibraryTests/Foo/bar", plan))
        full = r.make_plan("simulator", SIMULATOR, SIMULATOR, ids, declarations(), [], None, HEAD, "h", [], True)
        self.assertTrue(r.in_run_scope("IosLibraryExampleUITests/GoneUITests/testG1_x", full))
        self.assertTrue(r.in_run_scope("IosLibraryTests/Foo/bar", full))
        device = r.make_plan("device", FAKE_DEVICE, SIMULATOR, ids, declarations(), ["systemui"], None, HEAD, "h", [], False)
        self.assertFalse(r.in_run_scope("IosLibraryExampleUITests/ShareUITests/testS1_shareTextCopy", device))
        self.assertTrue(r.in_run_scope("IosLibraryExampleUITests/NotificationUITests/testN4_showImmediateShowsForegroundBanner",
                                       device))

    def test_the_baseline_is_refused_outside_a_full_run_and_the_two_environments(self):
        plan = {"feature": None, "kind": "simulator", "unitTests": True, "deviceAllow": []}
        env = {"model": "iPhone 17", "os": "26.2"}
        self.assertIsNone(r.baseline_refusal(env, plan, False, "Xcode 26.3"))
        self.assertTrue(r.baseline_refusal(env, dict(plan, feature="Dialog"), False, ""))
        self.assertTrue(r.baseline_refusal(env, dict(plan, unitTests=False), False, ""))
        self.assertTrue(r.baseline_refusal({"model": "iPhone 16", "os": "18.3.1"}, plan, False, ""))
        self.assertTrue(r.baseline_refusal(env, plan, True, ""))
        self.assertIsNone(r.baseline_refusal({"model": "iPhone XS", "os": "18.7.2"},
                                             dict(plan, kind="device", unitTests=False), False, ""))

    def test_counts_are_per_target_and_feature(self):
        counts = r.baseline_counts({"IosLibraryExampleUITests/DialogUITests/testD1_showAlertOK": "passed",
                                    "IosLibraryExampleUITests/ClipboardUITests/testU21_x": "skipped",
                                    "IosLibraryTests/Foo/bar": "passed"})
        self.assertEqual(counts, {"IosLibraryExampleUITests": {"Dialog": {"passed": 1}, "Clipboard": {"skipped": 1}},
                                  "IosLibraryTests": {"passed": 1}})


class Coverage(unittest.TestCase):

    def buttons(self):
        return r.expected_buttons({"dialog": (SAMPLE_DIR / "DialogSampleView.swift").read_text(encoding="utf-8"),
                                   "notification": (SAMPLE_DIR / "NotificationSampleView.swift").read_text(encoding="utf-8"),
                                   "share": (SAMPLE_DIR / "ShareSampleView.swift").read_text(encoding="utf-8")})

    def test_the_sample_has_45_buttons(self):
        buttons = self.buttons()
        self.assertEqual(len(buttons), 45)
        self.assertIn("dialog.button.showAlert", buttons)
        self.assertIn("notification.button.setBadgeCount0", buttons)

    def test_one_attachment_per_test_and_every_button(self):
        manifest = (FIXTURES / "attachments-d1" / "manifest.json").read_text(encoding="utf-8")
        directory = FIXTURES / "attachments-d1"
        key = "DialogUITests/testD1_showAlertOK"
        self.assertEqual(r.coverage_problems(manifest, directory, [key], ["dialog.button.showAlert"]), [])
        problems = r.coverage_problems(manifest, directory, [key, "DialogUITests/testD2_showConfirmDialogYes"],
                                       ["dialog.button.showAlert", "dialog.button.showConfirmDialog"])
        self.assertTrue(any("testD2" in p and "0 button coverage" in p for p in problems))
        self.assertTrue(any("showConfirmDialog" in p for p in problems))

    def test_two_attachments_or_broken_json_fail(self):
        # Mutation 7 "全ボタン": two attachments in one test; a broken JSON.
        with tempfile.TemporaryDirectory() as d:
            directory = pathlib.Path(d)
            manifest = json.loads((FIXTURES / "attachments-d1" / "manifest.json").read_text(encoding="utf-8"))
            attachment = manifest[0]["attachments"][0]
            (directory / attachment["exportedFileName"]).write_text('["dialog.button.showAlert"]')
            (directory / "broken.json").write_text('["dialog.button.showAlert"')
            two = json.loads(json.dumps(manifest))
            two[0]["attachments"].append(dict(attachment))
            key = "DialogUITests/testD1_showAlertOK"
            self.assertTrue(r.coverage_problems(json.dumps(two), directory, [key], []))
            broken = json.loads(json.dumps(manifest))
            broken[0]["attachments"][0]["exportedFileName"] = "broken.json"
            self.assertTrue(any("not JSON" in p for p in r.coverage_problems(json.dumps(broken), directory, [key], [])))


def copy_tests():
    directory = tempfile.mkdtemp()
    target = pathlib.Path(directory) / "IosLibraryExampleUITests"
    shutil.copytree(TESTS_DIR, target, ignore=shutil.ignore_patterns(".DS_Store"))
    return pathlib.Path(directory), target


class SourceRules(unittest.TestCase):
    """The closed rules of 6.1, broken one at a time in a copy of the test folder."""

    def setUp(self):
        self.temp, self.tests = copy_tests()
        self.pbxproj = PBXPROJ.read_text(encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.temp)

    def problems(self, pbxproj=None):
        return r.check_test_folder(self.tests, self.pbxproj if pbxproj is None else pbxproj)

    def add(self, name, body):
        (self.tests / name).write_text("import XCTest\nimport Foundation\n\n" + body + "\n", encoding="utf-8")

    def edit(self, name, old, new):
        path = self.tests / name
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def assertCaught(self, fragment=None):
        problems = self.problems()
        self.assertTrue(problems, "the mutation was not caught")
        if fragment:
            self.assertTrue(any(fragment in p for p in problems), problems)

    def test_the_real_tree_passes(self):
        self.assertEqual(r.check_test_folder(TESTS_DIR, self.pbxproj), [])
        self.assertEqual(r.frozen_file_problems(TESTS_DIR), [])
        self.assertEqual(r.trusted_part_changes(TESTS_DIR), [])

    def test_a_class_that_is_not_final_is_caught(self):
        self.add("ExtraUITests.swift", "class ExtraUITests: SampleUITestCase {\n    func testX1_a() throws {}\n}")
        self.assertCaught("final class")

    def test_a_class_on_another_base_is_caught(self):
        for base in ("ClipboardUITests", "XCTestCase", "SampleUITestCase, Sendable"):
            with self.subTest(base=base):
                self.add("ExtraUITests.swift", f"final class ExtraUITests: {base} {{\n}}")
                self.assertCaught("final class")

    def test_an_extension_of_a_test_class_is_caught(self):
        self.add("ExtraUITests.swift", "extension ClipboardUITests {\n    func testU99_more() throws {}\n}")
        self.assertCaught("extension")

    def test_an_extra_override_is_caught(self):
        # Mutation 7 "柱 2（閉じた形の規則）": class func setUp, tearDown, invokeTest, the async forms.
        for member in ("override class func setUp() {}", "override func tearDown() {}", "override func invokeTest() {}",
                       "override func setUp() async throws {}", "override func setUpAfterGate() async throws {}",
                       "static override func setUpAfterGate() {}", "override var name: String { \"x\" }"):
            with self.subTest(member=member):
                self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                          f"    {member}\n\n    override func setUpAfterGate() throws {{")
                self.assertCaught()
                shutil.copy(TESTS_DIR / "DialogUITests.swift", self.tests / "DialogUITests.swift")

    def test_class_members_are_caught_and_static_functions_pass(self):
        self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                  "    class func helper() {}\n\n    override func setUpAfterGate() throws {")
        self.assertCaught("class func")
        shutil.copy(TESTS_DIR / "DialogUITests.swift", self.tests / "DialogUITests.swift")
        self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                  "    static func helper() -> Int { 1 }\n\n    override func setUpAfterGate() throws {")
        self.assertEqual(self.problems(), [])

    def test_conditional_compilation_is_caught(self):
        # Mutation 7: a test inside `#if !targetEnvironment(simulator)`.
        self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                  "    #if !targetEnvironment(simulator)\n    func testD99_deviceOnly() throws {}\n    #endif\n\n"
                  "    override func setUpAfterGate() throws {")
        self.assertCaught("#if")

    def test_a_second_conditional_in_the_base_is_caught(self):
        self.edit("Support/SampleUITestCase.swift", "    // MARK: Hooks for test classes",
                  "    #if DEBUG\n    #endif\n    // MARK: Hooks for test classes")
        self.assertCaught("#if")

    def test_test_method_shapes(self):
        for shape in ("func testD99_x() async throws {}", "func testD99_x() async {}", "func testD99_x() -> Int { 1 }",
                      "private func testD99_x() throws {}", "@objc func testD99_x() throws {}",
                      "func testD99_x(_ value: Int) throws {}", "func testD99_x() rethrows {}"):
            with self.subTest(shape=shape):
                self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                          f"    {shape}\n\n    override func setUpAfterGate() throws {{")
                self.assertCaught()
                shutil.copy(TESTS_DIR / "DialogUITests.swift", self.tests / "DialogUITests.swift")
        self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                  "    @MainActor\n    func testD99_x() {}\n\n    override func setUpAfterGate() throws {")
        self.assertEqual(self.problems(), [])

    def test_dangerous_names_outside_support_are_caught(self):
        # Mutation 7 "柱 2（閉じた形の規則）": springboard, home, pasteboard, monitor written directly.
        for line in ('let s = XCUIApplication(bundleIdentifier: "com.apple.springboard")',
                     "XCUIDevice.shared.press(.home)", "_ = UIPasteboard.general",
                     '_ = addUIInterruptionMonitor(withDescription: "x") { _ in true }',
                     'let s = "\\(XCUIApplication().label)"', "let s = `XCUIApplication`()"):
            with self.subTest(line=line):
                self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                          f"    override func setUpAfterGate() throws {{\n        {line}")
                self.assertCaught("allowed only in")
                shutil.copy(TESTS_DIR / "DialogUITests.swift", self.tests / "DialogUITests.swift")

    def test_names_in_comments_and_plain_strings_are_not_code(self):
        self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                  '    // XCUIApplication, #if, override func tearDown()\n    /* XCUIDevice /* nested */ */\n'
                  '    private let note = "XCUIApplication #if override"\n'
                  "    override func setUpAfterGate() throws {")
        self.assertEqual(self.problems(), [])

    def test_a_second_home_press_in_the_frozen_file_is_caught(self):
        self.edit("IosLibraryExampleUITests.swift", "        XCUIDevice.shared.press(.home)",
                  "        XCUIDevice.shared.press(.home)\n        XCUIDevice.shared.press(.home)")
        self.assertCaught("XCUIDevice appears 2 times")
        self.assertTrue(r.frozen_file_problems(self.tests))

    def test_expect_failure_is_caught(self):
        self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                  "    override func setUpAfterGate() throws {\n        XCTExpectFailure(\"x\")")
        self.assertCaught("XCTExpectFailure")

    def test_identifier_strings_outside_the_trusted_part_are_caught(self):
        for literal in ('"share.button.shareText"', '"menu.dialog"', '"notification.lastEvent.\\(field)"'):
            with self.subTest(literal=literal):
                self.edit("DialogUITests.swift", "    override func setUpAfterGate() throws {",
                          f"    override func setUpAfterGate() throws {{\n        _ = {literal}")
                self.assertCaught("identifier string")
                shutil.copy(TESTS_DIR / "DialogUITests.swift", self.tests / "DialogUITests.swift")

    def test_identifier_strings_of_the_frozen_file_only_inside_clipboard_id(self):
        self.edit("IosLibraryExampleUITests.swift", "private enum ScrollDirection {",
                  'private let stray = "clipboard.result"\n\nprivate enum ScrollDirection {')
        self.assertCaught("identifier string")

    def test_imports_are_caught(self):
        for module in ("Testing", "UIKit", "struct Testing.Test"):
            with self.subTest(module=module):
                self.edit("DialogUITests.swift", "import Foundation", f"import Foundation\nimport {module}")
                self.assertCaught("import")
                shutil.copy(TESTS_DIR / "DialogUITests.swift", self.tests / "DialogUITests.swift")
        self.edit("DialogUITests.swift", "import Foundation", "import Foundation\n@testable import IosLibrary")
        self.assertCaught("@testable")

    def test_load_time_code_and_other_files_are_caught(self):
        self.add("Load.swift", 'let key = "NSPrincipalClass"')
        self.assertCaught("NSPrincipalClass")
        (self.tests / "Load.swift").unlink()
        (self.tests / "Load.m").write_text("+ (void)load {}\n")
        self.assertCaught("only .swift files")
        (self.tests / "Load.m").unlink()
        self.add("Observer.swift", "enum Observer {\n    static let c = XCTestObservationCenter.shared\n}")
        self.assertCaught("XCTestObservationCenter")

    def test_the_pbxproj_cannot_switch_the_info_plist(self):
        self.assertTrue(self.problems(self.pbxproj.replace("TEST_TARGET_NAME = IosLibraryExample;",
                                                           "TEST_TARGET_NAME = IosLibraryExample;\n\t\t\t\tINFOPLIST_KEY_NSPrincipalClass = Foo;")))
        self.assertTrue(self.problems(self.pbxproj.replace("TEST_TARGET_NAME = IosLibraryExample;",
                                                           "TEST_TARGET_NAME = IosLibraryExample;\n\t\t\t\tINFOPLIST_FILE = x.plist;")))

    def test_a_helper_outside_the_trusted_list_follows_the_test_rules(self):
        self.add("Support/Helper.swift", "final class Helper {\n    let app = XCUIApplication()\n}")
        problems = self.problems()
        self.assertTrue(any("Helper" in p and "final class" in p for p in problems), problems)
        self.assertTrue(any("allowed only in" in p for p in problems), problems)

    def test_a_trusted_file_that_changes_is_reported(self):
        # Mutation 7 "信頼する部分": a function that presses share.button.* without a token.
        self.edit("Support/SampleApp.swift", "struct SampleApp {",
                  'struct SampleApp {\n\n    func pressShareWithoutToken() { app.buttons["share.button.shareText"].tap() }')
        changes = r.trusted_part_changes(self.tests)
        self.assertEqual([c[0] for c in changes], ["Support/SampleApp.swift"])
        self.assertEqual(self.problems(), [])  # the rules still pass: only the hash catches it

    def test_the_frozen_file_one_line_changed(self):
        # Mutation 7 "柱 2（固定）".
        self.edit("IosLibraryExampleUITests.swift", "openClipboardScreen()", "openClipboardScreen() ")
        self.assertTrue(r.frozen_file_problems(self.tests))

    def test_the_bundled_declarations_must_match_the_source(self):
        # Mutation 7 "柱 2（写し）".
        source = self.tests / r.DECLARATIONS_FILE
        copy = self.temp / "bundle.json"
        shutil.copy(source, copy)
        self.assertEqual(r.bundle_declaration_problems(source, [copy]), [])
        copy.write_text(copy.read_text().replace('testD1_showAlertOK": []', 'testD1_showAlertOK": ["systemui"]'))
        self.assertTrue(r.bundle_declaration_problems(source, [copy]))
        self.assertTrue(r.bundle_declaration_problems(source, []))

    def test_the_folder_hash_follows_every_file(self):
        before = r.tests_folder_hash(self.tests)
        self.edit("DialogUITests.swift", "import XCTest", "import XCTest ")
        self.assertNotEqual(before, r.tests_folder_hash(self.tests))


class ShellGuards(unittest.TestCase):
    """The device guards of test_ios.sh, sourced with NTK_TEST_IOS_SOURCE_ONLY=1 and a fake
    xcodebuild that only records that it was called."""

    def run_bash(self, body):
        with tempfile.TemporaryDirectory() as d:
            directory = pathlib.Path(d)
            (directory / "bin").mkdir()
            fake = directory / "bin" / "xcodebuild"
            fake.write_text('#!/bin/bash\necho "called ALLOW=${TEST_RUNNER_NTK_DEVICE_ALLOW:-}" >> "$FAKE_LOG"\n')
            fake.chmod(0o755)
            # A fake xcrun too, so that no test here can reach the real devicectl (review v2, C).
            xcrun = directory / "bin" / "xcrun"
            xcrun.write_text('#!/bin/bash\necho "xcrun $*" >> "$FAKE_LOG"\nexit 99\n')
            xcrun.chmod(0o755)
            env = dict(os.environ, PATH=f"{directory / 'bin'}:{os.environ['PATH']}", FAKE_LOG=str(directory / "log"),
                       NTK_TEST_IOS_SOURCE_ONLY="1", TMPDIR=str(directory))
            script = f'source "{SCRIPT}"\n{body}\n'
            finished = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env, timeout=60)
            log = (directory / "log").read_text() if (directory / "log").exists() else ""
            leftovers = sorted(p.name for p in directory.glob("test_ios-device.*"))
            return finished, log, leftovers

    def test_no_device_xcodebuild_before_the_approval_and_the_trap(self):
        # The gate is made to pass here, so only the approval and trap flags can refuse.
        passing_gate = "set +e\nrunner() { return 0; }\n"
        finished, log, _ = self.run_bash(passing_gate + "device_xcodebuild 10 -version; echo \"code=$?\"")
        self.assertIn("code=97", finished.stdout)
        self.assertEqual(log, "")
        finished, log, _ = self.run_bash(passing_gate + "setup_device_tmp\ndevice_xcodebuild 10 -version; echo \"code=$?\"")
        self.assertIn("code=97", finished.stdout)
        self.assertEqual(log, "")
        finished, log, _ = self.run_bash(passing_gate + "APPROVAL_CONSUMED=1\ndevice_xcodebuild 10 -version; "
                                         "echo \"code=$?\"\ndevice_devicectl device list; echo \"code=$?\"")
        self.assertEqual(finished.stdout.count("code=97"), 2)
        self.assertEqual(log, "")
        # The gate (runner device-gate) is replaced: it passes here and refuses below.
        finished, log, _ = self.run_bash(
            "set +e\nrunner() { return 0; }\nAPPROVAL_CONSUMED=1\nDEVICE_ALLOW=systemui,files\nsetup_device_tmp\n"
            "device_xcodebuild 10 -version")
        self.assertEqual(log, "called ALLOW=systemui,files\n")
        finished, log, _ = self.run_bash(
            "set +e\nrunner() { return 1; }\nAPPROVAL_CONSUMED=1\nsetup_device_tmp\ndevice_xcodebuild 10 -version; "
            "echo \"code=$?\"\ndevice_devicectl device info details; echo \"code=$?\"")
        self.assertEqual(finished.stdout.count("code=97"), 2)
        self.assertEqual(log, "")

    def test_the_gate_is_asked_before_every_device_call(self):
        finished, log, _ = self.run_bash(
            "set +e\nrunner() { echo \"gate $*\" >> \"$FAKE_LOG\"; return 0; }\nAPPROVAL_CONSUMED=1\nsetup_device_tmp\n"
            "device_devicectl device info details\ndevice_xcodebuild 10 -version")
        lines = log.splitlines()
        self.assertEqual([line.split(" ")[0] for line in lines], ["gate", "xcrun", "gate", "called"])
        self.assertTrue(lines[0].startswith("gate device-gate --plan "))

    def test_source_only_works_only_when_sourced(self):
        # Review v2, C: a value left in the environment must not turn a run into a silent exit 0.
        finished = subprocess.run(["bash", str(SCRIPT), "--udid", SIMULATOR], capture_output=True, text=True,
                                  env=dict(os.environ, NTK_TEST_IOS_SOURCE_ONLY="1"), timeout=60)
        self.assertEqual(finished.returncode, 2)
        self.assertIn("NTK_TEST_IOS_SOURCE_ONLY", finished.stderr)
        finished, _, _ = self.run_bash("echo sourced-ok")
        self.assertIn("sourced-ok", finished.stdout)

    def test_the_simulator_xcodebuild_drops_the_allowance(self):
        finished, log, _ = self.run_bash("export TEST_RUNNER_NTK_DEVICE_ALLOW=clipboard\nsim_xcodebuild 10 -version")
        self.assertEqual(log, "called ALLOW=\n")

    def test_signals_and_exit_remove_the_device_results(self):
        # Mutation 7 "柱 1（終わりの片付け）": HUP left out of the trap, or the trap set too late.
        for signal, code in (("HUP", 129), ("INT", 130), ("TERM", 143)):
            with self.subTest(signal=signal):
                finished, _, leftovers = self.run_bash(f"setup_device_tmp\ntouch \"$DEVICE_TMP/x.xcresult\"\n"
                                                       f"kill -{signal} $$\nsleep 5\necho not-reached")
                self.assertEqual(finished.returncode, code, finished.stderr)
                self.assertNotIn("not-reached", finished.stdout)
                self.assertEqual(leftovers, [])
        finished, _, leftovers = self.run_bash("setup_device_tmp\ntouch \"$DEVICE_TMP/x.xcresult\"\nexit 0")
        self.assertEqual((finished.returncode, leftovers), (0, []))

    def test_the_script_sets_the_trap_after_the_approval_and_before_the_device(self):
        # The guards above refuse a device call made too early; this pins the order of the main
        # flow too: --dry-run exits, then the approval is consumed, then the trap, then the device.
        lines = joined_script()
        main = lines.index('if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then')

        def first(predicate):
            return next(i for i, line in enumerate(lines) if i > main and predicate(line))

        dry_run_exit = first(lambda line: "stopped before running any test" in line)
        approve = first(lambda line: line.startswith("runner approve "))
        consumed = first(lambda line: line == "APPROVAL_CONSUMED=1")
        trap = first(lambda line: line == "setup_device_tmp")
        device = first(lambda line: line.startswith(("device_xcodebuild ", "device_devicectl ")))
        self.assertLess(dry_run_exit, approve)
        self.assertLess(approve, consumed)
        self.assertLess(consumed, trap)
        self.assertLess(trap, device)

    def test_the_device_is_reached_only_through_the_guarded_functions(self):
        # Review R-10: lines are joined first, so a destination on a continuation line counts.
        lines = joined_script()
        main = lines.index('if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then')
        body = [line for line in lines[main:] if line and not line.startswith("#")]
        self.assertFalse([line for line in body if "platform=iOS,id" in line and not line.startswith("device_xcodebuild ")])
        self.assertFalse([line for line in body if re.search(r"(^|[;&|(]\s*|xcrun\s+)devicectl\b", line)
                          and not line.startswith("device_devicectl ")])
        calls = [line for line in body if "xcodebuild " in line and not line.startswith(("sim_xcodebuild ",
                 "device_xcodebuild ", 'XCODE="$(xcodebuild -version'))]
        self.assertEqual(calls, [])

    # The run's output folder as the script makes it: a real path (TMPDIR is under /var, a symlink).
    RUN = 'OUT_DIR="$(cd -P "$TMPDIR" && pwd -P)/run"; mkdir -p "$OUT_DIR"\n'

    def test_sim_xcodebuild_refuses_any_other_destination(self):
        own = '-derivedDataPath "$OUT_DIR/dd-test" -resultBundlePath "$OUT_DIR/0.xcresult"'
        for destination in ("platform=iOS,id=" + FAKE_DEVICE, "generic/platform=iOS", "id=" + FAKE_DEVICE,
                            "platform=iOS Simulator,name=iPhone 17"):
            with self.subTest(destination=destination):
                finished, log, _ = self.run_bash(self.RUN + f'set +e\nsim_xcodebuild 10 test {own} -destination "{destination}"; '
                                                 'echo "code=$?"')
                self.assertIn("code=97", finished.stdout)
                self.assertEqual(log, "")
        finished, log, _ = self.run_bash(self.RUN + f'sim_xcodebuild 10 test {own} -destination "platform=iOS Simulator,id={SIMULATOR}"')
        self.assertEqual(log, "called ALLOW=\n")

    def test_every_xcodebuild_names_its_own_paths(self):
        # Without -derivedDataPath, xcodebuild writes into Xcode's default DerivedData (the first
        # device run found the simulator enumeration's xcresult there). The simulator's paths must be
        # inside the run's folder and the device's inside its results folder, each option given once
        # as `-option <value>`, with no symlink anywhere (review of the fix A-1, A-2).
        sim = f'-destination "platform=iOS Simulator,id={SIMULATOR}"'
        dd, rb = '-derivedDataPath "$OUT_DIR/dd-test"', '-resultBundlePath "$OUT_DIR/0.xcresult"'
        link = 'mkdir -p "$OUT_DIR/real"; ln -s "$OUT_DIR/real" "$OUT_DIR/link"\n'
        refused = {
            "no -derivedDataPath": f"test-without-building {sim} {rb}",
            "no value at the end": f"test-without-building {sim} {rb} -derivedDataPath",
            "an option as the value": f"test-without-building {sim} -derivedDataPath {rb}",
            "only the = form": f'test-without-building {sim} -derivedDataPath="$OUT_DIR/dd-test" {rb}',
            "the = form besides": f'test-without-building {sim} {dd} -derivedDataPath="$HOME/x" {rb}',
            "another spelling besides": f'test-without-building {sim} {dd} --derivedDataPath "$HOME/x" {rb}',
            "another case besides": f'test-without-building {sim} {dd} -DerivedDataPath "$HOME/x" {rb}',
            "given twice": f'test-without-building {sim} {dd} {rb} -derivedDataPath "$OUT_DIR/dd-2"',
            "the same twice": f"test-without-building {sim} {dd} {dd} {rb}",
            "the default DerivedData": f'test-without-building {sim} -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/x" {rb}',
            "under BUILD_ROOT but outside the run": f'test-without-building {sim} -derivedDataPath "$BUILD_ROOT/DerivedData-simulator" {rb}',
            "the run's folder itself": f'test-without-building {sim} -derivedDataPath "$OUT_DIR" {rb}',
            "a .. component": f'test-without-building {sim} -derivedDataPath "$OUT_DIR/../x" {rb}',
            "a . component": f'test-without-building {sim} -derivedDataPath "$OUT_DIR/./x" {rb}',
            "an empty component": f'test-without-building {sim} -derivedDataPath "$OUT_DIR//x" {rb}',
            "a sibling with the same prefix": f'test-without-building {sim} -derivedDataPath "${{OUT_DIR}}x/dd" {rb}',
            "a symlink inside the run": link + f'sim_xcodebuild 10 test-without-building {sim} -derivedDataPath "$OUT_DIR/link/dd" {rb}',
            "a symlink as the folder": link + f'sim_xcodebuild 10 test-without-building {sim} -derivedDataPath "$OUT_DIR/link" {rb}',
            "a dangling symlink": 'ln -s "$HOME/Library/Developer/Xcode/DerivedData/ntk-not-there" "$OUT_DIR/dangling"\n'
                                  f'sim_xcodebuild 10 test-without-building {sim} -derivedDataPath "$OUT_DIR/dangling" {rb}',
            "a run folder under a symlink": 'OUT_DIR="$TMPDIR/run2"; mkdir -p "$OUT_DIR"\n'
                                            f'sim_xcodebuild 10 test-without-building {sim} {dd} {rb}',
            "no run folder": f'unset OUT_DIR\nsim_xcodebuild 10 test-without-building {sim} -derivedDataPath "$BUILD_ROOT/x/dd" '
                             '-resultBundlePath "$BUILD_ROOT/x/0.xcresult"',
            "a test without -resultBundlePath": f"test-without-building {sim} {dd}",
            "-resultBundlePath twice": f'test-without-building {sim} {dd} {rb} -resultBundlePath "$OUT_DIR/1.xcresult"',
            "-resultBundlePath without a value": f"test-without-building {sim} {dd} -resultBundlePath",
            "-resultBundlePath only in the = form": f'test-without-building {sim} {dd} -resultBundlePath="$OUT_DIR/0.xcresult"',
            "-resultBundlePath in the = form besides": f'test-without-building {sim} {dd} {rb} -resultBundlePath="$HOME/x"',
            "-resultBundlePath outside the run": f'test-without-building {sim} {dd} -resultBundlePath "$BUILD_ROOT/0.xcresult"',
            "-resultBundlePath through a symlink": link + f'sim_xcodebuild 10 test-without-building {sim} {dd} '
                                                          '-resultBundlePath "$OUT_DIR/link/0.xcresult"',
            "a build with -resultBundlePath outside": f'build-for-testing {sim} {dd} -resultBundlePath "$BUILD_ROOT/b.xcresult"',
            "no action": f"-showBuildSettings {sim} {dd}",
            # A second action must not ride on an allowed one (stage 0d review of the fix: A-3).
            "a test after a build": f"build-for-testing test {sim} {dd}",
            "two test actions": f"test test-without-building {sim} {dd} {rb}",
            "an allowed action with archive": f"build-for-testing archive {sim} {dd}",
            "another action alone": f"build {sim} {dd}",
            "clean alone": f"clean {sim} {dd}",
        }
        for name, call in refused.items():
            with self.subTest(refused=name):
                body = call if "sim_xcodebuild" in call else f"sim_xcodebuild 10 {call}"
                finished, log, _ = self.run_bash(self.RUN + f'set +e\n{body}; echo "code=$?"')
                self.assertIn("code=97", finished.stdout, finished.stderr)
                self.assertEqual(log, "")
        for name, call in {"a test": f"test-without-building {sim} {dd} {rb}",
                           "a build": f'build-for-testing {sim} -derivedDataPath "$OUT_DIR/dd-build"',
                           "the unit test": f'test {sim} -derivedDataPath "$OUT_DIR/dd-build" {rb}'}.items():
            with self.subTest(accepted=name):
                finished, log, _ = self.run_bash(self.RUN + f"sim_xcodebuild 10 {call}")
                self.assertEqual(log, "called ALLOW=\n", finished.stderr)
        device = f'-destination "platform=iOS,id={FAKE_DEVICE}"'
        passing = self.RUN + "set +e\nrunner() { return 0; }\nAPPROVAL_CONSUMED=1\nsetup_device_tmp\n"
        for name, call in {
            "the build under BUILD_ROOT": f'build-for-testing {device} -derivedDataPath "$BUILD_ROOT/DerivedData-device"',
            "the build in the run's folder": f'build-for-testing {device} -derivedDataPath "$OUT_DIR/dd-build"',
            "a test without paths": f"test-without-building {device}",
            "a test elsewhere": f'test-without-building {device} -derivedDataPath /tmp/dd -resultBundlePath "$DEVICE_TMP/0.xcresult"',
            "a result bundle in the run's folder": f'test-without-building {device} -derivedDataPath "$DEVICE_TMP/dd-test" '
                                                   '-resultBundlePath "$OUT_DIR/0.xcresult"',
            "given twice": f'test-without-building {device} -derivedDataPath "$DEVICE_TMP/dd-test" -derivedDataPath '
                           '"$DEVICE_TMP/dd-test" -resultBundlePath "$DEVICE_TMP/0.xcresult"',
        }.items():
            with self.subTest(device_refused=name):
                finished, log, _ = self.run_bash(passing + f'device_xcodebuild 10 {call}; echo "code=$?"')
                self.assertIn("code=97", finished.stdout, finished.stderr)
                self.assertEqual(log, "")
        finished, log, _ = self.run_bash(passing + f'device_xcodebuild 10 test-without-building {device} '
                                         '-derivedDataPath "$DEVICE_TMP/dd-test" -resultBundlePath "$DEVICE_TMP/0.xcresult"\n'
                                         f'device_xcodebuild 10 build-for-testing {device} -derivedDataPath "$DEVICE_TMP/dd-build"')
        self.assertEqual(log, "called ALLOW=\ncalled ALLOW=\n", finished.stderr)

    def test_every_xcodebuild_call_of_the_script_names_its_derived_data(self):
        lines = joined_script()
        main = lines.index('if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then')
        calls = [line for line in lines[main:] if line.startswith(("sim_xcodebuild ", "device_xcodebuild "))]
        self.assertGreaterEqual(len(calls), 6)
        self.assertEqual([line for line in calls if "-derivedDataPath " not in line], [])
        tests = [line for line in calls if " test " in line or " test-without-building " in line]
        self.assertEqual([line for line in tests if "-resultBundlePath " not in line], [])
        # Both builds are made inside the folder of this run (no build shared between runs).
        self.assertIn('DD_SIM="${OUT_DIR}/dd-build"', lines)
        self.assertIn('DD_DEVICE="${DEVICE_TMP}/dd-build"', lines)

    def test_capped_fails_when_the_command_cannot_start(self):
        # Review R-13: `exec` failing inside perl used to exit 0.
        finished, _, _ = self.run_bash('set +e\ncapped 10 /nonexistent/command; echo "code=$?"')
        self.assertNotIn("code=0", finished.stdout)
        finished, _, _ = self.run_bash('set +e\ncapped 10 true; echo "code=$?"')
        self.assertIn("code=0", finished.stdout)


class ReviewV1(unittest.TestCase):
    """The fixes of review v1 (reviews/2026-10-24-ios-c-abi-stage0d-review-v1.md), R-8 to R-15."""

    def plan(self, allowed=("systemui",)):
        return r.make_plan("device", FAKE_DEVICE, SIMULATOR, enumeration(), declarations(), list(allowed), None, HEAD,
                           "folderhash", [], False)

    def test_r8_the_whole_approval_is_compared(self):
        plan = self.plan(("systemui", "clipboard"))
        approval = r.make_approval(plan)
        self.assertEqual(r.approval_problems(approval, plan), [])

        def changed(mutate):
            copy = json.loads(json.dumps(approval))
            mutate(copy)
            return r.approval_problems(copy, plan)

        def recategorize(a):
            a["tests"][0]["categories"] = []
        self.assertTrue(changed(recategorize))
        self.assertTrue(changed(lambda a: a["tests"].reverse()))
        self.assertTrue(changed(lambda a: a["excluded"].pop()))
        self.assertTrue(changed(lambda a: a.update(extra=1)))
        self.assertTrue(changed(lambda a: a.pop("excluded")))
        self.assertTrue(changed(lambda a: a.update(createdAt="yesterday")))
        self.assertTrue(changed(lambda a: a.update(trustedPart={"unchanged": True, "changed": [{"file": "x"}]})))

    def test_r9_uncommitted_changes_under_ios_refuse_the_device(self):
        porcelain = " M ios/IosLibraryExample/IosLibraryExample/DialogSampleView.swift\n" \
                    "?? ios/IosLibraryExample/build/test_ios/x.json\n" \
                    "R  ios/a.swift -> ios/b.swift\n"
        self.assertEqual(r.uncommitted_ios_changes(porcelain),
                         ["ios/IosLibraryExample/IosLibraryExample/DialogSampleView.swift", "ios/b.swift"])
        self.assertEqual(r.uncommitted_ios_changes("?? ios/IosLibraryExample/build/x\n"), [])
        with tempfile.TemporaryDirectory() as d:
            repo = make_repo(pathlib.Path(d))
            plan_path, _, _ = write_device_plan(repo)
            args = ["--plan", plan_path, "--head", git(repo, "rev-parse", "HEAD"), "--tests-dir", repo / REPO_TESTS,
                    "--repo", repo]
            self.assertEqual(cli("verify-tree", *args).returncode, 0)
            (repo / "ios" / "IosLibraryExample" / "build").mkdir()
            (repo / "ios" / "IosLibraryExample" / "build" / "out.txt").write_text("x")
            self.assertEqual(cli("verify-tree", *args).returncode, 0)
            (repo / "ios" / "Sample.swift").write_text("let x = 1\n")
            finished = cli("verify-tree", *args)
            self.assertEqual(finished.returncode, 1)
            self.assertIn("uncommitted changes under ios/", finished.stdout)
            (repo / "ios" / "Sample.swift").unlink()
            (repo / REPO_TESTS / "A.swift").write_text("import XCTest // changed\n")
            self.assertEqual(cli("verify-tree", *args).returncode, 1)
            git(repo, "commit", "-q", "-am", "change")
            self.assertEqual(cli("verify-tree", *args).returncode, 1)  # HEAD and the folder moved on

    def test_r11_unreadable_or_unknown_results_stop_the_device(self):
        invocation = {"name": "DialogUITests", "timeout": 1800, "onlyTesting": ["x"],
                      "expected": ["DialogUITests/testD1_showAlertOK"]}

        def run(mutate, summary_total=1):
            data = json.loads(fixture("xcresult-d1-tests.json"))
            mutate(data["testNodes"][0]["children"][0]["children"][0]["children"])
            summary = json.loads(fixture("xcresult-d1-summary.json"))
            summary["totalTestCount"] = summary_total
            return r.record_invocation(invocation, json.dumps(data), json.dumps(summary), 0, False, SIMULATOR)

        def unreadable(cases):
            cases.append(dict(cases[0], nodeIdentifier="DialogUITests/testD1_showAlertOK() (2)"))
        records, stop = run(unreadable, 2)
        self.assertTrue(stop)
        self.assertTrue(any(rec["test"].endswith("#unreadableName") for rec in records))
        self.assertTrue(any(rec["test"].endswith("#readable") for rec in records))

        def repeated(cases):
            cases[0]["children"] = [{"nodeType": "Repetition", "name": "Repetition 1", "result": "Passed"}]
        records, stop = run(repeated)
        self.assertTrue(stop)
        self.assertTrue(any(rec["test"].endswith("#unknownShape") for rec in records))
        records, stop = r.record_invocation(invocation, fixture("xcresult-d1-tests.json"), fixture("xcresult-d1-summary.json"),
                                            0, False, FAKE_DEVICE)
        self.assertTrue(stop)
        records, stop = r.record_invocation(invocation, fixture("xcresult-d1-tests.json"), fixture("xcresult-d1-summary.json"),
                                            0, True, SIMULATOR)
        self.assertTrue(stop)
        records, stop = r.record_invocation(invocation, fixture("xcresult-d1-tests.json"), fixture("xcresult-d1-summary.json"),
                                            0, False, SIMULATOR)
        self.assertFalse(stop)
        self.assertEqual([rec["result"] for rec in records], ["passed"])

    def test_r11_review_exit_code_and_zero_tests(self):
        # Review R-16 list: exit != 0 with every test passed; no test at all.
        invocation = {"name": "DialogUITests", "timeout": 1800, "onlyTesting": ["x"],
                      "expected": ["DialogUITests/testD1_showAlertOK"]}
        records, _ = r.record_invocation(invocation, fixture("xcresult-d1-tests.json"), fixture("xcresult-d1-summary.json"),
                                         65, False, SIMULATOR)
        self.assertTrue(any(rec["test"].endswith("#exitCode") and rec["result"] == "failed" for rec in records))
        data = json.loads(fixture("xcresult-d1-tests.json"))
        data["testNodes"] = []
        summary = json.loads(fixture("xcresult-d1-summary.json"))
        summary.update(totalTestCount=0, passedTests=0)
        records, stop = r.record_invocation(dict(invocation, expected=[]), json.dumps(data), json.dumps(summary), 0, False,
                                            SIMULATOR)
        self.assertTrue(any(rec["test"].endswith("#zeroTests") for rec in records))
        unit = r.unit_records("IosLibraryExampleTests", fixture("xcresult-unit-example-tests.json"), 65)
        self.assertTrue(any(rec["test"].endswith("#exitCode") for rec in unit))

    def test_r12_the_device_test_run_keeps_its_output_in_the_trap_folder(self):
        text = joined_script()
        device_runs = [line for line in text if line.startswith("device_xcodebuild") and "test-without-building" in line]
        self.assertEqual(len(device_runs), 1)
        self.assertIn('-derivedDataPath "${DEVICE_TMP}/dd-test"', device_runs[0])
        self.assertIn("-collect-test-diagnostics never", device_runs[0])

    def test_r14_the_device_bundle_is_checked_too(self):
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            plan = self.plan()
            (d / "plan.json").write_text(json.dumps(plan))
            products = d / "Products"
            bundle = make_bundle(products, "iphoneos", TESTS_DIR / r.DECLARATIONS_FILE)
            args = ["--plan", d / "plan.json", "--otool-objc", FIXTURES / "otool-ov-device.txt",
                    "--otool-load", FIXTURES / "otool-l-device.txt", "--tests-dir", TESTS_DIR, "--products", products]
            finished = cli("check-binary", *args)
            self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
            (bundle / "DeviceRequirements.json").write_text("{}")
            self.assertEqual(cli("check-binary", *args).returncode, 1)
            shutil.copy(TESTS_DIR / r.DECLARATIONS_FILE, bundle / "DeviceRequirements.json")
            with open(bundle / "Info.plist", "wb") as f:
                plistlib.dump({"NSPrincipalClass": "Evil"}, f)
            finished = cli("check-binary", *args)
            self.assertEqual(finished.returncode, 1)
            self.assertIn("NSPrincipalClass", finished.stdout)

    def test_r14_binary_tests_listed_twice_stop(self):
        keys = r.binary_test_keys(r.parse_otool_classes(fixture("otool-ov-device.txt"), fixture("otool-l-device.txt")))
        self.assertTrue(r.binary_inventory_problems(keys + keys[:1], enumeration()))

    def test_r15_a_device_plan_with_no_test_is_refused(self):
        table = {k: ["files"] for k in declarations()}
        with self.assertRaises(r.RunnerError):
            r.make_plan("device", FAKE_DEVICE, SIMULATOR, enumeration(), table, [], None, HEAD, "h", [], False)
        self.assertTrue(r.make_plan("simulator", SIMULATOR, SIMULATOR, enumeration(), table, [], None, HEAD, "h", [],
                                    False)["selected"])

    def test_r17_the_simulator_can_name_each_test(self):
        ids = enumeration()
        plan = r.make_plan("simulator", SIMULATOR, SIMULATOR, ids, declarations(), [], "Notification", HEAD, "h", [], False,
                           name_each_test=True)
        self.assertTrue(plan["nameEachTest"])
        self.assertEqual(r.device_names_tests_only(plan["invocations"]), [])
        self.assertEqual(sorted(n for inv in plan["invocations"] for n in inv["onlyTesting"]), sorted(plan["selected"]))
        self.assertEqual([inv["stage"] for inv in plan["invocations"]][:2], ["permission", "permission"])


class ReviewV2(unittest.TestCase):
    """The fixes of review v2 (reviews/2026-10-24-ios-c-abi-stage0d-review-v2.md), R-18 to R-21."""

    def test_r18_the_runner_must_be_committed_and_unchanged(self):
        with tempfile.TemporaryDirectory() as d:
            repo = make_repo(pathlib.Path(d))
            plan_path, approval_path, plan = write_device_plan(repo)
            self.assertEqual(r.runner_problems(plan, repo), [])
            runner = repo / "scripts" / "ios_ui_runner.py"
            runner.write_text(runner.read_text() + "\n# edited\n")
            problems = r.runner_problems(plan, repo)
            self.assertTrue(any("differs from the commit" in p for p in problems))
            self.assertTrue(any("differ from the ones" in p for p in problems))
            finished = cli("approve", *approve_args(repo, plan_path, approval_path))
            self.assertEqual(finished.returncode, 1)
            self.assertFalse((repo.parent / "ledger.log").exists())
            git(repo, "rm", "-q", "--cached", "scripts/test_ios.sh")
            git(repo, "commit", "-q", "-m", "untrack")
            self.assertTrue(any("not committed" in p for p in r.git_runner_file_changes(repo)))

    def test_r19_the_gate_checks_the_approved_plan_before_each_device_call(self):
        with tempfile.TemporaryDirectory() as d:
            repo = make_repo(pathlib.Path(d))
            plan_path, approval_path, plan = write_device_plan(repo)
            approval = json.loads(approval_path.read_text())
            ledger = repo.parent / "ledger.log"
            head = git(repo, "rev-parse", "HEAD")
            gate = lambda p, a: r.gate_problems(p, a, repo, head, repo / REPO_TESTS, ledger)
            self.assertTrue(any("not consumed" in p for p in gate(plan, approval)))
            r.consume_approval(ledger, approval["approvalId"], FAKE_DEVICE)
            self.assertEqual(gate(plan, approval), [])
            changed = json.loads(json.dumps(plan))
            changed["invocations"][0]["onlyTesting"].append(ident("ShareUITests/testS1_shareTextCopy"))
            self.assertTrue(any("differs from the approved" in p for p in gate(changed, approval)))
            changed = json.loads(json.dumps(plan))
            changed["invocations"][0]["expected"].pop()
            self.assertTrue(gate(changed, approval))
            self.assertEqual(approval["planDigest"], r.plan_digest(plan))
            self.assertTrue(r.approval_problems(dict(approval, planDigest="0" * 64), plan))

    def test_r19_the_script_switches_to_the_read_only_plan_before_the_device(self):
        lines = joined_script()
        main = lines.index('if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then')
        after = lines[main:]
        switch = after.index('PLAN="${DEVICE_TMP}/plan.approved.json"')
        self.assertLess(after.index('chmod 0444 "${DEVICE_TMP}/plan.approved.json"'), switch)
        first_device = next(i for i, line in enumerate(after) if line.startswith(("device_xcodebuild ", "device_devicectl ")))
        self.assertLess(switch, first_device)
        guard = lines[lines.index("device_guard() {"):]
        self.assertTrue(guard[guard.index("fi") + 1].startswith("runner device-gate --plan \"${PLAN}\" --approved"))

    def test_r20_a_test_case_child_of_an_unknown_kind_stops(self):
        invocation = {"name": "DialogUITests", "timeout": 1800, "onlyTesting": ["x"],
                      "expected": ["DialogUITests/testD1_showAlertOK"]}
        for kind in ("Something New", "Repetition", None):
            with self.subTest(kind=kind):
                data = json.loads(fixture("xcresult-d1-tests.json"))
                case = data["testNodes"][0]["children"][0]["children"][0]["children"][0]
                case["children"] = [{"nodeType": kind, "name": "x", "result": "Failed"}]
                records, stop = r.record_invocation(invocation, json.dumps(data), fixture("xcresult-d1-summary.json"),
                                                    0, False, SIMULATOR)
                self.assertTrue(stop)
                self.assertTrue(any(rec["test"].endswith("#unknownShape") for rec in records))
        data = json.loads(fixture("xcresult-d1-tests.json"))
        case = data["testNodes"][0]["children"][0]["children"][0]["children"][0]
        case["children"] = [{"nodeType": "Failure Message", "name": "x"}]
        _, stop = r.record_invocation(invocation, json.dumps(data), fixture("xcresult-d1-summary.json"), 0, False, SIMULATOR)
        self.assertFalse(stop)

    def test_r21_the_reply_placeholder_is_the_sample_s_own(self):
        sample = (SAMPLE_DIR / "NotificationSampleView.swift").read_text(encoding="utf-8")
        placeholder = swift_string_constant("sampleReplyPlaceholder")
        self.assertEqual(placeholder, "IosLibraryExample reply")
        self.assertIn(f'textInputPlaceholder: "{placeholder}"', sample)
        self.assertNotIn("Type a message", sample)
        springboard = (SUPPORT / "Springboard.swift").read_text(encoding="utf-8")
        self.assertNotIn("expandedScope()", springboard)
        self.assertNotIn('"Type a message"', springboard)
        scope = springboard[springboard.index("private func expandedScope("):springboard.index("func expandBanner(")]
        self.assertIn('"content of the expanded sample notification")', scope)
        reply = springboard[springboard.index("func sendReply("):springboard.index("// MARK: Alerts")]
        self.assertEqual(reply.count("_ = try expandedScope(title: title, body: body)"), 2)
        self.assertIn('let typed = try exactlyOne(springboard.windows.containing(afterTyping), "reply window")', reply)


class MutationHarness(unittest.TestCase):
    """The mutation runs (scripts/tests/ios_ui_runner_mutations.py) keep every copy away from the
    real ledger (review v2, C)."""

    def harness(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("ios_ui_runner_mutations", HERE / "ios_ui_runner_mutations.py")
        harness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(harness)
        return harness

    def test_the_runner_reads_the_ledger_home_the_harness_replaces(self):
        # In the repository the runner has the expression; in a harness copy it is already replaced.
        text = RUNNER.read_text(encoding="utf-8")
        self.assertTrue(self.harness().LEDGER_HOME in text or "getpwuid" not in text)

    def test_a_prepared_copy_uses_its_own_ledger(self):
        harness = self.harness()
        with tempfile.TemporaryDirectory() as d:
            fake_repo, root = pathlib.Path(d) / "repo", pathlib.Path(d) / "copy"
            for part in harness.COPIED:
                (fake_repo / part).parent.mkdir(parents=True, exist_ok=True)
                if "." in pathlib.Path(part).name:
                    (fake_repo / part).write_text("")
                else:
                    (fake_repo / part).mkdir(exist_ok=True)
            (fake_repo / harness.M).write_text("import os, pathlib, pwd\nDEFAULT_LEDGER = " + harness.LEDGER_HOME
                                               + " / 'ledger.log'\n")
            harness.REPO = fake_repo
            root.mkdir()
            self.assertTrue(harness.prepare_copy(root))
            printed = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); "
                                      "import ios_ui_runner as r; print(r.DEFAULT_LEDGER)", str(root / "scripts")],
                                     capture_output=True, text=True, env=dict(os.environ, HOME=str(root)))
            self.assertEqual(printed.stdout.strip(), str(root / "ledger.log"), printed.stderr)
            (fake_repo / harness.M).write_text("import os, pwd\nHOME = pwd.getpwuid(os.getuid())\n")
            shutil.rmtree(root)
            root.mkdir()
            with self.assertRaises(RuntimeError):
                harness.prepare_copy(root)


def make_bundle(products, sdk, declarations_path, info=None):
    bundle = products / f"Debug-{sdk}" / "IosLibraryExampleUITests-Runner.app" / "PlugIns" / "IosLibraryExampleUITests.xctest"
    bundle.mkdir(parents=True)
    shutil.copy(declarations_path, bundle / "DeviceRequirements.json")
    with open(bundle / "Info.plist", "wb") as f:
        plistlib.dump(info or {"CFBundleIdentifier": "ios.library.example.IosLibraryExampleUITests"}, f)
    return bundle


def joined_script():
    """test_ios.sh with continuation lines joined, stripped (R-10: a destination on a continuation
    line must not slip past the static checks)."""
    lines, current = [], ""
    for raw in SCRIPT.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.endswith("\\"):
            current += line[:-1] + " "
            continue
        lines.append(current + line)
        current = ""
    return lines


class Commands(unittest.TestCase):
    """The CLI glue between test_ios.sh and the functions (review R-16)."""

    def test_approve_refuses_a_list_that_does_not_match_and_keeps_the_ledger(self):
        with tempfile.TemporaryDirectory() as d:
            repo = make_repo(pathlib.Path(d))

            def drop(a):
                a["tests"].pop()
            plan_path, approval_path, _ = write_device_plan(repo, selected_change=drop)
            finished = cli("approve", *approve_args(repo, plan_path, approval_path))
            self.assertEqual(finished.returncode, 1)
            self.assertFalse((repo.parent / "ledger.log").exists())
            plan_path, approval_path, _ = write_device_plan(repo)
            (repo / "ios" / "dirty.swift").write_text("x")
            finished = cli("approve", *approve_args(repo, plan_path, approval_path))
            self.assertEqual(finished.returncode, 1)
            self.assertIn("uncommitted", finished.stdout)
            self.assertFalse((repo.parent / "ledger.log").exists())

    def test_record_stops_the_device_with_exit_3_and_not_the_simulator(self):
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            for kind, udid, code in (("device", FAKE_DEVICE, 3), ("simulator", SIMULATOR, 0)):
                with self.subTest(kind=kind):
                    plan = {"kind": kind, "udid": udid, "invocations": [
                        {"index": 0, "name": "DialogUITests", "timeout": 1800, "onlyTesting": ["x"],
                         "expected": ["DialogUITests/testD1_showAlertOK", "DialogUITests/testD2_showConfirmDialogYes"]}]}
                    (d / "plan.json").write_text(json.dumps(plan))
                    tests = d / "tests.json"
                    data = json.loads(fixture("xcresult-d1-tests.json"))
                    data["devices"][0]["deviceId"] = udid
                    tests.write_text(json.dumps(data))
                    finished = cli("record", "--plan", d / "plan.json", "--index", 0, "--tests-json", tests,
                                   "--summary-json", FIXTURES / "xcresult-d1-summary.json", "--exit-code", 0,
                                   "--results", d / f"{kind}.jsonl")
                    self.assertEqual(finished.returncode, code, finished.stdout + finished.stderr)

    def test_may_uninstall_needs_reinstall_in_the_plan_and_the_approval(self):
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            for plan_allow, approved_allow, code in ((["systemui"], ["systemui"], 1),
                                                      (["reinstall", "systemui"], ["systemui"], 1),
                                                      (["reinstall", "systemui"], ["reinstall", "systemui"], 0)):
                with self.subTest(plan=plan_allow, approved=approved_allow):
                    (d / "plan.json").write_text(json.dumps({"kind": "device", "deviceAllow": plan_allow}))
                    (d / "approval.json").write_text(json.dumps({"deviceAllow": approved_allow}))
                    self.assertEqual(cli("may-uninstall", "--plan", d / "plan.json", "--approved",
                                         d / "approval.json").returncode, code)

    def preflight(self, d, tests, dry_run, kind="device"):
        enumeration_path = d / "enumeration.json"
        table = r.parse_declarations((tests / r.DECLARATIONS_FILE).read_text(encoding="utf-8"))
        enumeration_path.write_text(json.dumps(fake_enumeration(table)))
        products = d / "Products"
        if not products.exists():
            make_bundle(products, "iphonesimulator", tests / r.DECLARATIONS_FILE)
        args = ["--kind", kind, "--udid", FAKE_DEVICE if kind == "device" else SIMULATOR, "--enumerate-udid", SIMULATOR,
                "--enumeration", enumeration_path, "--tests-dir", tests, "--products", products, "--allow",
                "systemui" if kind == "device" else "", "--head", HEAD, "--repo", self.repo, "--plan", d / "plan.json",
                "--approval-out", d / "approval.json"]
        return cli("preflight", *(args + (["--dry-run"] if dry_run else [])))

    def test_preflight_refuses_the_device_when_the_trusted_part_changed(self):
        temp, tests = copy_tests()
        self.repo = make_repo(temp)
        try:
            self.assertEqual(self.preflight(temp, tests, dry_run=False).returncode, 0)
            path = tests / "Support" / "SampleApp.swift"
            path.write_text(path.read_text(encoding="utf-8") + "\n// changed\n", encoding="utf-8")
            finished = self.preflight(temp, tests, dry_run=False)
            self.assertEqual(finished.returncode, 1)
            self.assertIn("trusted part changed", finished.stderr)
            finished = self.preflight(temp, tests, dry_run=True)
            self.assertEqual(finished.returncode, 0)
            self.assertIn("THE TRUSTED PART CHANGED", finished.stdout)
            self.assertFalse(json.loads((temp / "approval.json").read_text())["trustedPart"]["unchanged"])
            self.assertEqual(self.preflight(temp, tests, dry_run=False, kind="simulator").returncode, 0)
        finally:
            shutil.rmtree(temp)

    def summary(self, d, plan, results, approved=None, baseline=None):
        (d / "plan.json").write_text(json.dumps(plan))
        (d / "environment.json").write_text(json.dumps({"kind": plan["kind"], "model": "iPhone 17", "os": "26.2",
                                                         "osBuild": "23C54", "language": "en"}))
        (d / "results.jsonl").write_text("".join(json.dumps(x) + "\n" for x in results))
        baselines = d / "baselines"
        baselines.mkdir(exist_ok=True)
        if baseline is not None:
            (baselines / "test_ios.baseline.iPhone_17-26.2.json").write_text(json.dumps({"results": baseline}))
        args = ["--plan", d / "plan.json", "--environment", d / "environment.json", "--results", d / "results.jsonl",
                "--baseline-dir", baselines]
        if approved:
            (d / "approval.json").write_text(json.dumps(approved))
            args += ["--approved", d / "approval.json"]
        return cli("summary", *args)

    def test_summary_compares_what_ran_with_the_approval_and_the_baseline(self):
        plan = r.make_plan("device", FAKE_DEVICE, SIMULATOR, enumeration(), declarations(), ["systemui"], None, HEAD, "h",
                           [], False)
        approval = r.make_approval(plan)
        ran = [{"test": f"IosLibraryExampleUITests/{r.key_from_enumeration_id(i)}", "result": "passed"} for i in plan["selected"]]
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            self.assertEqual(self.summary(d, plan, ran, approval).returncode, 0)
            finished = self.summary(d, plan, ran[1:], approval)
            self.assertEqual(finished.returncode, 1)
            self.assertIn("differ from the approved list", finished.stdout)
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            baseline = {x["test"]: "passed" for x in ran}
            self.assertEqual(self.summary(d, plan, ran, approval, baseline).returncode, 0)
            baseline["IosLibraryExampleUITests/DialogUITests/testD99_gone"] = "passed"
            finished = self.summary(d, plan, ran, approval, baseline)
            self.assertEqual(finished.returncode, 1)
            self.assertIn("did not run", finished.stdout)


FAKE_TOOLS = {
    "xcodebuild": r'''
import json, os, pathlib, plistlib, shutil, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("xcodebuild " + json.dumps(args) + " ALLOW=" + os.environ.get("TEST_RUNNER_NTK_DEVICE_ALLOW", "") + "\n")
def opt(name):
    return args[args.index(name) + 1] if name in args else None
if args == ["-version"]:
    print("Xcode 26.3"); print("Build version 17C529"); sys.exit(0)
sdk = "iphoneos" if (opt("-destination") or "").startswith("platform=iOS,") else "iphonesimulator"
tests = pathlib.Path(os.environ["FAKE_TESTS_DIR"])
if "build-for-testing" in args:
    products = pathlib.Path(opt("-derivedDataPath")) / "Build" / "Products"
    products.mkdir(parents=True, exist_ok=True)
    (products / f"IosLibraryExample_IosLibraryExample_{sdk}26.2-arm64.xctestrun").write_text("")
    bundle = products / f"Debug-{sdk}" / "IosLibraryExampleUITests-Runner.app" / "PlugIns" / "IosLibraryExampleUITests.xctest"
    bundle.mkdir(parents=True, exist_ok=True)
    shutil.copy(tests / "Support" / "DeviceRequirements.json", bundle / "DeviceRequirements.json")
    with open(bundle / "Info.plist", "wb") as f:
        plistlib.dump({"CFBundleIdentifier": "x"}, f)
    (bundle / "IosLibraryExampleUITests").write_text("binary")
    sys.exit(0)
if "-enumerate-tests" in args:
    table = json.loads((tests / "Support" / "DeviceRequirements.json").read_text())["tests"]
    enabled = [{"identifier": f"IosLibraryExampleUITests/{k}()"} for k in sorted(table)]
    enabled.append({"identifier": "IosLibraryExampleUITests/SampleUITestCase"})
    pathlib.Path(opt("-test-enumeration-output-path")).write_text(json.dumps(
        {"errors": [], "values": [{"enabledTests": enabled, "disabledTests": [], "testPlan": "IosLibraryExample"}]}))
    sys.exit(0)
if "test-without-building" in args:
    pathlib.Path(opt("-resultBundlePath")).mkdir(parents=True)
    sys.exit(0)
sys.exit(98)
''',
    "xcrun": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("xcrun " + json.dumps(args) + "\n")
    if args[:1] == ["devicectl"]:
        ledger = pathlib.Path(os.environ["FAKE_LEDGER"])
        log.write("devicectl-ledger " + (ledger.read_text() if ledger.exists() else "") .replace("\n", "|") + "\n")
fixtures = pathlib.Path(os.environ["FAKE_FIXTURES"])
if args[:3] == ["simctl", "list", "-j"]:
    print((fixtures / ("simctl-devices.json" if args[3] == "devices" else "simctl-runtimes.json")).read_text()); sys.exit(0)
if args[:1] == ["xcresulttool"]:
    print(pathlib.Path(os.environ["FAKE_TESTS_JSON" if "tests" in args else "FAKE_SUMMARY_JSON"]).read_text()); sys.exit(0)
if args[:4] == ["devicectl", "device", "info", "details"]:
    out = args[args.index("--json-output") + 1]
    pathlib.Path(out).write_text(json.dumps({"result": {
        "hardwareProperties": {"udid": os.environ["FAKE_DEVICE"], "marketingName": "iPhone XS"},
        "deviceProperties": {"osVersionNumber": "18.7.2", "osBuildUpdate": "22H124"}}}))
    sys.exit(0)
sys.exit(99)
''',
    "otool": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("otool " + json.dumps(args) + "\n")
if args[0] == "-l":
    print("Load command 1\n  sectname __objc_selrefs\n   segname __DATA\n      addr 0x0000000000005000"); sys.exit(0)
table = json.loads((pathlib.Path(os.environ["FAKE_TESTS_DIR"]) / "Support" / "DeviceRequirements.json").read_text())["tests"]
classes = {}
for key in table:
    cls, method = key.split("/")
    classes.setdefault(cls, []).append(method)
print(args[-1] + ":")
print("Contents of (__DATA_CONST,__objc_classlist) section")
for n, (cls, methods) in enumerate(sorted(classes.items())):
    objc = f"_TtC24IosLibraryExampleUITests{len(cls)}{cls}"
    print(f"{n * 8:016x} 0x{0x10000 + n * 0x100:x} _OBJC_CLASS_$_{objc}")
    print("    superclass 0x0 _OBJC_CLASS_$_XCTestCase")
    print(f"        name           0x1 {objc}")
    print("        baseMethods    0x2 methods")
    for method in methods:
        print(f"            name    0x3 {method}AndReturnError:")
    print("        baseProtocols  0x0")
print("Contents of (__DATA,__objc_selrefs) section")
''',
    "git": r'''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("git " + json.dumps(args) + "\n")
if "rev-parse" in args:
    print(os.environ["FAKE_HEAD"])
sys.exit(0)
''',
}


class EndToEnd(unittest.TestCase):
    """test_ios.sh from start to end in a copy of the repository, with xcodebuild, xcrun, otool
    and git replaced by fakes that only record (review R-16). No simulator, no device."""

    def setUp(self):
        self.temp = pathlib.Path(tempfile.mkdtemp())
        root = self.temp / "root"
        shutil.copytree(ROOT / "scripts", root / "scripts", ignore=shutil.ignore_patterns("__pycache__", "fixtures"))
        tests = root / REPO_TESTS
        shutil.copytree(TESTS_DIR, tests, ignore=shutil.ignore_patterns(".DS_Store"))
        (root / "ios" / "IosLibraryExample" / "IosLibraryExample.xcodeproj").mkdir(parents=True)
        shutil.copy(PBXPROJ, root / "ios" / "IosLibraryExample" / "IosLibraryExample.xcodeproj" / "project.pbxproj")
        self.ledger = self.temp / "ledger.log"
        runner = root / "scripts" / "ios_ui_runner.py"
        text = runner.read_text(encoding="utf-8")
        start = text.index("DEFAULT_LEDGER = ")
        end = text.index("\n", text.index('"test_ios-approvals.log"', start))
        # Only in this copy: the self-test's ledger (R-6 keeps the real one fixed).
        runner.write_text(text[:start] + f"DEFAULT_LEDGER = pathlib.Path({str(self.ledger)!r})" + text[end:], encoding="utf-8")
        bin_dir = self.temp / "bin"
        bin_dir.mkdir()
        for name, body in FAKE_TOOLS.items():
            (bin_dir / name).write_text(f"#!{sys.executable}\n{body}")
            (bin_dir / name).chmod(0o755)
        self.root, self.tests, self.log = root, tests, self.temp / "log"
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", FAKE_LOG=str(self.log),
                        FAKE_TESTS_DIR=str(tests), FAKE_FIXTURES=str(FIXTURES), FAKE_DEVICE=FAKE_DEVICE, FAKE_HEAD=HEAD,
                        FAKE_LEDGER=str(self.ledger), TMPDIR=str(self.temp), FAKE_TESTS_JSON=str(self.temp / "tests.json"),
                        FAKE_SUMMARY_JSON=str(FIXTURES / "xcresult-d1-summary.json"))

    def tearDown(self):
        shutil.rmtree(self.temp)

    def run_script(self, *args):
        if self.log.exists():
            self.log.unlink()
        finished = subprocess.run(["bash", str(self.root / "scripts" / "test_ios.sh"), *args], capture_output=True,
                                  text=True, env=self.env, timeout=300)
        return finished, self.log.read_text() if self.log.exists() else ""

    def dry_run(self, allow):
        finished, log = self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--dry-run",
                                        "--device-allow", allow)
        self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
        approvals = sorted((self.root / "ios" / "IosLibraryExample" / "build" / "test_ios").glob("*-device*/approval.json"))
        return finished, log, approvals[-1]

    def assert_own_derived_data(self, log, stdout):
        """Every xcodebuild call but -version named its DerivedData (and a test its result bundle)
        inside this run's folder for the simulator, or the device's results folder for the device,
        so nothing reached Xcode's default DerivedData or another run's folder."""
        run = pathlib.Path(next(line[len("[out] "):] for line in stdout.splitlines() if line.startswith("[out] ")))
        build_root = (self.root / "ios" / "IosLibraryExample" / "build" / "test_ios").resolve()
        self.assertEqual(run.parent, build_root)
        device_tmp = str(self.temp.resolve() / "test_ios-device.")
        calls = [json.loads(line[len("xcodebuild "):line.rindex(" ALLOW=")]) for line in log.splitlines()
                 if line.startswith("xcodebuild ")]
        actions = [args for args in calls if args != ["-version"]]
        self.assertTrue(actions)
        for args in actions:
            on_device = (args[args.index("-destination") + 1]).startswith("platform=iOS,")
            options = ["-derivedDataPath"] + ([] if "build-for-testing" in args else ["-resultBundlePath"])
            for option in options:
                self.assertEqual(args.count(option), 1, args)
                path = args[args.index(option) + 1]
                if on_device:
                    self.assertTrue(path.startswith(device_tmp), path)
                else:
                    self.assertTrue(path.startswith(str(run) + "/"), path)
        return actions

    def test_the_simulator_runs_keep_out_of_the_default_derived_data(self):
        (self.temp / "tests.json").write_text(fixture("xcresult-d1-tests.json"))
        for extra in (["--dry-run"], ["--feature", "Dialog"]):
            with self.subTest(extra=extra):
                finished, log = self.run_script("--udid", SIMULATOR, *extra)
                actions = self.assert_own_derived_data(log, finished.stdout)
                self.assertTrue(any("-enumerate-tests" in args for args in actions))
                if extra == ["--feature", "Dialog"]:
                    runs = [args for args in actions if "test-without-building" in args and "-enumerate-tests" not in args]
                    self.assertTrue(runs, finished.stdout + finished.stderr)

    def test_the_device_dry_run_never_calls_the_device(self):
        finished, log, approval = self.dry_run("systemui")
        self.assert_own_derived_data(log, finished.stdout)
        self.assertNotIn("devicectl", log)
        self.assertNotIn("platform=iOS,id", log)
        self.assertIn(f"platform=iOS Simulator,id={SIMULATOR}", log)
        self.assertEqual(json.loads(approval.read_text())["udid"], FAKE_DEVICE)
        self.assertIn("approval ID", finished.stdout)

    def test_a_used_approval_stops_before_devicectl(self):
        _, _, approval = self.dry_run("systemui")
        r.consume_approval(self.ledger, json.loads(approval.read_text())["approvalId"], FAKE_DEVICE)
        finished, log = self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--device-allow", "systemui",
                                        "--devicectl-id", "DCID", "--approved", str(approval))
        self.assertEqual(finished.returncode, 1)
        self.assertIn("already used", finished.stderr)
        self.assertNotIn("devicectl", log)
        self.assertNotIn("platform=iOS,id", log)

    def test_an_unreadable_device_result_stops_the_run_and_removes_the_results(self):
        _, _, approval = self.dry_run("")
        approval_id = json.loads(approval.read_text())["approvalId"]
        data = json.loads(fixture("xcresult-d1-tests.json"))
        data["devices"][0]["deviceId"] = FAKE_DEVICE
        case = data["testNodes"][0]["children"][0]["children"][0]["children"][0]
        case["nodeIdentifier"] = "NavigationUITests/testM1_menuOpensEachScreenAndBackReturnsToTheMenu() (1)"
        (self.temp / "tests.json").write_text(json.dumps(data))
        finished, log = self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--device-allow", "",
                                        "--devicectl-id", "DCID", "--approved", str(approval))
        self.assertEqual(finished.returncode, 1, finished.stdout + finished.stderr)
        self.assertIn("the device run was stopped", finished.stderr)
        self.assertIn("unreadableName", finished.stdout)
        devicectl = [line for line in log.splitlines() if line.startswith("xcrun [\"devicectl\"")]
        self.assertEqual(len(devicectl), 1)
        self.assertIn('"info", "details"', devicectl[0])
        # The approval was consumed before devicectl ran.
        self.assertIn(approval_id, next(line for line in log.splitlines() if line.startswith("devicectl-ledger ")))
        device_runs = [line for line in log.splitlines() if "platform=iOS,id=" + FAKE_DEVICE in line]
        self.assertEqual(len(device_runs), 2)  # the build and the first class, then the stop
        self.assertTrue(all(line.endswith(" ALLOW=") for line in device_runs))
        self.assert_own_derived_data(log, finished.stdout)
        self.assertEqual(sorted(p.name for p in self.temp.glob("test_ios-device.*")), [])


SUPPORT = TESTS_DIR / "Support"


def swift_string_constant(name):
    m = re.search(r'static let %s = "([^"]*)"' % name, (SUPPORT / "SystemLabels.swift").read_text(encoding="utf-8"))
    return m.group(1)


def quoted_names(label):
    """Mirror of `Springboard.quotedNames(in:)`."""
    names, current = [], None
    for character in label:
        if character == "“":
            if current is not None:
                return None
            current = ""
        elif character == "”":
            if current is None:
                return None
            names.append(current)
            current = None
        elif current is not None:
            current += character
    return names if current is None else None


def paste_alert_names_known_source(label):
    """Mirror of `Springboard.pasteAlertNamesKnownSource(_:)` (review R-3)."""
    names = quoted_names(label)
    if names is None or len(names) != 2:
        return False
    sample, runner = swift_string_constant("sampleDisplayName"), swift_string_constant("runnerDisplayName")
    return names[0] == sample and names[1] in (runner, sample)


class PasteAlert(unittest.TestCase):
    """CB1 presses Allow Paste only for the sample pasting from the runner or from itself (review
    R-3). The decision is a pure Swift function in the trusted Springboard.swift; this mirrors it
    and pins the Swift text it mirrors, so the two cannot drift apart unnoticed."""

    EN = "“IosLibraryExample” would like to paste from “IosLibraryExampleUITests-Runner”"
    JA = "“IosLibraryExample”に“IosLibraryExample”からペーストしようとしています"

    def test_the_runner_and_the_sample_are_known_sources(self):
        self.assertTrue(paste_alert_names_known_source(self.EN))
        self.assertTrue(paste_alert_names_known_source(self.JA))
        self.assertTrue(paste_alert_names_known_source("“IosLibraryExample” would like to paste from “IosLibraryExample”"))

    def test_another_source_or_another_app_is_refused(self):
        for label in ("“IosLibraryExample” would like to paste from “Jonghyun’s MacBook Pro”",
                      "“IosLibraryExample”に“田中のMac”からペーストしようとしています",
                      "“Notes” would like to paste from “IosLibraryExampleUITests-Runner”",
                      "“IosLibraryExampleUITests-Runner” would like to paste from “IosLibraryExample”",
                      "“IosLibraryExample” would like to paste from “IosLibraryExampleUITests-Runner ”"):
            with self.subTest(label=label):
                self.assertFalse(paste_alert_names_known_source(label))

    def test_exactly_two_quoted_names(self):
        for label in ("“IosLibraryExample” would like to paste", "IosLibraryExample would like to paste from IosLibraryExample",
                      "“IosLibraryExample” would like to paste from “IosLibraryExample” via “Mac”",
                      "“IosLibraryExample” would like to paste from “IosLibraryExample", "“IosLibraryExample” from ”x“",
                      "“IosLibraryExample“ would like to paste from ”IosLibraryExample”", ""):
            with self.subTest(label=label):
                self.assertFalse(paste_alert_names_known_source(label))

    def test_the_swift_function_is_the_one_mirrored(self):
        text = (SUPPORT / "Springboard.swift").read_text(encoding="utf-8")
        body = text[text.index("static func pasteAlertNamesKnownSource"):text.index("private func tapAlertButton")]
        self.assertIn("guard let names = quotedNames(in: label), names.count == 2 else { return false }", body)
        self.assertIn("return names[0] == SystemLabels.sampleDisplayName", body)
        self.assertIn("[SystemLabels.runnerDisplayName, SystemLabels.sampleDisplayName].contains(names[1])", body)
        quoted = text[text.index("static func quotedNames"):text.index("static func pasteAlertNamesKnownSource")]
        for line in ('case "“":', "guard current == nil else { return nil }", 'case "”":',
                     "guard let name = current else { return nil }", "current?.append(character)",
                     "return current == nil ? names : nil"):
            self.assertIn(line, quoted)
        self.assertEqual(swift_string_constant("runnerDisplayName"), "IosLibraryExampleUITests-Runner")
        self.assertEqual(swift_string_constant("sampleDisplayName"), "IosLibraryExample")
        self.assertIn("tapPasteAlertFromKnownSource(SystemLabels.allowPaste)",
                      (TESTS_DIR / "ClipboardPasteUITests.swift").read_text(encoding="utf-8"))


def fake_enumeration(table):
    tests = [{"identifier": f"IosLibraryExampleUITests/{key}()"} for key in sorted(table)]
    tests.append({"identifier": "IosLibraryExampleUITests/SampleUITestCase"})
    return {"errors": [], "values": [{"enabledTests": tests, "disabledTests": [], "testPlan": "IosLibraryExample"}]}


if __name__ == "__main__":
    unittest.main()
