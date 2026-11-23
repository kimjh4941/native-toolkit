#!/usr/bin/env python3
"""Decisions and checks of scripts/test_mac.sh (macOS UI test design, section 6.3).

The shell script runs xcodebuild, tart, ssh and tar; everything that decides what runs, and every
check of what ran, is here as pure functions so that scripts/tests/test_mac_ui_runner.py can break
them directly (design 6.3 "判定は ... 純粋な関数に置く", chapter 7).

Design: artifact/topics/macos-c-abi/designs/2026-11-23-macos-c-abi-ui-test-design.md

Two ways to run (6.3):
  vm   A tart VM that the runner qualifies by fact every time (6.3 step 0). No approval: the VM has
       no personal account, no shared clipboard and no shared folder. The sources go in by tar over
       ssh, the VM builds and runs, and only the values of 3.4 come back.
  mac  The user's own Mac. The three pillars of the iOS runner (U-9): the runner selects the tests
       by their declared categories, the declarations are checked (the enumeration comes from the
       VM, the build of this Mac is checked against it), and the user approves every run
       (--dry-run writes the list with a one-time ID, --approved consumes it in a ledger).

This module must run on the VM's /usr/bin/python3 (3.9): no `match`, no `X | Y` types.

Updating the pinned hashes (TRUSTED_FILES, FROZEN_FILES): only after a review of the change by
another model (iOS design 2 "信頼する部分"). `python3 scripts/mac_ui_runner.py hashes` prints the
current values; record the review in artifact/topics/macos-c-abi/ next to the change.
"""

import argparse
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import plistlib
import pwd
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

# --- Fixed tables ---------------------------------------------------------------------------

UI_TARGET = "MacLibraryExampleUITests"
LIBRARY_UNIT_TARGET = "MacLibraryTests"
EXAMPLE_UNIT_TARGET = "MacLibraryExampleTests"
UNIT_TARGETS = (LIBRARY_UNIT_TARGET, EXAMPLE_UNIT_TARGET)
SAMPLE_BUNDLE_ID = "com.jonghyunkim.mac.nativetoolkit.example"
RUNNER_BUNDLE_ID = "mac.library.example.MacLibraryExampleUITests.xctrunner"
BASE_CLASS = "SampleUITestCase"

# The declared categories (3.3) and the ones that never run on this Mac (VM only).
CATEGORIES = ("notification", "ncsettings", "settings", "badge", "clipboard", "pasteprivacy", "sharepicker",
              "realservice", "panels", "coldstart")
VM_ONLY_CATEGORIES = ("ncsettings", "pasteprivacy", "realservice")
MAC_CATEGORIES = tuple(c for c in CATEGORIES if c not in VM_ONLY_CATEGORIES)

FEATURES = ("Dialog", "Notification", "Share", "Clipboard")
COMMON_FEATURE = "Common"

# Classes in the order of 6.3 step 7, with their feature. Common runs with every --feature.
# The notification classes always run one test per xcodebuild (6.3 step 7).
UI_CLASSES = (
    ("SupportRuleTests", COMMON_FEATURE),
    ("NavigationUITests", COMMON_FEATURE),
    ("IdentifierInventoryUITests", COMMON_FEATURE),
    ("DialogUITests", "Dialog"),
    ("NotificationUITests", "Notification"),
    ("NotificationEventUITests", "Notification"),
    ("NotificationColdStartUITests", "Notification"),
    ("ClipboardSampleViewUITests", "Clipboard"),
    ("ClipboardSampleWaitRuleTests", "Clipboard"),
    ("ClipboardPasteUITests", "Clipboard"),
    ("ShareUITests", "Share"),
)
NOTIFICATION_CLASSES = ("NotificationUITests", "NotificationEventUITests", "NotificationColdStartUITests")
# The permission stage (U-7; VM only by its categories) and the paste privacy stage (U-12).
PERMISSION_CLASS = "NotificationPermissionUITests"
PERMISSION_ORDER = ("testNP2_requestPermissionDontAllow", "testNP3_showImmediateAsksThenShows",
                    "testNP1_requestPermissionAllow")
PRIVACY_CLASS = "ClipboardPrivacyUITests"
SEPARATE_CLASSES = ((PERMISSION_CLASS, "Notification"), (PRIVACY_CLASS, "Clipboard"))
# The U-30 probes (MacQualificationProbeTests) are not written yet; their class goes here when they are.
QUALIFICATION_CLASSES = ()
# The watch (U-20): first of the notification tests, only when one is selected.
WATCH_TEST = "NotificationUITests/testN4_showImmediateBanner"
# Tests that share the sample's Share picker and may open Mail (S11): Mail is stopped after the class.
MAIL_CLASS = "ShareUITests"
# Classes whose tests never launch the sample, so they attach no button coverage (5.7).
NO_SAMPLE_CLASSES = ("SupportRuleTests", "ClipboardSampleWaitRuleTests")

ONE_TEST_TIMEOUT_SECONDS = 15 * 60
CLASS_TIMEOUT_SECONDS = 60 * 60

# Per-class minimum declarations (U-9 pillar 2 (2)); CLASS_ANY_OF: every test declares one of them.
CLASS_MINIMUMS = {
    "ClipboardSampleViewUITests": {"clipboard"},
    "ClipboardPasteUITests": {"clipboard"},
    PRIVACY_CLASS: {"clipboard", "pasteprivacy"},
    "NotificationEventUITests": {"notification"},
    "NotificationColdStartUITests": {"notification", "coldstart"},
    PERMISSION_CLASS: {"notification", "ncsettings"},
}
CLASS_ANY_OF = {"ShareUITests": {"sharepicker", "realservice"}}

# Exclusion reasons (3.4 ExclusionReason): the one vocabulary of --dry-run, the results and the baseline.
EXCLUSION_REASONS = ("category", "vmOnly", "osOnly", "macDeferred", "qualificationOnly", "environmentExclusion",
                     "auditExpired", "ownerUnverified")

# Tests that run only in the VM whatever their categories say. None today: every VM-only test is
# VM only through its categories (ncsettings, pasteprivacy, realservice). Keys must be declared.
VM_ONLY_TESTS = frozenset()
# Tests that run only on one major version of macOS (U-16, U-33). The back button cannot be pressed on
# 15.8.3 (9.0 (2)); 15 has no Copy in the share picker (M-3).
OS_ONLY_TESTS = {
    "NavigationUITests/testM1b_backReturnsToTheMenu": "26",
    "NavigationUITests/testM2_reopenedScreensStartFromTheirInitialState": "26",
    "ClipboardSampleViewUITests/testObservationStopsWhenTheScreenIsLeft": "26",
    "ShareUITests/testS2_shareTextCopy": "26",
    "ShareUITests/testS4_shareURLCopy": "26",
}
# What each deferred test presses that has not been checked on macOS 26 (5.0, U-5, U-30): on this
# Mac a test is selected only when every target of it is in MAC_VERIFIED_TARGETS. The reason is
# macDeferred when the test also waits for the Reply check (U-5), ownerUnverified otherwise.
MAC_DEFERRED_TESTS = {
    "NotificationEventUITests/testN20_categoryAddsOptions": ("ownerUnverified", ("notificationMenuItem",)),
    "NotificationEventUITests/testN23_openAction": ("ownerUnverified", ("notificationMenuItem",)),
    "NotificationColdStartUITests/testNC2_openActionLaunches": ("ownerUnverified", ("notificationMenuItem",)),
    "NotificationEventUITests/testN24_replyAction": ("macDeferred", ("notificationMenuItem", "replyInBanner")),
    "NotificationColdStartUITests/testNC3_replyLaunches": ("macDeferred", ("notificationMenuItem", "replyInBanner")),
    "ClipboardPasteUITests/testCB1_pasteButtonPastesWithoutConfirmation": ("ownerUnverified", ("pasteButton",)),
    "ShareUITests/testS2_shareTextCopy": ("ownerUnverified", ("pickerCopy",)),
    "ShareUITests/testS4_shareURLCopy": ("ownerUnverified", ("pickerCopy",)),
}
PRESS_TARGETS = ("notificationMenuItem", "replyInBanner", "pasteButton", "pickerCopy")
# The press targets checked on macOS 26 (the results of U-30 copied here). Empty until U-30.
MAC_VERIFIED_TARGETS = frozenset()
# Tests of the qualification stages (U-30): never in a normal run or a baseline.
QUALIFICATION_ONLY_TESTS = {"mac26": frozenset(), "mac26-reply": frozenset(), "vm-ja": frozenset()}
# Exclusions per environment (U-33: if the back button cannot be pressed on 26 either). Empty.
ENVIRONMENT_EXCLUSIONS = {"vm": {}, "mac": {}}

# The fixed Clipboard classes (U-26): their files are pinned whole and their methods listed (0c 3.1).
FROZEN_FILES = {
    "ClipboardSampleViewUITests.swift": "c1924aa9b959fd7d931248b5ebaecf0fc17dcdb0875b0472bfa80b4fbdccf028",
    "ClipboardSampleWaitRuleTests.swift": "c861faa4babd1f36578997532e2fe72881179b8c30b10c28e3fcadc0b7bbf0cb",
}
FROZEN_METHODS = {
    "ClipboardSampleViewUITests": (
        "testEveryButtonReportsAResult", "testAnExpectationThatDoesNotHoldIsShownAsAFailure",
        "testTheScopeArgumentFollowsThePicker", "testAnOrdinaryFailureIsRecordedInTheReachedList",
        "testCreatingANamedPasteboardAgainKeepsItsContents", "testCreatingAUniquePasteboardAgainReleasesThePreviousOne",
        "testANamedPasteboardGoesFromCreationThroughUseToRemoval",
        "testAUniquePasteboardGoesFromCreationThroughUseToRemoval", "testAppendFollowsTheOwnershipTheCopyReturned",
        "testObservationStopsWhenTheScreenIsLeft", "testACallerSuppliedPasteboardNameIsNotShown",
    ),
    "ClipboardSampleWaitRuleTests": (
        "testTheSameTextFromAnEarlierClickIsNotAccepted", "testAResultFromAnotherButtonIsNotAccepted",
        "testTheResultOfThisClickIsAccepted", "testALongerButtonNameDoesNotStandInForTheShorterOne",
        "testADetailWordDoesNotStandInForALabel", "testARepeatWithIdenticalTextIsAccepted",
    ),
}

# The trusted part (iOS design 2; macOS 6.1): the base file and the Support files, pinned per file.
# Pinned in stage 0d (2026-11-23) from commit 623a919b, the end of stage 0c. Not yet reviewed by
# another model (stage 0d working notes).
BASE_FILE = "Support/SampleUITestCase.swift"
TRUSTED_FILES = {
    "Support/NotificationCenterUI.swift": "99b962c089f5a350742742ac5b17b325bc07df4c96db37572dc32f8c6e512bcf",
    "Support/NotificationCleanup.swift": "0b176bdde9c83566af5d3e653a0ad4f4e73312dd9f941036bf4205033eea0840",
    "Support/NotificationRules.swift": "55d55dcfce4ea987f6835c98179590000e05b0a98a4ec933395cb0a5eb7d8d69",
    "Support/NotificationScreen.swift": "ed0c28a531f60df8bcc7c3d83c2ef2e9893cd0450ff8e874eb27b57fd3b86af1",
    "Support/OtherApps.swift": "1c3fa497b36bb0f342392f6e105e8ca9867d241264db1a3397f5b00be504a563",
    "Support/Panels.swift": "5959023421beb3137940351e0444e396f0ee4847593bc81236af0b29d7aa7324",
    "Support/PrivacyPrompt.swift": "e552df65bbe391a0c4e5d6a003ef31c37d1847910168a300b2ea64384e01cf2c",
    "Support/RunnerPasteboard.swift": "7a4f14256a5808ebbcf0300aaa6370a1ac34d1fae8038b39bac20789fb336f27",
    "Support/SampleApp.swift": "ee528175a23bffbb6b6f3fe111347954fa25c05774d7c0be5a01cfd63cc569aa",
    "Support/SampleUITestCase.swift": "a1f2e883faf8c27bedace3b7a3163fb0bb5b3c398a5fb056fe868d799cb2fa19",
    "Support/SharePicker.swift": "0b21705e53c039f1e647654b80a3c9dc8870cbc05c7a32042b9849825e800190",
    "Support/StepCode.swift": "46f31c5136b38ca2e0fb5e7d38401c67d6de74cceddb2f77ccede70f40fac2f4",
    "Support/SystemLabels.swift": "0af3f74c50f33a7935c4b25c310e3d9f32de0907898ae7a92a3c8d27f719b707",
    "Support/UnexpectedInterruptionGuard.swift": "f1c9b99b3a5de5a420ca09f53b5a563a6c9ed16df2fe9a0d96b06827cd77cfad",
    "Support/WaitRule.swift": "accb6087e9294087b76ab5fa23a37336084e365fe91c71764bf65096b276e704",
}
DECLARATIONS_FILE = "Support/DeviceRequirements.json"
STEP_CODE_FILE = "Support/StepCode.swift"

# Names that drive the system, the Mac or the pasteboard directly (6.1 "危ない名前"): only in the
# trusted part. `supportRoot` is the Support files' shared XCUIApplication (0c 1.7 (9)).
DANGEROUS_NAMES = ("XCUIApplication", "NSPasteboard", "NSWorkspace", "NSRunningApplication", "Process",
                   "addUIInterruptionMonitor", "typeKey", "typeText", "coordinate", "supportRoot")
# The frozen files' known occurrences, checked by count (0c 3.1).
FROZEN_DANGEROUS_COUNTS = {
    "ClipboardSampleViewUITests.swift": {"XCUIApplication": 9},
    "ClipboardSampleWaitRuleTests.swift": {},
}
# Known uses in the test files of a Support wrapper that has a dangerous name: (file, name) -> count.
# DialogUITests calls SampleAlert.typeKey, which checks the alert and the focus before the key (5.0).
# The allowance names the receiver too: `alert.typeKey(` only (Claude B-15).
TEST_FILE_DANGEROUS_ALLOWANCES = {("DialogUITests.swift", "typeKey"): (1, "alert")}
# The frozen files' identifier strings (`clipboard.`), checked by count (0c 3.1).
FROZEN_IDENTIFIER_COUNTS = {"ClipboardSampleViewUITests.swift": 10, "ClipboardSampleWaitRuleTests.swift": 0}
FORBIDDEN_NAMES = ("XCTExpectFailure", "XCTExpectedFailure", "XCTestObservationCenter", "XCTestObservation",
                   "NSPrincipalClass")
ALLOWED_IMPORTS = {"XCTest", "Foundation"}
ALLOWED_SUPPORT_IMPORTS = ALLOWED_IMPORTS | {"AppKit", "Darwin", "CoreGraphics"}
ALLOWED_ATTRIBUTES = {"MainActor", "discardableResult", "escaping", "Sendable", "autoclosure", "unknown"}
ALLOWED_POUND = {"available", "unavailable", "file", "fileID", "filePath", "line", "column", "function", "dsohandle"}
CONDITIONAL_POUND = {"if", "elseif", "else", "endif"}
HOOKS = ("setUpAfterGate", "tearDownAfterGate")
IDENTIFIER_STRING = re.compile(r"(?<![A-Za-z0-9_])(menu|dialog|notification|share|clipboard)\.(?=[A-Za-z]|$)")
FORBIDDEN_IN_TEST_FILES = {"extension", "protocol", "deinit", "required", "convenience", "dynamic"}
MODIFIERS = {"final", "private", "fileprivate", "internal", "public", "open", "nonisolated", "static", "class",
             "override", "mutating", "nonmutating", "lazy", "weak", "unowned", "indirect", "dynamic",
             "required", "convenience", "optional", "package"}

# Intended skips (6.3 "結果の読み方"): none today.
INTENDED_SKIPS = ()

# The VM (6.3 step 0, U-25). Provenance: 0a chapter 1.
VM_PROVENANCE = "cirrus-vanilla-15.7.7+15.8.3"
VM_OS = ("15.8.3", "24H241")
VM_XCODE = ("26.3", "17C529")
VM_LANGUAGE = "en-US"
# Every account of the VM must be of these types; only HolidayCalendar may be authenticated (it is a
# system account). Anything else, a Mail account above all, fails the qualification (fail closed).
VM_ALLOWED_ACCOUNT_TYPES = {"com.apple.account.HolidayCalendar": True, "com.apple.account.OnMyDevice": False,
                            "com.apple.account.iTunesStore": False}
MAC_MAJOR = "26"
# The Xcode this Mac builds with (U-23).
MAC_XCODE = "26.6"

COVERAGE_ATTACHMENT = re.compile(r"^ntk-button-coverage-v1(_\d+_[0-9A-Fa-f-]+)?\.json$")
APPROVAL_ID = re.compile(r"^[0-9a-f]{32}$")
APPROVAL_HOURS = 12
# What must be shown in the VM before anything runs on this Mac (design 9.2 last line, U-8, 9.1 and
# U-30): each value is where the check is recorded, or None while it is not done. An approval is
# refused while any is None (Claude B-14, Codex B-5).
MAC_RUN_PREREQUISITES = {
    "u8MonitorStopsTheTest": None,         # U-8: the monitor really stops a test (a harmless alert in the VM)
    "killDuringRecording": None,           # 9.1: the parent KILLed during a real recording; the writers stop
    "windowOwnersReadableOn26": None,      # U-30 mac26: CGWindowListCopyWindowInfo on this Mac
    "decoyNotificationRoot": None,         # 6c and 7 "根（動き）": nothing reaches a decoy with the same title
}


def prerequisite_status(repo, table=None):
    """{name: record path or None}. A value counts only when it is a path inside artifact/ of the
    repository that exists (Claude v2 C-5); anything else is None, as if not checked."""
    status = {}
    for name, value in (MAC_RUN_PREREQUISITES if table is None else table).items():
        ok = isinstance(value, str) and value.startswith("artifact/") and ".." not in value.split("/") \
            and (pathlib.Path(repo) / value).is_file()
        status[name] = value if ok else None
    return status
DEFAULT_LEDGER = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library" / "Application Support" / "native-toolkit" \
    / "test_mac-approvals.log"
LEDGER_LINE = re.compile(r"^[0-9a-f]{32}\t\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\+00:00|Z)\tmac$")
# The runner's own output under mac/ (git-ignored by mac/.gitignore; 3.4).
MAC_OUTPUT_PREFIX = "mac/MacLibraryExample/build/"
RUNNER_FILES = ("scripts/mac_ui_runner.py", "scripts/test_mac.sh", "scripts/mac_unit_audit.json")
AUDIT_FILE = "scripts/mac_unit_audit.json"
# The audit is bound to these parts of the tree (U-29): MacLibrary, MacLibraryTests and the project.
AUDIT_TREE_PATHS = ("mac/MacLibrary/MacLibrary", "mac/MacLibrary/MacLibraryTests",
                    "mac/MacLibrary/MacLibrary.xcodeproj/project.pbxproj",
                    "mac/MacLibrary/MacLibrary.xcodeproj/xcshareddata/xcschemes",
                    "mac/MacWorkspace.xcworkspace/contents.xcworkspacedata")
AUDIT_PATTERNS = {
    "NSPasteboard.general": r"NSPasteboard\.general\b",
    ".general": r"(?<!NSPasteboard)\.general\b",
    "NSGeneralPboard": r"NSGeneralPboard",
    "CFPasteboard general": r"Apple CFPasteboard general",
    "NSPasteboard(name:": r"NSPasteboard\(\s*name\s*:",
    "MacClipboardManager.shared": r"MacClipboardManager\.shared\b",
    "UNUserNotificationCenter.current": r"UNUserNotificationCenter\.current\b",
    "MacNotificationManager.shared": r"MacNotificationManager\.shared\b",
    "NSSharingService": r"NSSharingService\w*",
    "MacShareManager.shared": r"MacShareManager\.shared\b",
    "NSWorkspace": r"NSWorkspace\w*",
    "TEST_HOST": r"TEST_HOST",
}
AUDIT_WORDS = tuple(AUDIT_PATTERNS)
# The suites share these helpers; their words are counted too (Claude B-11).
AUDIT_HELPER_GLOB = "**/Mock*.swift"


class RunnerError(Exception):
    """A check failed; the message says which and why."""


# --- Names (6.1 DeviceRequirements.json) ----------------------------------------------------

_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]*$")


def key_from_enumeration_id(identifier):
    """`MacLibraryExampleUITests/<Class>/<method>()` -> `<Class>/<method>`."""
    parts = identifier.split("/")
    if len(parts) != 3 or parts[0] != UI_TARGET or not parts[2].endswith("()"):
        raise RunnerError(f"unexpected enumeration identifier: {identifier}")
    return _checked_key(f"{parts[1]}/{parts[2][:-2]}", identifier)


def key_from_node_id(node_id):
    """`<Class>/<method>()` (xcresult nodeIdentifier) -> `<Class>/<method>`."""
    if not node_id.endswith("()") or node_id.count("/") != 1:
        raise RunnerError(f"unexpected nodeIdentifier: {node_id}")
    return _checked_key(node_id[:-2], node_id)


def enumeration_id_from_key(key):
    return f"{UI_TARGET}/{key}()"


def _checked_key(key, original):
    if not _KEY.match(key):
        raise RunnerError(f"not <Class>/test<Name>: {original}")
    return key


def class_of(key):
    return key.split("/", 1)[0]


def method_of(key):
    return key.split("/", 1)[1]


def duplicates(items):
    seen, repeated = set(), []
    for item in items:
        if item in seen and item not in repeated:
            repeated.append(item)
        seen.add(item)
    return repeated


# --- Enumeration (6.3 VM step 3) ------------------------------------------------------------

def parse_enumeration(text):
    """The UI test identifiers of `-enumerate-tests -test-enumeration-style flat
    -test-enumeration-format json`, in order. Only `MacLibraryExampleUITests/` entries are kept
    (the unit tests come too). The base class may be listed without methods; any other such
    entry stops the run."""
    data = json.loads(text)
    if data.get("errors"):
        raise RunnerError(f"the enumeration reported errors: {data['errors']}")
    values = data.get("values")
    if not isinstance(values, list) or len(values) != 1:
        raise RunnerError("the enumeration must have exactly one value (one test plan configuration)")
    if values[0].get("disabledTests"):
        raise RunnerError(f"the enumeration lists disabled tests: {values[0]['disabledTests']}")
    identifiers = []
    for test in values[0].get("enabledTests", []):
        identifier = test.get("identifier", "")
        if not identifier.startswith(UI_TARGET + "/"):
            continue
        if identifier.count("/") == 1:
            if identifier != f"{UI_TARGET}/{BASE_CLASS}":
                raise RunnerError(f"a class without test methods other than {BASE_CLASS}: {identifier}")
            continue
        key_from_enumeration_id(identifier)
        identifiers.append(identifier)
    return identifiers


def parse_declarations(text):
    """`Support/DeviceRequirements.json` -> {key: [categories]}. Repeated keys fail even though
    JSON parsers keep the last one silently."""
    def no_duplicates(pairs):
        repeated = duplicates([k for k, _ in pairs])
        if repeated:
            raise RunnerError(f"{DECLARATIONS_FILE} repeats keys: {repeated}")
        return dict(pairs)

    data = json.loads(text, object_pairs_hook=no_duplicates)
    if set(data) != {"schema", "tests"} or data["schema"] != 1 or not isinstance(data["tests"], dict):
        raise RunnerError(f"{DECLARATIONS_FILE} must be {{\"schema\": 1, \"tests\": {{...}}}}")
    table = {}
    for key, categories in data["tests"].items():
        _checked_key(key, key)
        if not isinstance(categories, list) or not all(isinstance(c, str) for c in categories):
            raise RunnerError(f"{DECLARATIONS_FILE} {key}: the value must be an array of strings")
        unknown = [c for c in categories if c not in CATEGORIES]
        if unknown:
            raise RunnerError(f"{DECLARATIONS_FILE} {key}: unknown categories {unknown}")
        if duplicates(categories):
            raise RunnerError(f"{DECLARATIONS_FILE} {key}: repeated categories {duplicates(categories)}")
        table[key] = list(categories)
    return table


def known_classes():
    return {c for c, _ in UI_CLASSES + SEPARATE_CLASSES} | set(QUALIFICATION_CLASSES)


def table_keys():
    """Every key the runner's tables name; each must be declared (a renamed test stops the runner
    instead of dropping out of a table)."""
    keys = set(VM_ONLY_TESTS) | set(OS_ONLY_TESTS) | set(MAC_DEFERRED_TESTS) | {WATCH_TEST}
    for tests in QUALIFICATION_ONLY_TESTS.values():
        keys |= set(tests)
    for table in ENVIRONMENT_EXCLUSIONS.values():
        keys |= set(table)
    keys |= {f"{PERMISSION_CLASS}/{m}" for m in PERMISSION_ORDER}
    return keys


def check_enumeration(identifiers, declarations):
    """VM step 3: the enumeration against the table, the class list, the minimums, the runner's
    tables and the frozen classes. Returns the problems (an empty list passes)."""
    problems = []
    if duplicates(identifiers):
        problems.append(f"the enumeration repeats identifiers: {duplicates(identifiers)}")
    keys = [key_from_enumeration_id(i) for i in identifiers]
    missing = sorted(set(keys) - set(declarations))
    extra = sorted(set(declarations) - set(keys))
    if missing:
        problems.append(f"tests without a declaration in {DECLARATIONS_FILE}: {missing}")
    if extra:
        problems.append(f"declarations without a test: {extra}")
    classes = {class_of(k) for k in keys}
    if classes != known_classes():
        problems.append(f"the enumerated classes differ from the runner's classes: not listed "
                        f"{sorted(classes - known_classes())}, not enumerated {sorted(known_classes() - classes)}")
    problems += check_class_minimums(declarations)
    undeclared = sorted(table_keys() - set(declarations))
    if undeclared:
        problems.append(f"the runner's tables name tests that are not declared (renamed?): {undeclared}")
    problems += check_frozen_methods(keys)
    return problems


def check_class_minimums(declarations):
    problems = []
    for key, categories in sorted(declarations.items()):
        minimum = CLASS_MINIMUMS.get(class_of(key), set())
        if not minimum <= set(categories):
            problems.append(f"{key} declares {sorted(categories)}, below the minimum of its class {sorted(minimum)}")
        any_of = CLASS_ANY_OF.get(class_of(key))
        if any_of and not any_of & set(categories):
            problems.append(f"{key} declares {sorted(categories)}, none of {sorted(any_of)} its class needs")
    return problems


def check_frozen_methods(keys):
    problems = []
    for cls, frozen in FROZEN_METHODS.items():
        methods = [method_of(k) for k in keys if class_of(k) == cls]
        if sorted(methods) != sorted(frozen):
            problems.append(f"{cls} methods differ from the frozen list: added {sorted(set(methods) - set(frozen))}, "
                            f"removed {sorted(set(frozen) - set(methods))}")
    return problems


# --- Hashes (6.3, iOS design 2 "信頼する部分") -----------------------------------------------

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def file_sha256(path):
    return sha256_bytes(pathlib.Path(path).read_bytes())


def trusted_part_changes(tests_dir, pinned=None):
    """[(file, pinned, actual)] for the trusted files that differ (actual is None when missing),
    and Support files that are not in the table (a new Support file is not trusted)."""
    pinned = TRUSTED_FILES if pinned is None else pinned
    changes = []
    for relative, expected in sorted(pinned.items()):
        path = pathlib.Path(tests_dir) / relative
        actual = file_sha256(path) if path.is_file() else None
        if actual != expected:
            changes.append((relative, expected, actual))
    return changes


def frozen_file_problems(tests_dir, pinned=None):
    pinned = FROZEN_FILES if pinned is None else pinned
    problems = []
    for relative, expected in sorted(pinned.items()):
        path = pathlib.Path(tests_dir) / relative
        actual = file_sha256(path) if path.is_file() else None
        if actual != expected:
            problems.append(f"{relative} differs from the frozen file (sha256 {actual}, pinned {expected})")
    return problems


def folder_hash(root, exclude_prefixes=()):
    """One hash over every file under root (relative path and content), .DS_Store aside."""
    root = pathlib.Path(root)
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if (p.is_file() or p.is_symlink()) and p.name != ".DS_Store"):
        relative = path.relative_to(root).as_posix()
        if any(relative.startswith(prefix) for prefix in exclude_prefixes):
            continue
        content = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
        digest.update(relative.encode() + b"\0" + sha256_bytes(content).encode() + b"\n")
    return digest.hexdigest()


def tree_hash(repo, paths):
    """One hash over the files git would hand over (`git ls-files -co --exclude-standard`) under
    the paths, the runner's output folder and .DS_Store aside. The same list goes to the VM."""
    files = git_file_list(repo, paths)
    digest = hashlib.sha256()
    for relative in files:
        path = pathlib.Path(repo) / relative
        if path.is_symlink():
            content = os.readlink(path).encode()
        elif path.is_file():
            content = path.read_bytes()
        else:
            continue  # deleted in the work tree but still listed
        digest.update(relative.encode() + b"\0" + sha256_bytes(content).encode() + b"\n")
    return digest.hexdigest()


def git_file_list(repo, paths):
    finished = subprocess.run(["git", "-C", str(repo), "ls-files", "-co", "--exclude-standard", "-z", "--", *paths],
                              capture_output=True)
    if finished.returncode != 0:
        raise RunnerError("git ls-files failed")
    names = [n.decode() for n in finished.stdout.split(b"\0") if n]
    return sorted(n for n in names if not n.startswith(MAC_OUTPUT_PREFIX) and not n.endswith("/.DS_Store")
                  and n != ".DS_Store")


def bundle_declaration_problems(source_path, bundle_paths):
    if not bundle_paths:
        return [f"no {DECLARATIONS_FILE} in the built test bundle"]
    expected = file_sha256(source_path)
    differing = [p for p in bundle_paths if file_sha256(p) != expected]
    return [f"{len(differing)} bundled copy(ies) differ from {DECLARATIONS_FILE}"] if differing else []


def bundle_info_plist_problems(info_plist_paths):
    problems = []
    for path in info_plist_paths:
        with open(path, "rb") as f:
            info = plistlib.load(f)
        if "NSPrincipalClass" in info:
            problems.append("the built test bundle's Info.plist sets NSPrincipalClass")
    return problems


def step_vocabulary(step_code_text):
    """The cases of `enum StepCode` (Support/StepCode.swift, a trusted file): the only values that
    may follow `NTK-STEP:` in what leaves the run (3.4)."""
    m = re.search(r"enum StepCode: String, CaseIterable \{(.*?)\n\}", step_code_text, re.S)
    if not m:
        raise RunnerError("Support/StepCode.swift has no `enum StepCode: String, CaseIterable`")
    cases = re.findall(r"^\s*case (\w+)\s*$", m.group(1), re.M)
    if not cases or duplicates(cases):
        raise RunnerError("Support/StepCode.swift: no cases, or repeated cases")
    return cases


# --- Closed source rules (6.1) ----------------------------------------------------------------

class Token:
    __slots__ = ("kind", "text", "line", "segments")

    def __init__(self, kind, text, line, segments=None):
        self.kind = kind          # ident, eident (`escaped`), string, regex, pound, attr, number, punct
        self.text = text
        self.line = line
        self.segments = segments  # literal parts of a string

    def __repr__(self):
        return f"Token({self.kind}, {self.text!r}, {self.line})"


class LexError(Exception):
    pass


_IDENT = re.compile(r"[^\W\d]\w*|\$\w+", re.UNICODE)
_NUMBER = re.compile(r"0[xob][0-9A-Fa-f_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?")
# A bare regex literal may follow these (6.1: `firstMatch(of: /.../)`); after a value, `/` divides.
_REGEX_AFTER_PUNCT = set("(,:=[{!&|?;")
_REGEX_AFTER_WORDS = {"return", "in", "case", "where", "try", "await", "throw", "if", "guard", "while"}


def lex(text):
    """Swift tokens without comments; string literals become one token with their literal parts,
    followed by the tokens of their interpolations (so code inside `\\(...)` is still checked).
    Regex literals (`/.../` and `#/.../#`) become one token, so their quotes do not open strings."""
    tokens, _, _ = _lex(text, 0, 1, stop_at_paren=False)
    return tokens


def _regex_may_start(tokens):
    if not tokens:
        return True
    prev = tokens[-1]
    if prev.kind == "punct":
        return prev.text in _REGEX_AFTER_PUNCT
    return prev.kind == "ident" and prev.text in _REGEX_AFTER_WORDS


def _bare_regex_end(text, i):
    """The index after the closing `/` of a bare regex literal starting at i, or None. A bare
    literal does not start with a space and stays on one line; `\\` escapes, `[...]` may hold `/`."""
    n = len(text)
    j = i + 1
    if j >= n or text[j] in " \t\n/*":
        return None
    in_class = 0
    while j < n:
        c = text[j]
        if c == "\n":
            return None
        if c == "\\":
            j += 2
            continue
        if c == "[":
            in_class += 1
        elif c == "]" and in_class:
            in_class -= 1
        elif c == "/" and not in_class:
            return j + 1 if text[j - 1] not in " \t" else None
        j += 1
    return None


def _lex(text, i, line, stop_at_paren):
    tokens = []
    depth = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            i, line = _skip_block_comment(text, i, line)
        elif re.match(r"#+/", text[i:i + 8]):
            pounds = len(re.match(r"#+", text[i:]).group(0))
            closing = "/" + "#" * pounds
            j = text.find(closing, i + pounds + 1)
            if j < 0:
                raise LexError(f"line {line}: unterminated extended regex literal")
            body = text[i:j + len(closing)]
            tokens.append(Token("regex", body, line))
            line += body.count("\n")
            i = j + len(closing)
        elif c == '"' or (c == "#" and re.match(r"#+\"", text[i:])):
            token, i, line, inner = _lex_string(text, i, line)
            tokens.append(token)
            tokens.extend(inner)
        elif c == "#":
            m = _IDENT.match(text, i + 1)
            if not m:
                raise LexError(f"line {line}: unsupported '#' construct")
            tokens.append(Token("pound", m.group(0), line))
            i = m.end()
        elif c == "/" and _regex_may_start(tokens) and _bare_regex_end(text, i) is not None:
            end = _bare_regex_end(text, i)
            tokens.append(Token("regex", text[i:end], line))
            i = end
        elif c == "@":
            m = _IDENT.match(text, i + 1)
            if not m:
                raise LexError(f"line {line}: '@' without a name")
            tokens.append(Token("attr", m.group(0), line))
            i = m.end()
        elif c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                raise LexError(f"line {line}: unterminated escaped identifier")
            tokens.append(Token("eident", text[i + 1:j], line))
            i = j + 1
        elif _NUMBER.match(text, i) and c.isdigit():
            m = _NUMBER.match(text, i)
            tokens.append(Token("number", m.group(0), line))
            i = m.end()
        elif _IDENT.match(text, i):
            m = _IDENT.match(text, i)
            tokens.append(Token("ident", m.group(0), line))
            i = m.end()
        else:
            if stop_at_paren:
                if c == "(":
                    depth += 1
                elif c == ")":
                    if depth == 0:
                        return tokens, i + 1, line
                    depth -= 1
            tokens.append(Token("punct", c, line))
            i += 1
    if stop_at_paren:
        raise LexError(f"line {line}: unterminated string interpolation")
    return tokens, i, line


def _skip_block_comment(text, i, line):
    depth = 0
    n = len(text)
    while i < n:
        if text.startswith("/*", i):
            depth += 1
            i += 2
        elif text.startswith("*/", i):
            depth -= 1
            i += 2
            if depth == 0:
                return i, line
        else:
            if text[i] == "\n":
                line += 1
            i += 1
    raise LexError(f"line {line}: unterminated block comment")


def _lex_string(text, i, line):
    start_line = line
    pounds = 0
    while text[i] == "#":
        pounds += 1
        i += 1
    multiline = text.startswith('"""', i)
    i += 3 if multiline else 1
    closing = ('"""' if multiline else '"') + "#" * pounds
    escape = "\\" + "#" * pounds
    segments, current, inner = [], [], []
    n = len(text)
    while True:
        if i >= n:
            raise LexError(f"line {start_line}: unterminated string")
        if text.startswith(closing, i):
            i += len(closing)
            break
        if text.startswith(escape, i):
            j = i + len(escape)
            if j < n and text[j] == "(":
                segments.append("".join(current))
                current = []
                tokens, i, line = _lex(text, j + 1, line, stop_at_paren=True)
                inner.extend(tokens)
                continue
            if j < n:
                current.append(text[j])
                if text[j] == "\n":
                    line += 1
                i = j + 1
                continue
        ch = text[i]
        if ch == "\n":
            if not multiline:
                raise LexError(f"line {line}: newline in a single-line string")
            line += 1
        current.append(ch)
        i += 1
    segments.append("".join(current))
    return Token("string", "".join(segments), start_line, segments), i, line, inner


def file_role(relative):
    if relative == BASE_FILE:
        return "base"
    if relative in TRUSTED_FILES:
        return "trusted"
    if relative in FROZEN_FILES:
        return "frozen"
    return "test"


def _word(token, *words):
    return token is not None and token.kind == "ident" and token.text in words


def _at(tokens, i):
    return tokens[i] if 0 <= i < len(tokens) else None


def _preceding_declaration_words(tokens, i):
    """Modifiers and attributes written before the keyword at i."""
    modifiers, attributes = [], []
    j = i - 1
    while j >= 0:
        t = tokens[j]
        if t.kind == "ident" and t.text in MODIFIERS:
            modifiers.append(t.text)
        elif t.kind == "attr":
            attributes.append(t.text)
        elif t.kind == "punct" and t.text == ")" and _attribute_argument_start(tokens, j) is not None:
            j = _attribute_argument_start(tokens, j)
            continue
        else:
            break
        j -= 1
    return modifiers, attributes


def _attribute_argument_start(tokens, close_index):
    depth = 0
    for j in range(close_index, -1, -1):
        if tokens[j].kind == "punct" and tokens[j].text == ")":
            depth += 1
        elif tokens[j].kind == "punct" and tokens[j].text == "(":
            depth -= 1
            if depth == 0:
                return j - 1 if j > 0 and tokens[j - 1].kind == "attr" else None
    return None


def check_swift_source(relative, text):
    """The closed rules of 6.1 for one file of the test folder. Returns the problems."""
    role = file_role(relative)
    try:
        tokens = lex(text)
    except LexError as e:
        return [f"{relative}: cannot read the source ({e})"]
    problems = []

    def problem(token, message):
        problems.append(f"{relative}:{token.line}: {message}")

    dangerous_counts = {name: 0 for name in DANGEROUS_NAMES}
    identifier_strings = 0
    for i, t in enumerate(tokens):
        nxt = _at(tokens, i + 1)
        prev = _at(tokens, i - 1)
        if t.kind == "pound":
            # `#if` and its kin are never in ALLOWED_POUND (6.1: no conditional compilation anywhere).
            if t.text not in ALLOWED_POUND:
                problem(t, f"#{t.text} is not allowed" + (" (6.1)" if t.text in CONDITIONAL_POUND else ""))
            continue
        if t.kind == "attr":
            if t.text not in ALLOWED_ATTRIBUTES:
                problem(t, f"the attribute @{t.text} is not allowed")
            continue
        if t.kind == "regex":
            continue
        if t.kind == "string":
            if role in ("test", "frozen") and any(IDENTIFIER_STRING.search(s) for s in t.segments):
                identifier_strings += 1
                if role == "test":
                    problem(t, "an identifier string of the sample outside the trusted part")
            if "NSPrincipalClass" in t.text:
                problem(t, "NSPrincipalClass is not allowed")
            continue
        if t.kind not in ("ident", "eident"):
            continue
        word = t.text
        if word in DANGEROUS_NAMES:
            allowance = TEST_FILE_DANGEROUS_ALLOWANCES.get((relative.rsplit("/", 1)[-1], word))
            receiver_ok = allowance is not None and _at(tokens, i - 1) is not None and _at(tokens, i - 1).text == "." \
                and _word(_at(tokens, i - 2), allowance[1]) and nxt is not None and nxt.text == "("
            dangerous_counts[word] += 1
            if role == "test" and allowance is not None and not receiver_ok:
                problem(t, f"{word} is allowed here only as {allowance[1]}.{word}(...)")
        if word in FORBIDDEN_NAMES:
            problem(t, f"{word} is not allowed")
        if t.kind == "eident":
            continue  # `class` in backticks is a name, not the keyword
        if word == "import":
            k = i + 1
            if _word(_at(tokens, k), "struct", "class", "enum", "protocol", "typealias", "func", "var", "let"):
                k += 1
            module = _at(tokens, k)
            allowed = ALLOWED_SUPPORT_IMPORTS if role in ("base", "trusted") else ALLOWED_IMPORTS
            if module is None or module.text not in allowed:
                problem(t, f"import {module.text if module else ''} is not allowed (only {sorted(allowed)})")
        if role in ("test", "frozen"):
            if word in FORBIDDEN_IN_TEST_FILES:
                problem(t, f"'{word}' is not allowed outside the trusted part")
            if word == "actor" and nxt is not None and nxt.kind == "ident" and _at(tokens, i + 2) is not None \
                    and _at(tokens, i + 2).text in ("{", ":", "<"):
                problem(t, "an actor is not allowed outside the trusted part")
        if word == "class":
            if nxt is not None and nxt.kind == "ident" and (nxt.text in ("func", "var", "let", "subscript") or nxt.text in MODIFIERS):
                if role != "base":
                    problem(t, f"'class {nxt.text}' is not allowed outside the base file")
                continue
            if prev is not None and prev.kind == "punct" and prev.text in (":", ","):
                continue  # `protocol P: class`
            problems += [f"{relative}:{t.line}: {m}" for m in _class_declaration_problems(tokens, i, role)]
        if word == "extension" and role in ("base", "trusted"):
            target = _at(tokens, i + 1)
            if target is not None and target.text in ("XCTestCase", BASE_CLASS):
                problem(t, f"an extension of {target.text} is not allowed")
        if word == "override" and role != "base":
            shape = [(_at(tokens, i + k).text if _at(tokens, i + k) else "") for k in range(1, 6)]
            ok = shape[0] == "func" and shape[1] in HOOKS and shape[2:4] == ["(", ")"] and \
                (shape[4] == "{" or (shape[4] == "throws" and (_at(tokens, i + 6) and _at(tokens, i + 6).text == "{")))
            if not ok or _word(prev, "static", "class"):
                problem(t, "override is allowed only for 'func setUpAfterGate()' and 'func tearDownAfterGate()'")
        if word == "func" and nxt is not None and nxt.kind in ("ident", "eident") and nxt.text.startswith("test"):
            # XCTest takes only `test*` methods without arguments that return nothing; the trusted part
            # may name a helper `testHost() throws -> TestHost`.
            returns = [(_at(tokens, i + k).text if _at(tokens, i + k) else "") for k in range(2, 7)]
            if not (role in ("base", "trusted") and returns[:2] == ["(", ")"] and
                    ("->" in "".join(returns[2:5]) or returns[2:4] == ["-", ">"] or returns[3:5] == ["-", ">"])):
                problems += [f"{relative}:{t.line}: {m}" for m in _test_method_problems(tokens, i)]

    if role == "frozen":
        expected_counts = FROZEN_DANGEROUS_COUNTS.get(relative, {})
        for name in DANGEROUS_NAMES:
            if dangerous_counts[name] != expected_counts.get(name, 0):
                problems.append(f"{relative}: {name} appears {dangerous_counts[name]} times, the frozen file has "
                                f"{expected_counts.get(name, 0)}")
        if identifier_strings != FROZEN_IDENTIFIER_COUNTS.get(relative, 0):
            problems.append(f"{relative}: {identifier_strings} identifier strings, the frozen file has "
                            f"{FROZEN_IDENTIFIER_COUNTS.get(relative, 0)}")
    elif role == "test":
        name_only = relative.rsplit("/", 1)[-1]
        for name, count in dangerous_counts.items():
            allowed = TEST_FILE_DANGEROUS_ALLOWANCES.get((name_only, name), (0, None))[0]
            if count != allowed and (count or allowed):
                problems.append(f"{relative}: {name} appears {count} times; outside the trusted part it may appear "
                                f"{allowed} times")
    return problems


def _class_declaration_problems(tokens, i, role):
    modifiers, attributes = _preceding_declaration_words(tokens, i)
    name = _at(tokens, i + 1)
    if name is None or name.kind not in ("ident", "eident"):
        return ["a class without a name"]
    k = i + 2
    inherits = []
    while k < len(tokens) and not (tokens[k].kind == "punct" and tokens[k].text == "{"):
        inherits.append(tokens[k].text)
        k += 1
    if role in ("test", "frozen"):
        if modifiers != ["final"] or attributes or inherits != [":", BASE_CLASS]:
            return [f"class {name.text}: only 'final class <Name>: {BASE_CLASS}' is allowed outside the trusted part"]
        return []
    if role == "base" and name.text == BASE_CLASS:
        return [] if inherits == [":", "XCTestCase"] and not attributes and not modifiers else \
            [f"the base class must be 'class {BASE_CLASS}: XCTestCase'"]
    return []


def _test_method_problems(tokens, i):
    name = tokens[i + 1].text
    modifiers, attributes = _preceding_declaration_words(tokens, i)
    after = [(_at(tokens, i + k).text if _at(tokens, i + k) else "") for k in range(2, 6)]
    shape_ok = after[:2] == ["(", ")"] and (after[2] == "{" or after[2:4] == ["throws", "{"])
    problems = []
    if not shape_ok or tokens[i + 1].kind != "ident":
        problems.append(f"{name}: a test method must be 'func {name}()' or 'func {name}() throws' (no async)")
    if modifiers or any(a != "MainActor" for a in attributes):
        problems.append(f"{name}: a test method takes no modifiers and only @MainActor")
    return problems


def check_test_folder(tests_dir, pbxproj_text):
    """6.1 over the whole folder: only Swift files and the declaration table, every Swift file
    under the closed rules, every Support file in the trusted table, no Info.plist switch."""
    root = pathlib.Path(tests_dir)
    problems = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            problems.append(f"{relative}: symbolic links are not allowed in the test folder")
            continue
        if path.is_dir() or path.name == ".DS_Store":
            continue
        if relative == DECLARATIONS_FILE:
            continue
        if path.suffix != ".swift":
            problems.append(f"{relative}: only .swift files and {DECLARATIONS_FILE} are allowed in the test folder")
            continue
        if relative.startswith("Support/") and relative not in TRUSTED_FILES:
            problems.append(f"{relative}: a Support file that is not in the trusted table")
        problems += check_swift_source(relative, path.read_text(encoding="utf-8"))
    problems += pbxproj_problems(pbxproj_text)
    return problems


def pbxproj_problems(pbxproj_text):
    problems = []
    if "NSPrincipalClass" in pbxproj_text:
        problems.append("project.pbxproj mentions NSPrincipalClass")
    blocks = re.findall(r"isa = XCBuildConfiguration;\s*buildSettings = \{(.*?)\n\t\t\t\};", pbxproj_text, re.S)
    ui_blocks = [b for b in blocks if "TEST_TARGET_NAME = MacLibraryExample;" in b]
    if not ui_blocks:
        problems.append("project.pbxproj: the UI test target's build configurations were not found")
    for block in ui_blocks:
        if "GENERATE_INFOPLIST_FILE = YES;" not in block or re.search(r"\bINFOPLIST_FILE\s*=", block):
            problems.append("project.pbxproj: the UI test target must generate its Info.plist (no INFOPLIST_FILE)")
    return problems


# --- Selection (6.3 "選ぶ") and the plan ---------------------------------------------------------

def feature_of_class(name):
    for c, feature in UI_CLASSES + SEPARATE_CLASSES:
        if c == name:
            return feature
    if name in QUALIFICATION_CLASSES:
        return COMMON_FEATURE
    raise RunnerError(f"unknown class {name}")


def in_feature(key, feature):
    return feature is None or feature_of_class(class_of(key)) in (feature, COMMON_FEATURE)


def deferred_reason(key, verified_targets):
    """The reason a test waits on this Mac, or None when every target it presses was checked on 26."""
    entry = MAC_DEFERRED_TESTS.get(key)
    if entry is None:
        return None
    reason, targets = entry
    if all(t in verified_targets for t in targets):
        return None
    return reason


def exclusion_reason(key, categories, where, os_major, allowed, verified_targets, qualification):
    """The ExclusionReason of a test in this environment, or None when it runs. The order is the
    order of 6.3 step 2; the first that applies is the reason."""
    qualification_tests = set().union(*QUALIFICATION_ONLY_TESTS.values())
    if qualification is not None:
        return None if key in QUALIFICATION_ONLY_TESTS[qualification] else "qualificationOnly"
    if key in qualification_tests:
        return "qualificationOnly"
    if key in OS_ONLY_TESTS and OS_ONLY_TESTS[key] != os_major:
        return "osOnly"
    if key in ENVIRONMENT_EXCLUSIONS.get(where, {}):
        return "environmentExclusion"
    if where == "mac":
        if key in VM_ONLY_TESTS or any(c in VM_ONLY_CATEGORIES for c in categories):
            return "vmOnly"
        deferred = deferred_reason(key, verified_targets)
        if deferred:
            return deferred
        if any(c not in allowed for c in categories):
            return "category"
    return None


def select_tests(identifiers, declarations, where, os_major, allowed, feature=None, verified_targets=None,
                 qualification=None):
    """(selected identifiers, excluded [(identifier, categories, reason)]).

    In the VM every category is allowed; only the OS, the environment and the qualification
    stages exclude. On this Mac a test runs only when every category it declares is in --allow, it
    is not VM only, not of another OS, not deferred (its press targets unchecked) and not a
    qualification probe outside --qualification. Tests outside --feature are neither."""
    allowed = set(allowed)
    verified = MAC_VERIFIED_TARGETS if verified_targets is None else frozenset(verified_targets)
    unknown = allowed - set(CATEGORIES)
    if unknown:
        raise RunnerError(f"unknown categories in --allow: {sorted(unknown)}")
    if where == "vm" and allowed:
        raise RunnerError("--allow is for this Mac only (the VM allows every category)")
    if where == "mac" and allowed & set(VM_ONLY_CATEGORIES):
        raise RunnerError(f"VM-only categories cannot be allowed on this Mac: {sorted(allowed & set(VM_ONLY_CATEGORIES))}")
    if where not in ("vm", "mac"):
        raise RunnerError(f"--where must be vm or mac, not {where!r}")
    if qualification is not None and qualification not in QUALIFICATION_ONLY_TESTS:
        raise RunnerError(f"unknown qualification stage {qualification}")
    selected, excluded = [], []
    for identifier in identifiers:
        key = key_from_enumeration_id(identifier)
        if not in_feature(key, feature):
            continue
        categories = declarations[key]
        reason = exclusion_reason(key, categories, where, os_major, allowed if where == "mac" else set(CATEGORIES),
                                  verified, qualification)
        if reason is None:
            selected.append(identifier)
        else:
            excluded.append((identifier, categories, reason))
    return selected, excluded


def build_invocations(identifiers, selected, where, feature=None, name_each_test=False):
    """The xcodebuild runs in the order of 6.3: the permission stage (one test each, a reset
    before each), the classes (the watch first of the notification tests, the notification tests one
    each), the paste privacy stage. In the VM a class is one call naming its selected methods, unless
    --name-each-test; on this Mac every test is its own call.

    `prepare` says what the runner does before the call: `ncreset` (VM: reset the sample's
    notification permission and check it), `ncui` (VM: restart the notification UI), `privacy`
    (VM: the paste privacy preview is set before the stage and removed after it). `after` says
    what follows: `stopMail` (VM)."""
    chosen = set(selected)
    by_class = {}
    for identifier in identifiers:
        by_class.setdefault(class_of(key_from_enumeration_id(identifier)), []).append(identifier)
    one_each = name_each_test or where == "mac"
    invocations = []

    def add(stage, name, cls, tests, prepare=(), after=()):
        if not tests:
            return
        invocations.append({"index": len(invocations), "stage": stage, "name": name, "class": cls,
                            "onlyTesting": list(tests), "expected": [key_from_enumeration_id(i) for i in tests],
                            "timeout": ONE_TEST_TIMEOUT_SECONDS if len(tests) == 1 else CLASS_TIMEOUT_SECONDS,
                            "prepare": list(prepare), "after": list(after)})

    if feature in (None, "Notification"):
        for method in PERMISSION_ORDER:
            identifier = enumeration_id_from_key(f"{PERMISSION_CLASS}/{method}")
            if identifier in chosen:
                add("permission", f"{PERMISSION_CLASS}/{method}", PERMISSION_CLASS, [identifier], prepare=("ncreset",))
        stray = [i for i in by_class.get(PERMISSION_CLASS, []) if i in chosen and
                 method_of(key_from_enumeration_id(i)) not in PERMISSION_ORDER]
        if stray:
            raise RunnerError(f"tests of {PERMISSION_CLASS} outside the permission order: {stray}")
    watch = enumeration_id_from_key(WATCH_TEST)
    watch_first = where == "mac" and watch in chosen
    if watch_first:
        add("watch", WATCH_TEST, class_of(WATCH_TEST), [watch])
    for cls, _ in UI_CLASSES:
        tests = [i for i in by_class.get(cls, []) if i in chosen and not (watch_first and i == watch)]
        if not tests:
            continue
        if cls in NOTIFICATION_CLASSES:
            if cls == "NotificationUITests" and watch in tests:
                tests = [watch] + [t for t in tests if t != watch]
            for n, test in enumerate(tests):
                key = key_from_enumeration_id(test)
                stage = "watch" if test == watch else "ui"
                add(stage, key, cls, [test], prepare=("ncui",) if n == 0 and where == "vm" else ())
            continue
        after = ("stopMail",) if cls == MAIL_CLASS and where == "vm" else ()
        if one_each:
            for n, test in enumerate(tests):
                add("ui", key_from_enumeration_id(test), cls, [test],
                    after=after if n == len(tests) - 1 else ())
        else:
            add("ui", cls, cls, tests, after=after)
    if feature in (None, "Clipboard"):
        tests = [i for i in by_class.get(PRIVACY_CLASS, []) if i in chosen]
        if tests:
            add("privacy", PRIVACY_CLASS, PRIVACY_CLASS, tests, prepare=("privacy",))
    for qualification_class in QUALIFICATION_CLASSES:
        for test in [i for i in by_class.get(qualification_class, []) if i in chosen]:
            add("qualification", key_from_enumeration_id(test), qualification_class, [test])
    return invocations


def only_testing_arguments(invocation):
    """`-only-testing:<name>` for each name. Never empty: without -only-testing every test runs."""
    names = invocation.get("onlyTesting") or []
    if not names:
        raise RunnerError(f"{invocation.get('name')}: refusing to build an xcodebuild call without -only-testing")
    for name in names:
        if not name.startswith(UI_TARGET + "/") or name.count("/") != 2 or not name.endswith("()"):
            raise RunnerError(f"{name}: not one test of {UI_TARGET}")
    return [f"-only-testing:{name}" for name in names]


def unit_only_testing_arguments(plan, index):
    """`-only-testing:` of a unit call. In the VM a whole target; on this Mac only `MacLibraryTests/<suite>`
    of the audited suites the plan recorded, never a whole target (Claude B-10). Never empty."""
    names = plan["unitInvocations"][index]["onlyTesting"]
    if not names:
        raise RunnerError("refusing a unit call without -only-testing")
    for name in names:
        if plan["where"] == "mac":
            target, _, suite = name.partition("/")
            if target != LIBRARY_UNIT_TARGET or not suite or suite not in plan.get("auditSuites", []):
                raise RunnerError(f"{name}: this Mac runs only the audited suites of {LIBRARY_UNIT_TARGET}")
        elif name not in UNIT_TARGETS:
            raise RunnerError(f"{name}: not a unit target")
    return [f"-only-testing:{name}" for name in names]


XCODEBUILD_ACTIONS = ("build-for-testing", "test-without-building", "test", "build", "clean", "archive",
                      "analyze", "installsrc", "install")


def _inside(root, path):
    """A strict, plain path under root: absolute, no empty, `.` or `..` part, no newline."""
    if not root or not path or not path.startswith(root.rstrip("/") + "/") or "\n" in path:
        return False
    return not any(part in ("", ".", "..") for part in path[len(root.rstrip("/")) + 1:].split("/"))


def call_problems(root, arguments, kind, expected_only_testing=()):
    """The xcodebuild arguments of one call on this Mac (iOS `require_own_paths`, Claude A-1, Codex B-2):
    exactly one action (`build-for-testing` for a build, `test-without-building` for a test), each of
    `-derivedDataPath`, `-resultBundlePath` (tests), `-workspace` (builds) and `-xctestrun` (tests)
    exactly once as two arguments with a plain path inside the run's private folder, and for a test the
    `-only-testing:` names exactly the planned ones (Codex A-2: a failed lookup never becomes a full run)."""
    problems = []
    actions = [a for a in arguments if a in XCODEBUILD_ACTIONS]
    want = "build-for-testing" if kind == "build" else "test-without-building"
    if actions != [want]:
        problems.append(f"the call must have exactly the action {want}, it has {actions}")
    needs = {"-derivedDataPath": 1, "-resultBundlePath": 0 if kind == "build" else 1,
             "-workspace": 1 if kind == "build" else 0, "-xctestrun": 0 if kind == "build" else 1}
    for option, count in needs.items():
        positions = [i for i, a in enumerate(arguments) if a == option]
        spelled = [a for a in arguments if a.lower().startswith(option.lower()) and a != option]
        if len(positions) != count or spelled:
            problems.append(f"{option} must appear exactly {count} time(s) as its own argument")
            continue
        for i in positions:
            if i + 1 >= len(arguments) or not _inside(root, arguments[i + 1]):
                problems.append(f"{option} must name a path inside the run's private folder")
    problems += _option_problems(arguments, kind)
    named = [a[len("-only-testing:"):] for a in arguments if a.startswith("-only-testing:")]
    # Any other spelling (-only-testing without the colon, -skip-testing) is refused by _option_problems.
    if kind == "build":
        if named:
            problems.append("a build names no test")
    elif not named or named != list(expected_only_testing):
        problems.append("the -only-testing names differ from the plan's for this call")
    return problems


# The options a call may carry and the values they may take (Claude v2 C-3); None = any value (paths
# are checked above).
CALL_OPTIONS = {
    "build": {"-workspace": None, "-scheme": ("MacLibraryExample", "MacLibrary"),
              "-destination": ("platform=macOS,arch=arm64",), "-derivedDataPath": None},
    "test": {"-xctestrun": None, "-destination": ("platform=macOS,arch=arm64",), "-derivedDataPath": None,
             "-resultBundlePath": None, "-parallel-testing-enabled": ("NO",), "-test-timeouts-enabled": ("YES",),
             "-default-test-execution-time-allowance": ("120",), "-maximum-test-execution-time-allowance": ("240",),
             "-collect-test-diagnostics": ("never",)},
}


def _option_problems(arguments, kind):
    problems = []
    allowed = CALL_OPTIONS[kind]
    i = 0
    while i < len(arguments):
        a = arguments[i]
        if a in XCODEBUILD_ACTIONS or a.startswith("-only-testing:"):
            i += 1
            continue
        if a not in allowed:
            problems.append(f"an argument the runner does not pass: {a.split('=', 1)[0][:40]}")
            i += 1
            continue
        if i + 1 >= len(arguments):
            problems.append(f"{a} without a value")
            break
        if allowed[a] is not None and arguments[i + 1] not in allowed[a]:
            problems.append(f"{a} with a value the runner does not pass")
        i += 2
    if kind == "test" and "-destination" not in arguments:
        problems.append("-destination is missing")
    return problems


def path_symlink_problems(root, arguments):
    """No part of a path the call names, from the private folder down, may be a symlink (iOS A-2)."""
    problems = []
    for i, a in enumerate(arguments[:-1]):
        if a in ("-derivedDataPath", "-resultBundlePath", "-workspace", "-xctestrun"):
            path = arguments[i + 1]
            if not _inside(root, path):
                continue
            current = root.rstrip("/")
            for part in path[len(current) + 1:].split("/"):
                current = current + "/" + part
                if os.path.islink(current):
                    problems.append(f"{a} passes through a symlink")
                    break
    if os.path.islink(root) or os.path.realpath(root) != root:
        problems.append("the private folder is not its own real path")
    return problems


def mac_selection_leaks(names, allowed):
    """The -only-testing names of a run on this Mac that must never run here (a second check, right
    before xcodebuild, of what select_tests excluded)."""
    problems = []
    for name in names:
        key = key_from_enumeration_id(name)
        if key in VM_ONLY_TESTS or key in MAC_DEFERRED_TESTS and deferred_reason(key, MAC_VERIFIED_TARGETS):
            problems.append(f"{key} never runs on this Mac")
    return problems


def unit_invocations(where, audit_suites, unit_keys=None):
    """VM: both unit targets whole (MacLibraryExampleTests and SharePickerPresenterTests are VM only,
    U-29). This Mac: the audited suites of MacLibraryTests only, each named. `expected` is the set of
    tests the enumeration gives for those names (Codex A-8); the results must be exactly that set."""
    keys = list(unit_keys or [])
    if where == "vm":
        return [{"target": t, "onlyTesting": [t], "expected": [k for k in keys if k.split("/", 1)[0] == t]}
                for t in (LIBRARY_UNIT_TARGET, EXAMPLE_UNIT_TARGET)]
    if not audit_suites:
        return []
    names = [f"{LIBRARY_UNIT_TARGET}/{s}" for s in audit_suites]
    return [{"target": LIBRARY_UNIT_TARGET, "onlyTesting": names,
             "expected": [k for k in keys if any(k.startswith(n + "/") for n in names)]}]


def make_plan(where, identifiers, declarations, allowed, feature, os_major, head, mac_tree, trusted_changes,
              unit, audit_state, name_each_test=False, runner_files=None, qualification=None, tables_hash=None,
              declarations_hash=None, lsregister=None, stale=None, unit_keys=None, environment=None,
              baseline=False, prerequisites=None):
    selected, excluded = select_tests(identifiers, declarations, where, os_major, allowed, feature,
                                      qualification=qualification)
    if where == "mac":
        leaked = mac_selection_leaks(selected, allowed)
        if leaked:
            raise RunnerError("; ".join(leaked))
        if not selected:
            raise RunnerError("no test is selected for this Mac; nothing to approve or run")
    if any("notification" in declarations[key_from_enumeration_id(i)] for i in selected) and \
            enumeration_id_from_key(WATCH_TEST) not in selected:
        raise RunnerError("tests that declare notification are selected without the watch N4 (U-20)")
    invocations = build_invocations(identifiers, selected, where, feature, name_each_test)
    named = [k for inv in invocations for k in inv["expected"]]
    if sorted(named) != sorted(key_from_enumeration_id(i) for i in selected) or duplicates(named):
        raise RunnerError("the invocations do not cover exactly the selected tests")
    suites = audit_state.get("suites", []) if audit_state else []
    units = unit_invocations(where, suites, unit_keys) if unit and qualification is None else []
    for u in units:
        if unit_keys is not None and not u["expected"]:
            raise RunnerError(f"the enumeration has no tests for {u['onlyTesting']}")
    unit_excluded = []
    if where == "mac" and unit and qualification is None and audit_state and audit_state.get("expired"):
        unit_excluded = [{"target": LIBRARY_UNIT_TARGET, "reason": "auditExpired"}]
    return {
        "schema": 1, "where": where, "feature": feature, "qualification": qualification, "allow": sorted(allowed),
        "osMajor": os_major, "head": head, "macTree": mac_tree,
        "trustedPart": {"unchanged": not trusted_changes,
                        "changed": [{"file": f, "pinned": p, "actual": a} for f, p, a in trusted_changes]},
        "tablesHash": tables_hash or runner_tables_hash(), "declarationsHash": declarations_hash,
        "auditHash": audit_state.get("hash") if audit_state else None,
        "enumeration": identifiers, "declarations": declarations, "selected": selected,
        "excluded": [{"id": i, "categories": c, "reason": r} for i, c, r in excluded],
        "invocations": invocations, "unitInvocations": units, "unitExcluded": unit_excluded,
        "nameEachTest": name_each_test or where == "mac", "runnerFiles": dict(runner_files or {}),
        "lsregister": lsregister or [], "stale": stale or [], "auditSuites": list(suites),
        "environment": dict(environment or {}), "baseline": bool(baseline),
        "prerequisites": dict(prerequisites if prerequisites is not None else MAC_RUN_PREREQUISITES) if where == "mac" else {},
    }


def runner_tables_hash():
    """One hash over the runner's selection tables (the baseline's `source` and the approval)."""
    tables = {"vmOnly": sorted(VM_ONLY_TESTS), "osOnly": OS_ONLY_TESTS,
              "macDeferred": {k: [v[0], list(v[1])] for k, v in MAC_DEFERRED_TESTS.items()},
              "verified": sorted(MAC_VERIFIED_TARGETS),
              "qualification": {k: sorted(v) for k, v in QUALIFICATION_ONLY_TESTS.items()},
              "environment": ENVIRONMENT_EXCLUSIONS}
    return sha256_bytes(json.dumps(tables, sort_keys=True).encode())


# --- Approval (U-9 pillar 3, 6.3 --dry-run / --approved) --------------------------------------

def plan_digest(plan):
    """SHA-256 of the whole plan in a canonical form (iOS 0d R-19): the approval names exactly
    these invocations, names and expected results."""
    return sha256_bytes(json.dumps(plan, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())


def runner_file_hashes(repo):
    return {relative: file_sha256(pathlib.Path(repo) / relative) for relative in RUNNER_FILES}


def make_approval(plan, created_at=None, approval_id=None):
    if plan["where"] != "mac":
        raise RunnerError("approval lists are for runs on this Mac")
    return {
        "planDigest": plan_digest(plan),
        "runnerFiles": plan.get("runnerFiles", {}),
        "schema": 1,
        "approvalId": approval_id or secrets.token_hex(16),
        "createdAt": created_at or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "feature": plan["feature"], "qualification": plan["qualification"], "allow": plan["allow"],
        "head": plan["head"], "macTree": plan["macTree"], "trustedPart": plan["trustedPart"],
        "tablesHash": plan["tablesHash"], "auditHash": plan["auditHash"],
        "tests": [{"id": i, "categories": plan["declarations"][key_from_enumeration_id(i)]} for i in plan["selected"]],
        "unitTests": [n for u in plan["unitInvocations"] for n in u["onlyTesting"]],
        "excluded": plan["excluded"], "unitExcluded": plan["unitExcluded"],
        "lsregister": plan["lsregister"], "stale": plan["stale"], "environment": plan["environment"],
        "baseline": plan["baseline"], "prerequisites": plan["prerequisites"],
    }


_CREATED_AT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\+00:00|Z)$")


def approval_problems(approval, plan, now=None):
    """The approved list must be exactly the list the runner would write now: the same keys, and
    the same value for each, apart from the ID and the time (iOS 0d R-8). It is good for
    APPROVAL_HOURS after it was written (Claude B-9), and only once every precondition of a run on
    this Mac is recorded as checked (MAC_RUN_PREREQUISITES; Claude B-14, Codex B-5)."""
    if not isinstance(approval, dict) or approval.get("schema") != 1:
        return ["the approval file is not a schema 1 approval list"]
    if plan.get("where") != "mac":
        return ["approvals are for runs on this Mac"]
    problems = []
    if not APPROVAL_ID.match(str(approval.get("approvalId", ""))):
        problems.append("the approval ID is missing or malformed")
    if not _CREATED_AT.match(str(approval.get("createdAt", ""))):
        problems.append("the approval time is missing or malformed")
    expected = make_approval(plan, created_at=approval.get("createdAt"), approval_id=approval.get("approvalId"))
    unknown = sorted(set(approval) - set(expected))
    missing = sorted(set(expected) - set(approval))
    if unknown or missing:
        problems.append(f"the approval's keys differ: unknown {unknown}, missing {missing}")
    for field in sorted(set(expected) & set(approval)):
        if field in ("approvalId", "createdAt"):
            continue
        if approval[field] != expected[field]:
            if field == "tests":
                approved = [t.get("id") if isinstance(t, dict) else t for t in approval[field]]
                selected = [t["id"] for t in expected[field]]
                problems.append(f"the approved tests differ from the selection: approved only "
                                f"{[t for t in approved if t not in selected][:5]}, selected only "
                                f"{[t for t in selected if t not in approved][:5]}"
                                + (", order or categories differ" if sorted(map(str, approved)) == sorted(map(str, selected)) else ""))
            else:
                problems.append(f"{field} differs from the approved list")
    if not plan["trustedPart"]["unchanged"]:
        problems.append("the trusted part changed; this Mac cannot run until its hashes are pinned after a review")
    if _CREATED_AT.match(str(approval.get("createdAt", ""))):
        created = datetime.datetime.fromisoformat(str(approval["createdAt"]).replace("Z", "+00:00"))
        current = now or datetime.datetime.now(datetime.timezone.utc)
        if current - created > datetime.timedelta(hours=APPROVAL_HOURS) or created - current > datetime.timedelta(minutes=5):
            problems.append(f"the approval is older than {APPROVAL_HOURS} hours (or from the future); plan and ask again")
    unchecked = sorted(k for k, v in plan.get("prerequisites", {}).items() if not v)
    if unchecked:
        problems.append(f"preconditions of a run on this Mac are not checked yet: {unchecked}")
    return problems


def ledger_ids(text):
    """The IDs of a ledger. Every line must be `<ID><TAB><time><TAB>mac`; a broken line refuses the
    run (fail closed. iOS 0d R-7)."""
    if text and not text.endswith("\n"):
        raise RunnerError("the approval ledger's last line is incomplete; check it by hand before a run on this Mac")
    ids = []
    for number, line in enumerate(text.splitlines(), 1):
        if not LEDGER_LINE.match(line):
            raise RunnerError(f"the approval ledger has a malformed line {number}; check it by hand")
        ids.append(line.split("\t", 1)[0])
    return ids


def consume_approval(path, approval_id, now=None):
    """Records the ID as used before anything runs on this Mac; an ID already there is refused (an
    approval runs once, and a run that stopped needs a new approval). Under a lock of its own, the
    whole ledger is checked, then written to a temporary file, synced, renamed, and the folder synced."""
    if not APPROVAL_ID.match(approval_id):
        raise RunnerError("malformed approval ID")
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.parent / (path.name + ".lock"), "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise RunnerError("the approval ledger is not a regular file")
        text = path.read_text(encoding="utf-8") if path.exists() else ""
        if approval_id in ledger_ids(text):
            raise RunnerError(f"the approval {approval_id} was already used; run --dry-run and ask again")
        stamp = now or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
        line = f"{approval_id}\t{stamp}\tmac\n"
        if not LEDGER_LINE.match(line[:-1]):
            raise RunnerError("the new ledger line is malformed")
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as out:
                out.write(text + line)
                out.flush()
                os.fsync(out.fileno())
            os.replace(temporary, path)
        except BaseException:
            if os.path.exists(temporary):
                os.unlink(temporary)
            raise
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)


def uncommitted_mac_changes(porcelain):
    """Paths under mac/ that differ from the commit (`git status --porcelain=v1 -uall -- mac`), apart
    from the runner's own output."""
    paths = []
    for line in porcelain.splitlines():
        if not line.strip():
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        path = path.strip('"')
        if not path.startswith(MAC_OUTPUT_PREFIX):
            paths.append(path)
    return paths


# --- The built test bundle's inventory (U-9 pillar 2 (5)) ----------------------------------------

def selrefs_address(load_commands_text):
    """Start of (__DATA*, __objc_selrefs) from `otool -l`."""
    m = re.search(r"sectname __objc_selrefs\s+segname __DATA\w*\s+addr (0x[0-9a-f]+)", load_commands_text)
    if not m:
        raise RunnerError("otool -l has no __objc_selrefs section")
    return int(m.group(1), 16)


def _swift_class_name(objc_name):
    """`_TtC24MacLibraryExampleUITests13DialogUITests` -> `DialogUITests`; plain names stay."""
    m = re.fullmatch(r"_TtC(\d+)(\w+)", objc_name)
    if not m:
        return objc_name
    rest = m.group(2)[int(m.group(1)):]
    m2 = re.fullmatch(r"(\d+)(\w+)", rest)
    if not m2 or len(m2.group(2)) != int(m2.group(1)):
        return objc_name
    return m2.group(2)


def parse_otool_classes(objc_text, load_commands_text):
    """{class address: {"name", "superclass" (address or external name), "selectors"}} from
    `otool -ov`, with relative method list names resolved through __objc_selrefs (iOS 0d 2.5)."""
    lines = objc_text.splitlines()
    selref_base = selrefs_address(load_commands_text)
    selrefs = {}
    in_selrefs = False
    index = 0
    for line in lines:
        if line.startswith("Contents of "):
            in_selrefs = "__objc_selrefs" in line
            index = 0
            continue
        if in_selrefs:
            m = re.match(r"\s+0x[0-9a-f]+ (\S+)$", line)
            if m:
                selrefs[selref_base + 8 * index] = m.group(1)
                index += 1
    classes = {}
    current = None
    section = None
    in_metaclass = False
    in_methods = False
    for line in lines:
        if line.startswith("Contents of "):
            section = line
            current = None
            continue
        if "__objc_classlist" not in (section or ""):
            continue
        m = re.match(r"^[0-9a-f]{16} (0x[0-9a-f]+) (\S+)$", line)
        if m:
            current = {"address": int(m.group(1), 16), "symbol": m.group(2), "name": None,
                       "superclass": None, "selectors": []}
            classes[current["address"]] = current
            in_metaclass = False
            in_methods = False
            continue
        if current is None:
            continue
        if line.startswith("Meta Class"):
            in_metaclass = True
            continue
        if in_metaclass:
            continue
        m = re.match(r"^    superclass (0x[0-9a-f]+)(?: (\S+))?$", line)
        if m:
            address = int(m.group(1), 16)
            current["superclass"] = address if address else (m.group(2) or "")
            continue
        m = re.match(r"^        name\s+0x[0-9a-f]+ (\S+)$", line)
        if m and current["name"] is None:
            current["name"] = _swift_class_name(m.group(1))
            continue
        m = re.match(r"^        (\w+)\s", line)
        if m:
            in_methods = m.group(1) == "baseMethods"
            continue
        if not in_methods:
            continue
        m = re.match(r"^            name\s+0x[0-9a-f]+ \((0x[0-9a-f]+)\)(?: (\S+))?$", line)
        if m:
            slot = int(m.group(1), 16)
            if slot not in selrefs:
                raise RunnerError(f"a method name points outside __objc_selrefs: {m.group(1)}")
            if m.group(2) and m.group(2) != selrefs[slot]:
                raise RunnerError(f"otool's selector {m.group(2)} differs from __objc_selrefs {selrefs[slot]}")
            current["selectors"].append(selrefs[slot])
            continue
        m = re.match(r"^            name\s+0x[0-9a-f]+ (\S+)$", line)
        if m:
            current["selectors"].append(m.group(1))
    return classes


def normalize_test_selector(selector):
    """`test<Name>` and `test<Name>AndReturnError:` -> `test<Name>`; anything else is not a test."""
    if not selector.startswith("test"):
        return None
    if selector.endswith("AndReturnError:"):
        selector = selector[: -len("AndReturnError:")]
    if ":" in selector or not re.fullmatch(r"test[A-Za-z0-9_]*", selector):
        return None
    return selector


def binary_test_keys(classes):
    """`<Class>/<method>` for every XCTestCase subclass of the binary, inherited tests included."""
    def chain(entry):
        seen = []
        while entry is not None:
            if entry["address"] in seen:
                raise RunnerError("a class cycle in the binary")
            seen.append(entry["address"])
            parent = entry["superclass"]
            if isinstance(parent, int):
                entry = classes.get(parent)
                if entry is None:
                    return None, seen
            else:
                return parent, seen
        return None, seen

    keys = []
    for entry in classes.values():
        root, ancestry = chain(entry)
        if root != "_OBJC_CLASS_$_XCTestCase":
            continue
        methods = []
        for address in ancestry:
            for selector in classes[address]["selectors"]:
                normalized = normalize_test_selector(selector)
                if normalized and normalized not in methods:
                    methods.append(normalized)
        keys += [f"{entry['name']}/{m}" for m in methods]
    return keys


def binary_inventory_problems(binary_keys, identifiers):
    problems = []
    if duplicates(binary_keys):
        problems.append(f"the binary repeats tests: {duplicates(binary_keys)}")
    enumerated = {key_from_enumeration_id(i) for i in identifiers}
    only_binary = sorted(set(binary_keys) - enumerated)
    only_enumeration = sorted(enumerated - set(binary_keys))
    if only_binary or only_enumeration:
        problems.append(f"the built tests differ from the VM's enumeration: only in the binary {only_binary}, "
                        f"only in the enumeration {only_enumeration}")
    return problems


# --- VM qualification (6.3 VM step 0) -------------------------------------------------------

def tart_run_problems(ps_lines, vm):
    """The one `tart run <vm>` process of this Mac must have --no-clipboard and neither --dir nor
    --net-bridged. `ps -axo args=` lines; only the tart executable's own process counts."""
    runs = []
    for line in ps_lines.splitlines():
        args = line.split()
        if len(args) < 3:
            continue
        exe = args[0]
        if not (exe.endswith("/tart") or exe == "tart" or exe.endswith("/tart.app/Contents/MacOS/tart")):
            continue
        if args[1] == "run" and args[2] == vm:
            runs.append(args)
    if len(runs) != 1:
        return [f"expected exactly one `tart run {vm}` process, found {len(runs)}"]
    args = runs[0]
    problems = []
    if "--no-clipboard" not in args:
        problems.append("tart run lacks --no-clipboard (the VM would share this Mac's clipboard)")
    for flag in ("--dir", "--net-bridged"):
        if any(a == flag or a.startswith(flag + "=") for a in args):
            problems.append(f"tart run has {flag} (a shared folder or a bridged network)")
    return problems


def vm_qualification(facts):
    """[(item, passed)] of 6.3 step 0 from the facts the shell read; a fact that is missing or
    cannot be read fails its item. The raw values never leave the run (3.4)."""
    def get(name):
        return facts.get(name)

    accounts = get("accounts")
    accounts_ok = isinstance(accounts, list) and bool(accounts)
    if accounts_ok:
        for entry in accounts:
            kind = entry.get("type") if isinstance(entry, dict) else None
            if kind not in VM_ALLOWED_ACCOUNT_TYPES:
                accounts_ok = False
            elif entry.get("authenticated") not in (0, 1, "0", "1"):
                accounts_ok = False
            elif str(entry.get("authenticated")) == "1" and not VM_ALLOWED_ACCOUNT_TYPES[kind]:
                accounts_ok = False
    items = [
        ("tartRunArgs", get("tartProblems") == []),
        ("hvVmmPresent", get("hvVmmPresent") == "1"),
        ("hwModelVirtualMac", isinstance(get("hwModel"), str) and get("hwModel").startswith("VirtualMac")),
        ("osVersion", (get("osVersion"), get("osBuild")) == VM_OS),
        ("noAppleAccount", get("mobileMeAccounts") == "absent"),
        ("accountsOnlySystem", accounts_ok),
        ("noSharedFolder", get("virtiofsMounts") == "0"),
        ("tartIsThePeer", isinstance(get("macAddress"), str) and
         re.fullmatch(r"[0-9a-f]{2}(:[0-9a-f]{2}){5}", get("macAddress").lower()) is not None and
         str(get("tartMacAddress") or "").lower() == get("macAddress").lower()),
        ("xcode", (get("xcodeVersion"), get("xcodeBuild")) == VM_XCODE),
        ("identity", isinstance(get("platformUUID"), str) and
         re.fullmatch(r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", get("platformUUID")) is not None
         and isinstance(get("vmBoottime"), str) and re.fullmatch(r"[1-9][0-9]{8,11}", get("vmBoottime")) is not None),
    ]
    return items


def vm_language_problem(facts, qualification=None):
    """The language is the measuring environment, not the qualification: en-US for normal runs and
    baselines, ja only for the vm-ja stage (6.3 step 0)."""
    language = facts.get("language")
    wanted = "ja" if qualification == "vm-ja" else VM_LANGUAGE
    if language != wanted:
        return f"the VM's language is not {wanted}"
    return None


# --- Output boundary (3.4) --------------------------------------------------------------------

RESULT_KINDS = ("passed", "failed", "skipped")
RECORD_KINDS = ("passed", "failed", "skipped", "excluded", "watchStopped", "notificationStopped", "runStopped")
# The names of the runner's own problems (NTK-RUNNER:<name>); each is written by some path of the runner.
RUNNER_PROBLEMS = ("timeout", "noResult", "destination", "zeroTests", "summary", "unreadableName", "otherBundle",
                   "unknownShape", "readable", "namedSet", "exitCode", "buttonCoverage", "fixture", "privacyRestore",
                   "permissionReset", "missingResult")
# The preconditions the tests name (`NTK-PRECONDITION:<name>`; 3.4). A closed list like StepCode: a name
# outside it is dropped from what leaves the run (Claude C-8).
PRECONDITION_NAMES = ("notAuthorized", "notNotDetermined", "coldStartTiming", "pastePrivacyPreview")
_PUBLIC_TEST = re.compile(r"^(MacLibraryExampleUITests/[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]*"
                          r"|(MacLibraryTests|MacLibraryExampleTests)(/[A-Za-z_][A-Za-z0-9_]*){1,3}"
                          r"|(MacLibraryExampleUITests|MacLibraryTests|MacLibraryExampleTests)(/[A-Za-z0-9_/]+)?#[A-Za-z]+)$")
_PUBLIC_CODE = re.compile(r"^(NTK-STEP:[A-Za-z0-9_-]+|NTK-GATED:[a-z]+|NTK-PRECONDITION:[A-Za-z]+"
                          r"|NTK-INTERRUPTED|NTK-STOP:[A-Za-z]+|NTK-STALE:[a-z]+|NTK-RUNNER:[A-Za-z]+|NTK-RAW:[A-Za-z ]+)$")


def public_codes(message, step_vocabulary_values):
    """The codes of 3.4 found in a failure or skip message, in order and once each; everything else
    in the message is dropped. `NTK-STEP:` passes only with a value of `enum StepCode`."""
    codes = []
    if not message:
        return codes
    for m in re.finditer(r"NTK-STEP:([A-Za-z0-9_-]+)", message):
        if m.group(1) in step_vocabulary_values:
            codes.append(f"NTK-STEP:{m.group(1)}")
    for m in re.finditer(r"NTK-GATED:([a-z]+)", message):
        if m.group(1) in CATEGORIES:
            codes.append(f"NTK-GATED:{m.group(1)}")
    for m in re.finditer(r"NTK-PRECONDITION:([A-Za-z][A-Za-z0-9]{0,40})(?![A-Za-z0-9])", message):
        if m.group(1) in PRECONDITION_NAMES:
            codes.append(f"NTK-PRECONDITION:{m.group(1)}")
    if "NTK-INTERRUPTED" in message:
        codes.append("NTK-INTERRUPTED")
    out = []
    for code in codes:
        if code not in out:
            out.append(code)
    return out


def public_record(record):
    """The record exactly as it may leave the run (3.4), or RunnerError. Only these keys, and each
    value of its allowed form: the test key, the kind, the codes, the seconds, the reason."""
    allowed_keys = {"test", "result", "kind", "codes", "seconds", "reason", "invocation", "runs"}
    if not isinstance(record, dict) or not set(record) <= allowed_keys or "test" not in record or "result" not in record:
        raise RunnerError("a record with keys outside 3.4")
    if not isinstance(record["test"], str) or not _PUBLIC_TEST.match(record["test"]):
        raise RunnerError("a record whose test is not a test key")
    if record["result"] not in RESULT_KINDS:
        raise RunnerError("a record with an unknown result")
    if record.get("kind", record["result"]) not in RECORD_KINDS:
        raise RunnerError("a record with an unknown kind")
    codes = record.get("codes", [])
    if not isinstance(codes, list) or not all(isinstance(c, str) and _PUBLIC_CODE.match(c) for c in codes):
        raise RunnerError("a record with a code outside 3.4")
    for code in codes:
        name = code.split(":", 1)[1] if ":" in code else ""
        if (code.startswith("NTK-PRECONDITION:") and name not in PRECONDITION_NAMES) or \
                (code.startswith("NTK-RUNNER:") and name not in RUNNER_PROBLEMS):
            raise RunnerError("a record with a code outside 3.4")
    if "seconds" in record and not (isinstance(record["seconds"], (int, float)) and record["seconds"] >= 0):
        raise RunnerError("a record with seconds that are not a number")
    if "runs" in record and not (isinstance(record["runs"], int) and record["runs"] >= 1):
        raise RunnerError("a record with runs that are not a count")
    if "reason" in record and record["reason"] not in EXCLUSION_REASONS:
        raise RunnerError("a record with a reason outside ExclusionReason")
    if "invocation" in record and not (isinstance(record["invocation"], str) and
                                       re.fullmatch(r"[A-Za-z0-9_/]+", record["invocation"])):
        raise RunnerError("a record with an invocation name outside 3.4")
    return dict(record)


# --- Results (6.3 "結果の読み方") -----------------------------------------------------------------

KNOWN_CASE_CHILDREN = {"Failure Message"}


def parse_xcresult_tests(text):
    """[{"node", "bundle", "result", "skipReason", "message", "unknownShape", "seconds"}] for every
    Test Case of `xcresulttool get test-results tests`, in order, and the device ids."""
    data = json.loads(text)
    cases = []

    def walk(node, bundle):
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            bundle = node.get("name")
        if node.get("nodeType") == "Test Case":
            children = node.get("children", [])
            messages = [c.get("name", "") for c in children if c.get("nodeType") == "Failure Message"]
            skip = next((m[len("Test skipped - "):] for m in messages if m.startswith("Test skipped - ")), None)
            shapes = sorted({str(c.get("nodeType")) for c in children} - KNOWN_CASE_CHILDREN)
            arguments = sum(1 for c in children if c.get("nodeType") == "Arguments")
            seconds = node.get("durationInSeconds")
            cases.append({"node": node.get("nodeIdentifier", ""), "bundle": bundle, "result": node.get("result", ""),
                          "skipReason": skip if skip is not None else ("" if node.get("result") == "Skipped" else None),
                          "message": "\n".join(messages), "unknownShape": shapes, "arguments": arguments,
                          "seconds": round(float(seconds), 1) if isinstance(seconds, (int, float)) else None})
            return
        for child in node.get("children", []):
            walk(child, bundle)

    for node in data.get("testNodes", []):
        walk(node, None)
    return cases, [d.get("deviceId") for d in data.get("devices", [])]


def destination_ok(tests_text, summary_text=None):
    """Exactly one device, and it is a Mac of arm64 (this Mac or the VM; Claude v2 C-4); a missing platform or
    architecture is not a Mac (Codex v3 B-2). With the summary, its devices name the same device."""
    devices = json.loads(tests_text).get("devices", [])
    if len(devices) != 1 or not isinstance(devices[0], dict):
        return False
    device = devices[0]
    if device.get("platform") != "macOS" or device.get("architecture") != "arm64" or not device.get("deviceId"):
        return False
    if summary_text is not None:
        try:
            configured = [c.get("device", {}).get("deviceId") for c in json.loads(summary_text).get("devicesAndConfigurations", [])]
        except (ValueError, AttributeError):
            return False
        if configured and configured != [device["deviceId"]]:
            return False
    return True


def summary_problems(summary_text, cases):
    summary = json.loads(summary_text)
    counted = {"Passed": "passedTests", "Failed": "failedTests", "Skipped": "skippedTests",
               "Expected Failure": "expectedFailures"}
    problems = []
    if summary.get("totalTestCount") != len(cases):
        problems.append(f"the summary counts {summary.get('totalTestCount')} tests, the test list {len(cases)}")
    for result, field in counted.items():
        n = sum(1 for c in cases if c["result"] == result)
        if summary.get(field, 0) != n:
            problems.append(f"the summary's {field} is {summary.get(field)}, the test list has {n}")
    return problems


def classify(key, result, skip_reason):
    """passed|failed|skipped. Expected Failure, gated, precondition and unlisted skips fail."""
    if result == "Passed":
        return "passed"
    if result == "Skipped":
        reason = skip_reason or ""
        if "NTK-GATED:" in reason or "NTK-PRECONDITION:" in reason:
            return "failed"
        for allowed_key, prefix in INTENDED_SKIPS:
            if key == allowed_key and reason.startswith(prefix):
                return "skipped"
        return "failed"
    return "failed"


def ran_exactly_problems(result_keys, expected_keys):
    """The results must be exactly the named tests: no duplicate, none missing, none extra."""
    problems = []
    if duplicates(result_keys):
        problems.append(f"the results repeat tests: {duplicates(result_keys)}")
    missing = sorted(set(expected_keys) - set(result_keys))
    extra = sorted(set(result_keys) - set(expected_keys))
    if missing:
        problems.append(f"named but not in the results: {missing}")
    if extra:
        problems.append(f"in the results but not named: {extra}")
    if duplicates(expected_keys):
        problems.append(f"the names repeat tests: {duplicates(expected_keys)}")
    return problems


def record_invocation(invocation, tests_text, summary_text, exit_code, timed_out, vocabulary, target=UI_TARGET):
    """The public records (3.4) of one UI xcodebuild run, and whether the run must stop now: no
    result bundle, a time-out, a test case whose name cannot be read or that has a shape the runner
    does not know (iOS 0d R-20), a summary that does not agree, or results that are not exactly the
    named tests. Failure messages stay out; only their codes come through."""
    name = invocation["name"]
    records = []
    stop = False

    def pseudo(problem, stops=True):
        nonlocal stop
        records.append({"test": f"{target}/{name}#{problem}", "result": "failed", "kind": "failed",
                        "codes": [f"NTK-RUNNER:{problem}"]})
        stop = stop or stops

    if timed_out:
        pseudo("timeout")
    if tests_text is None:
        pseudo("noResult")
        return [public_record(r) for r in records], True
    cases, devices = parse_xcresult_tests(tests_text)
    if not destination_ok(tests_text, summary_text):
        pseudo("destination")  # one run is one Mac (this one or the VM); more, none, or not a Mac is not this run
    if not cases:
        pseudo("zeroTests")
    if summary_text is None or summary_problems(summary_text, cases):
        pseudo("summary")
    pairs = []
    for case in cases:
        try:
            key = key_from_node_id(case["node"])
        except RunnerError:
            pseudo("unreadableName")
            continue
        if case["bundle"] != target:
            pseudo("otherBundle")
            continue
        if case["unknownShape"]:
            pseudo("unknownShape")
            continue
        pairs.append((case, key))
    if len(pairs) != len(cases):
        pseudo("readable")
    if ran_exactly_problems([key for _, key in pairs], invocation["expected"]):
        pseudo("namedSet")
    if exit_code != 0 and cases and all(c["result"] in ("Passed", "Skipped") for c in cases):
        pseudo("exitCode", stops=False)
    for case, key in pairs:
        outcome = classify(key, case["result"], case["skipReason"])
        codes = public_codes(case["message"], vocabulary)
        if case["result"] == "Expected Failure":
            codes.append("NTK-RAW:Expected Failure")
        record = {"test": f"{target}/{key}", "result": outcome, "kind": outcome, "codes": codes}
        if case["seconds"] is not None:
            record["seconds"] = case["seconds"]
        records.append(record)
    return [public_record(r) for r in records], stop


UNIT_CASE_CHILDREN = KNOWN_CASE_CHILDREN | {"Arguments"}


def unit_key(target, identifier, enumerated=False):
    """`<suite>[/<nested>]/<test>(<labels>)` (xcresult) or, with `enumerated`, `<target>/<suite>/.../<test>(<labels>)`
    (the enumeration) -> `<target>/<suite>[/<nested>]/<test>`; the same form for both, so they can be compared.
    (A suite may carry its target's name, as `MacLibraryTests/MacLibraryTests/example()`.)"""
    node = identifier[len(target) + 1:] if enumerated else identifier
    node = re.sub(r"\(.*\)$", "", node)
    return f"{target}/" + re.sub(r"[^A-Za-z0-9_/]", "_", node)


def parse_unit_enumeration(text, targets):
    """The unit test keys of an enumeration (`-enumerate-tests ... json`), for the given targets."""
    data = json.loads(text)
    if data.get("errors"):
        raise RunnerError("the enumeration reported errors")
    values = data.get("values")
    if not isinstance(values, list) or len(values) != 1:
        raise RunnerError("the enumeration must have exactly one value")
    if values[0].get("disabledTests"):
        raise RunnerError("the enumeration lists disabled tests")
    keys = []
    for test in values[0].get("enabledTests", []):
        identifier = test.get("identifier", "")
        target = identifier.split("/", 1)[0]
        if target in targets and identifier.count("/") >= 2:
            keys.append(unit_key(target, identifier, enumerated=True))
    return keys


def _argument_problems(case_node):
    """The `Arguments` children of a parameterized test: each has a result that agrees with its case,
    and no child of its own but messages (Codex v2 B-1)."""
    problems = []
    result = case_node.get("result")
    for child in case_node.get("children", []):
        if child.get("nodeType") != "Arguments":
            continue
        if child.get("result") not in ("Passed", "Failed", "Skipped", "Expected Failure"):
            problems.append("unknownShape")
        elif result == "Passed" and child.get("result") != "Passed":
            problems.append("summary")
        if {str(c.get("nodeType")) for c in child.get("children", [])} - KNOWN_CASE_CHILDREN:
            problems.append("unknownShape")
    return problems


def _unit_case_nodes(tests_text):
    data = json.loads(tests_text)
    nodes = []

    def walk(node):
        if node.get("nodeType") == "Test Case":
            nodes.append(node)
            return
        for child in node.get("children", []):
            walk(child)
    for node in data.get("testNodes", []):
        walk(node)
    return nodes


def unit_records(target, tests_text, exit_code, vocabulary, expected=None, summary_text=None):
    """Unit test results as `<target>/<suite>[/<nested suite>]/<test>` (Swift Testing and XCTest alike).
    A parameterized Swift Testing test is one record with `runs`, its expanded count (its `Arguments`
    children, whose values stay out; 6.3 "件数は展開の後の数"). Skips fail like UI skips; the messages
    stay out. With `expected` (the planned keys from the enumeration), the results must be exactly
    that set, each once (Codex A-8); a child that is neither a message nor arguments stops (R-20)."""
    if tests_text is None:
        return [public_record({"test": f"{target}#noResult", "result": "failed", "codes": ["NTK-RUNNER:noResult"]})]
    cases, _ = parse_xcresult_tests(tests_text)
    records, problems = [], []
    if not destination_ok(tests_text, summary_text):
        problems.append("destination")
    if summary_text is not None and summary_problems(summary_text, cases):
        problems.append("summary")
    for node in _unit_case_nodes(tests_text):
        problems += _argument_problems(node)
    for case in cases:
        if case["bundle"] != target:
            problems.append("otherBundle")  # any bundle but the named target (Codex v2 B-1)
            continue
        if set(case["unknownShape"]) - UNIT_CASE_CHILDREN:
            problems.append("unknownShape")
            continue
        key = unit_key(target, case["node"])
        outcome = classify(key, case["result"], case["skipReason"])
        record = {"test": key, "result": outcome, "kind": outcome,
                  "codes": public_codes(case["message"], vocabulary), "runs": max(1, case["arguments"])}
        if case["seconds"] is not None:
            record["seconds"] = case["seconds"]
        records.append(record)
    keys = [r["test"] for r in records]
    if duplicates(keys):
        problems.append("readable")  # two tests fall on one key once their labels are dropped (Claude B-16)
    if expected is not None and (sorted(set(keys)) != sorted(set(expected)) or duplicates(list(expected))):
        problems.append("namedSet")
    if not records:
        problems.append("zeroTests")
    if exit_code != 0 and all(r["result"] == "passed" for r in records):
        problems.append("exitCode")
    for problem in sorted(set(problems)):
        records.append({"test": f"{target}#{problem}", "result": "failed", "codes": [f"NTK-RUNNER:{problem}"]})
    return [public_record(r) for r in records]


STOP_CODES = {"watchStopped": "NTK-STOP:watch", "notificationStopped": "NTK-STOP:notificationUI",
              "runStopped": "NTK-STOP:noResult"}


def not_run_records(invocations, kind):
    """The tests of invocations that were not run because the watch or a notification test failed
    (U-20, 5.0), or because a call returned no result (Codex A-7, Claude A-4): failures, never passes."""
    code = STOP_CODES[kind]
    return [public_record({"test": f"{UI_TARGET}/{k}", "result": "failed", "kind": kind, "codes": [code]})
            for inv in invocations for k in inv["expected"]]


# --- Button coverage (5.7, full VM runs) -----------------------------------------------------

def expected_buttons(sample_sources):
    """`<screen>.button.<name>` for every `enum ButtonName` case of the Dialog, Notification and
    Share identifier enums (`{"dialog": text, ...}`)."""
    buttons = []
    for screen, text in sample_sources.items():
        m = re.search(r"enum ButtonName: String, CaseIterable \{(.*?)\n    \}", text, re.S)
        if not m:
            raise RunnerError(f"no ButtonName enum for {screen}")
        buttons += [f"{screen}.button.{name}" for name in re.findall(r'case \w+ = "(\w+)"', m.group(1))]
    return buttons


def coverage_problems(manifest_entries, attachment_dir, keys_using_sample, buttons):
    """Each test that launches the sample leaves exactly one `ntk-button-coverage-v1.json` (a JSON
    array of unique strings); together they press every button of Dialog, Notification and Share."""
    found = {}
    for entry in manifest_entries:
        try:
            key = key_from_node_id(entry.get("testIdentifier", ""))
        except RunnerError:
            continue
        for attachment in entry.get("attachments", []):
            if COVERAGE_ATTACHMENT.match(attachment.get("suggestedHumanReadableName", "")):
                found.setdefault(key, []).append(attachment["exportedFileName"])
    problems, pressed = [], set()
    for key in keys_using_sample:
        files = found.get(key, [])
        if len(files) != 1:
            problems.append(f"{key}: {len(files)} button coverage attachments, expected exactly 1")
            continue
        try:
            values = json.loads((pathlib.Path(attachment_dir) / files[0]).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            problems.append(f"{key}: the button coverage attachment is not JSON")
            continue
        if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
            problems.append(f"{key}: the button coverage attachment is not an array of strings")
            continue
        if duplicates(values):
            problems.append(f"{key}: the button coverage attachment repeats values")
        pressed |= set(values)
    not_pressed = sorted(set(buttons) - pressed)
    if not_pressed:
        problems.append(f"buttons no test pressed: {not_pressed}")
    return problems


# --- Fixture (U-11) -------------------------------------------------------------------------

FIXTURE_NAME = re.compile(r"^/private/tmp/ntk-uitest-[A-Za-z0-9-]+$")
FIXTURE_ITEMS = ("a.txt", "b.txt", "note.md", "pic.png", "dirA", "dirB", "default.txt")


FIXTURE_CONTENT = {"a.txt": b"a\n", "b.txt": b"b\n", "note.md": b"# note\n", "default.txt": b"default\n",
                   "pic.png": __import__("base64").b64decode(
                       "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")}


def _fixture_root_problem(root):
    """The fixture root must be a real folder of this user, not a symlink (U-11; Codex A-10)."""
    try:
        info = os.lstat(root)
    except OSError:
        return "the fixture is missing"
    import stat
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        return "the fixture root is not a folder of this user"
    return None


def fixture_create(root):
    """Makes the fixture anew: the root and its two folders with mkdir (never reusing one that exists),
    the files with O_CREAT | O_EXCL | O_NOFOLLOW, so nothing is written through a symlink (U-11)."""
    root = str(root)
    if not FIXTURE_NAME.match(root):
        raise RunnerError("the fixture is not the shared temporary folder ntk-uitest-<id>")
    try:
        os.mkdir(root, 0o700)
    except FileExistsError:
        raise RunnerError("the fixture folder already exists; not reusing it")
    problem = _fixture_root_problem(root)
    if problem:
        raise RunnerError(problem)
    for folder in ("dirA", "dirB"):
        os.mkdir(os.path.join(root, folder), 0o700)
    for name, content in FIXTURE_CONTENT.items():
        fd = os.open(os.path.join(root, name), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as out:
            out.write(content)


def fixture_manifest(root):
    """{relative: "dir" | sha256} of the fixture, without following symlinks; `.DS_Store` aside (the
    open panel writes one, 0c 1.7 (3)); a symlink is recorded as such and fails the comparison."""
    root = str(root)
    if not FIXTURE_NAME.match(root):
        raise RunnerError("the fixture is not the shared temporary folder ntk-uitest-<id>")
    problem = _fixture_root_problem(root)
    if problem:
        raise RunnerError(problem)
    manifest = {}
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in sorted(folders + files):
            path = os.path.join(directory, name)
            relative = os.path.relpath(path, root)
            if name == ".DS_Store":
                continue
            if os.path.islink(path):
                manifest[relative] = "symlink"
            elif os.path.isdir(path):
                manifest[relative] = "dir"
            else:
                with open(path, "rb") as f:
                    manifest[relative] = sha256_bytes(f.read())
    return manifest


def fixture_problems(before, after):
    problems = []
    for name in sorted(set(before) | set(after)):
        if before.get(name) != after.get(name):
            problems.append(f"fixture item {name}: {before.get(name, 'absent')} -> {after.get(name, 'absent')}")
    if "symlink" in before.values() or "symlink" in after.values():
        problems.append("the fixture holds a symlink")
    if sorted(n for n in before if "/" not in n) != sorted(FIXTURE_ITEMS):
        problems.append("the fixture did not start with exactly its seven items")
    return problems


# --- LaunchServices (U-21) -------------------------------------------------------------------

def lsregister_copies(dump_text, bundle_ids, run_root, repo_root, derived_root):
    """The registered copies of the sample and the runner (`lsregister -dump`) outside this run's
    folder: [{"path", "mark", "place"}]. `mark` is the first 12 of the SHA-256 of the real path, and
    `place` one of derivedData, repository, applications, other (3.4: the path never leaves)."""
    copies = []
    blocks = re.split(r"\n-{10,}\n", dump_text)
    for block in blocks:
        ident = re.search(r"^identifier:\s+(\S+)", block, re.M)
        path = re.search(r"^path:\s+(.+?)(?: \(0x[0-9a-f]+\))?$", block, re.M)
        if not ident or not path or ident.group(1) not in bundle_ids:
            continue
        p = path.group(1).strip()
        if run_root and (p == run_root or p.startswith(run_root.rstrip("/") + "/")):
            continue
        real = os.path.realpath(p)
        if derived_root and real.startswith(derived_root.rstrip("/") + "/"):
            place = "derivedData"
        elif repo_root and real.startswith(repo_root.rstrip("/") + "/"):
            place = "repository"
        elif real.startswith("/Applications/"):
            place = "applications"
        else:
            place = "other"
        entry = {"path": p, "mark": sha256_bytes(real.encode())[:12], "place": place}
        if entry not in copies:
            copies.append(entry)
    return copies


def copy_mark(app_path):
    """`copy=<12 hex>` of the real path of the app (TEST_RUNNER_NTK_EXPECTED_COPY, U-21)."""
    return "copy=" + sha256_bytes(os.path.realpath(app_path).encode())[:12]


# --- The stopped run's writers (6.3 the Mac step 4) --------------------------------------------

def _under(path, root):
    return bool(path) and bool(root) and path.startswith(root.rstrip("/") + "/")


def stale_plan(marker, boottime_now, processes, tool_roots, folder=None):
    """What to do about a previous run's folder whose marker is left.

    marker: {"boottime", "created", "root", "writers": [{"pid", "start", "exe"}], "pgid"}
    processes: [{"pid", "pgid", "start", "exe"}] of this Mac now (exe is the real path or None).
    tool_roots: the folders of xcodebuild and the XCTest tools (the Xcode apps' Contents).

    Returns {"removeOnly": bool, "signal": [pid], "group": pgid or None, "refuse": reason or None}.
    A marker from an earlier boot: every writer ended, nothing is signalled (PIDs are reused).
    Otherwise a writer is a process whose PID, start time and real executable all match, or whose
    executable is under the previous run's folder and started after the marker was made (a sample
    woken by a notification). The group is signalled only when its leader is a writer and every
    process of the group is a tool or under the folder.

    With `folder` (the folder the marker was found in), the marker's root must be that folder's real
    path and carry the run-folder prefix; otherwise the plan refuses (Claude B-5: a root of `/` would
    make every later process a writer). A missing or unreadable marker is refused by the caller."""
    try:
        boot = int(marker["boottime"])
        created = float(marker["created"])
        root = str(marker["root"])
        writers = list(marker.get("writers", []))
    except (KeyError, TypeError, ValueError, AttributeError):
        return {"removeOnly": False, "signal": [], "group": None, "refuse": "malformed marker", "unverified": []}
    if folder is not None and (os.path.realpath(folder) != root or
                               not os.path.basename(root).startswith(RUN_FOLDER_PREFIX)):
        return {"removeOnly": False, "signal": [], "group": None, "refuse": "the marker names another folder",
                "unverified": []}
    if boot < boottime_now:
        return {"removeOnly": True, "signal": [], "group": None, "refuse": None, "unverified": []}
    if boot > boottime_now:
        return {"removeOnly": False, "signal": [], "group": None, "refuse": "the marker's boot time is later than now",
                "unverified": []}
    if marker.get("launching"):
        return {"removeOnly": False, "signal": [], "group": None, "unverified": [],
                "refuse": "an xcodebuild was started and never recorded; nothing is signalled and the folder stays "
                          "until the Mac restarts"}

    def matches(p, w):
        return p.get("pid") == w.get("pid") and p.get("start") == w.get("start") and p.get("exe") == w.get("exe") \
            and p.get("exe") is not None

    alive = []
    unverified = []
    for p in processes:
        if any(matches(p, w) for w in writers):
            alive.append(p)
        elif _under(p.get("exe"), root) and isinstance(p.get("start"), (int, float)) and p["start"] >= created:
            alive.append(p)
    group = None
    pgid = marker.get("pgid")
    if pgid is not None:
        leader = [p for p in processes if p.get("pid") == pgid]
        members = [p for p in processes if p.get("pgid") == pgid]
        members_ok = bool(members) and all(
            _under(p.get("exe"), root) or any(_under(p.get("exe"), t) for t in tool_roots) for p in members)
        leader_ok = len(leader) == 1 and any(matches(leader[0], w) for w in writers)
        if members_ok and leader_ok:
            group = pgid
        elif not leader and members:
            # A group whose leader is gone cannot be shown to be this run's by the three-way match: it is not
            # signalled as a group, and its members that are not writers shown one by one are reported and
            # keep the folder (review v3: Codex A-2; v4 C-1).
            unverified = sorted(p["pid"] for p in members if p not in alive)
    return {"removeOnly": not alive and not unverified, "signal": sorted(p["pid"] for p in alive), "group": group,
            "refuse": None, "unverified": unverified}


MARKER_NAME = "ntk-run-marker.json"
RUN_FOLDER_PREFIX = "ntk-test-mac."


LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# The copies a run builds and registers with LaunchServices; removed with its folder.
RUN_APPS = ("dd-ui/Build/Products/Debug/MacLibraryExample.app",
            "dd-ui/Build/Products/Debug/MacLibraryExampleUITests-Runner.app")


class OsPort:
    """The operating system as the stale-run and current-run cleanup see it. The self-tests on this Mac
    pass a fake port, so that no real signal, process list or removal is reached (review v1: Codex A-5,
    Claude A-3); the runner passes this one."""

    def processes(self):
        return _processes()

    def boottime(self):
        return _boottime()

    def signal(self, pid, number):
        try:
            os.kill(pid, number)
        except ProcessLookupError:
            pass

    def signal_group(self, pgid, number):
        try:
            os.killpg(pgid, number)
        except ProcessLookupError:
            pass

    def remove(self, folder):
        _remove_run_folder(folder)

    def remove_fixture(self, path):
        _remove_fixture(path)

    def unregister(self, app):
        subprocess.run([LSREGISTER, "-u", app], capture_output=True)

    def sleep(self, seconds):
        time.sleep(seconds)

    def now(self):
        return time.time()


def _identity(process):
    return (process.get("pid"), process.get("start"), _mark(process.get("exe")))


def stop_writers(marker, folder, port, tool_roots, term_wait=30.0, kill_wait=5.0, approved=None):
    """Stops the writers of a run folder: TERM, wait, KILL, wait. The plan is made again right before
    each signal from the process list of that moment (PID, start time and real executable), so a PID that
    ended and was reused in between is never signalled (Codex A-5, v2 A-2). With `approved` (the
    identities a stopped run's approval listed), only those are signalled, one by one, and a process
    that is not among them stops the cleanup instead (review v3: Codex B-1). Returns None when no writer
    is left, or the reason the folder must stay. A group whose leader is gone is never signalled as a group;
    its writers shown one by one (three-way match, or under the folder and started after the marker) are,
    and the members that cannot be shown are not and keep the folder (Codex v3 A-2, v4 C-1)."""
    allowed = None if approved is None else {tuple(a) for a in approved}

    def fresh():
        return stale_plan(marker, port.boottime(), port.processes(), tool_roots, folder)

    def outsider(plan):
        if allowed is None:
            return False
        current = {p["pid"]: p for p in port.processes()}
        return any(pid in current and _identity(current[pid]) not in allowed for pid in plan["signal"])

    for number, wait in ((15, term_wait), (9, kill_wait)):
        plan = fresh()
        if plan["refuse"]:
            return plan["refuse"]
        if not plan["signal"]:
            break
        if outsider(plan):
            return "a process the approval did not list belongs to the stopped run; plan and ask again"
        if plan["group"] is not None and allowed is None:
            port.signal_group(plan["group"], number)
        # Each process is checked again right before its own signal (review v2: Codex A-2): one that ended
        # with the group, or whose number was taken meanwhile, is no longer in the fresh plan.
        for pid in plan["signal"]:
            current = fresh()
            if current["refuse"]:
                return current["refuse"]
            if pid in current["signal"] and not outsider({"signal": [pid]}):
                port.signal(pid, number)
        deadline = port.now() + wait
        while port.now() < deadline:
            if not fresh()["signal"]:
                break
            port.sleep(0.5)
        else:
            continue
        break
    plan = fresh()
    if plan["refuse"]:
        return plan["refuse"]
    if plan["signal"]:
        return "writers are still running"
    if plan["unverified"]:
        # How many, and whether they are Xcode's tools (never their places; review v4: Claude C-4).
        left = [p for p in port.processes() if p.get("pid") in plan["unverified"]]
        tools = sum(1 for p in left if any(_under(p.get("exe"), t) for t in tool_roots))
        return (f"{len(plan['unverified'])} process(es) of the run's xcodebuild group ({tools} of them Xcode tools) "
                "are left whose identity cannot be shown; nothing was signalled to them")
    return None


def clean_run_folder(folder, port, tool_roots, read_marker, approved_entry=None):
    """A run folder of this Mac (a stopped one, or the current one at its end): its marker must be
    there and name it; its writers are stopped and found gone; then its fixture and the folder go.
    Returns None, or the reason nothing was removed (Codex A-6: a folder without a readable marker
    is never removed)."""
    try:
        marker = read_marker(folder)
    except (OSError, ValueError):
        return "the run folder has no readable marker"
    if not isinstance(marker, dict):
        return "the run folder has no readable marker"
    approved = None
    if approved_entry is not None:
        # The marker is the one the approval saw (review v3: Codex B-1).
        if sha256_bytes(json.dumps(marker, sort_keys=True).encode())[:16] != approved_entry.get("marker"):
            return "the stopped run's marker changed after the approval"
        approved = [(w.get("pid"), w.get("start"), w.get("exe")) for w in approved_entry.get("writers", [])]
    problem = stop_writers(marker, folder, port, tool_roots, approved=approved)
    if problem:
        return problem
    for app in RUN_APPS:
        path = os.path.join(folder, app)
        if os.path.isdir(path) and not os.path.islink(path):
            port.unregister(path)
    run_id = str(marker.get("runId", ""))
    if re.fullmatch(r"[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}", run_id):
        port.remove_fixture(f"/private/tmp/ntk-uitest-{run_id}")
    port.remove(folder)
    return None


def writer_entry(pid, processes, expect_under):
    """The marker's entry of a writer once its real executable is under `expect_under` (the Xcode the
    runner calls): a process caught between fork and exec is not recorded (Claude B-4)."""
    found = [p for p in processes if p.get("pid") == pid]
    expect_under = os.path.realpath(expect_under) if expect_under else expect_under
    if len(found) != 1 or not _under(found[0].get("exe"), expect_under):
        return None
    return {"pid": pid, "start": found[0]["start"], "exe": found[0]["exe"], "pgid": found[0]["pgid"]}


# --- U-29: the audit of this Mac's unit tests --------------------------------------------------

def audit_word_counts(text):
    """{word: count} of AUDIT_WORDS in one test file. `.general` counts the scope value only (not the
    `.general` of `NSPasteboard.general`, which has its own word). A word counts as a prefix
    (`NSSharingServicePicker` is an `NSSharingService`; Claude B-11)."""
    counts = {}
    for word, pattern in AUDIT_PATTERNS.items():
        n = len(re.findall(pattern, text))
        if n:
            counts[word] = n
    return counts


def _declares(text, suite):
    return re.search(r"\b(struct|class|enum|actor)\s+" + re.escape(suite) + r"\b", text) is not None


def audit_state(audit, current_tree_hash, file_texts, helper_texts=None):
    """{"suites": [audited suites that may run on this Mac], "expired": bool, "hash", "problems"}.

    The table is expired (no suite on this Mac) when its tree hash is not the current tree's, or its
    review (by another model, naming the same tree hash) is missing. A suite runs only when its file
    declares it, it is listed once and not also under notListed, and every word count of its file
    equals the allowed occurrences the audit wrote. The helper files the suites share (the mocks) must
    match their own allowed occurrences, or nothing runs (Codex B-3, Claude B-11). This is a helper
    check, not the audit itself."""
    problems = []
    if not isinstance(audit, dict) or audit.get("schema") != 1:
        return {"suites": [], "expired": True, "hash": None, "problems": ["the audit is not a schema 1 table"]}
    digest = sha256_bytes(json.dumps(audit, sort_keys=True).encode())
    review = audit.get("review")
    reviewed = isinstance(review, dict) and bool(review.get("by")) and bool(review.get("date")) and \
        review.get("treeHash") == audit.get("treeHash")
    expired = audit.get("treeHash") != current_tree_hash or not reviewed
    if audit.get("treeHash") != current_tree_hash:
        problems.append("the audited tree differs from the current one (expired)")
    if not reviewed:
        problems.append("the audit has no review by another model of this tree yet")
    names = [e.get("suite") for e in audit.get("suites", [])]
    not_listed = {e.get("suite") for e in audit.get("notListed", [])}
    for name in duplicates(names):
        problems.append(f"{name}: listed twice")
    helpers_ok = True
    for entry in audit.get("helpers", []):
        file = entry.get("file")
        text = (helper_texts or {}).get(file)
        allowed = {a["word"]: a["count"] for a in entry.get("allowed", []) if a.get("reason")}
        if text is None or audit_word_counts(text) != allowed:
            problems.append(f"helper {file}: missing, or its words differ from the allowed occurrences")
            helpers_ok = False
    for file in sorted(set(helper_texts or {}) - {e.get("file") for e in audit.get("helpers", [])}):
        if audit_word_counts(helper_texts[file]):
            problems.append(f"helper {file}: not in the table but has audit words")
            helpers_ok = False
    suites = []
    for entry in audit.get("suites", []):
        name, file = entry.get("suite"), entry.get("file")
        if not name or name in not_listed or duplicates(names) and name in duplicates(names):
            problems.append(f"{name}: also under notListed, repeated or unnamed")
            continue
        if file not in file_texts:
            problems.append(f"{name}: its file {file} is missing")
            continue
        if not _declares(file_texts[file], name):
            problems.append(f"{name}: its file {file} does not declare it")
            continue
        counts = audit_word_counts(file_texts[file])
        allowed = {a["word"]: a["count"] for a in entry.get("allowed", []) if a.get("reason")}
        if counts != allowed:
            problems.append(f"{name}: the words of its file {counts} differ from the allowed occurrences {allowed}")
            continue
        suites.append(name)
    if not helpers_ok:
        suites = []
    return {"suites": [] if expired else suites, "expired": expired or not helpers_ok, "hash": digest,
            "problems": problems}


# --- U-30: whether Reply opened the list ---------------------------------------------------------

def _contains(outer, inner):
    ox, oy, ow, oh = outer
    ix, iy, iw, ih = inner
    return ox <= ix and oy <= iy and ix + iw <= ox + ow and iy + ih <= oy + oh


def _expanded(frame, margin):
    x, y, w, h = frame
    return (x - margin, y - margin, w + 2 * margin, h + 2 * margin)


def _frame(value):
    if not isinstance(value, (list, tuple)) or len(value) != 4 or \
            not all(isinstance(v, (int, float)) for v in value) or value[2] < 0 or value[3] < 0:
        return None
    return tuple(float(v) for v in value)


def classify_reply_state(root_before, windows_before, windows_after, fields_after, margin):
    """"list", "banner" or "unknown" (U-30): whether Reply opened the Notification Center list.

    root_before: the frame of the sample's banner root before Reply. windows_*: the frames of the
    notification center's windows in front of the sample's window, before and within 2 s after.
    fields_after: [{"inRoot": bool, "focused": bool}] of the reply fields. Precondition: exactly one
    window before, containing the root and inside the root plus the margin (a banner-sized window).
    "list" when a window was added, or the window holding the root grew past root plus margin.
    "banner" when the count is the same, that window stays inside root plus margin, and exactly one
    focused field is in the root. Anything else, or any value missing, is "unknown"."""
    root = _frame(root_before)
    if root is None or not isinstance(windows_before, list) or not isinstance(windows_after, list) \
            or not isinstance(fields_after, list) or not isinstance(margin, (int, float)) or margin < 0:
        return "unknown"
    before = [_frame(w) for w in windows_before]
    after = [_frame(w) for w in windows_after]
    if any(w is None for w in before + after):
        return "unknown"
    bound = _expanded(root, margin)
    holding_before = [w for w in before if _contains(w, root)]
    if len(before) != 1 or len(holding_before) != 1 or not _contains(bound, holding_before[0]):
        return "unknown"
    if len(after) > len(before):
        return "list"
    holding_after = [w for w in after if _contains(w, root)]
    if len(holding_after) == 1 and not _contains(bound, holding_after[0]):
        return "list"
    if len(after) != len(before) or len(holding_after) != 1:
        return "unknown"
    if not all(isinstance(f, dict) and isinstance(f.get("inRoot"), bool) and isinstance(f.get("focused"), bool)
               for f in fields_after):
        return "unknown"
    focused = [f for f in fields_after if f["inRoot"] and f["focused"]]
    in_root = [f for f in fields_after if f["inRoot"]]
    if len(focused) == 1 and len(in_root) == 1:
        return "banner"
    return "unknown"


# --- Baseline (6.3 "基準のファイル") ---------------------------------------------------------------

def baseline_name(where, os_version):
    if where not in ("vm", "mac") or not re.fullmatch(r"\d+(\.\d+)*", str(os_version)):
        raise RunnerError("a baseline name needs vm|mac and an OS version")
    return f"test_mac.baseline.{where}-{os_version}.json"


def compare_with_baseline(current, baseline_results, in_scope, current_excluded=None, baseline_excluded=None,
                          current_runs=None, baseline_runs=None, baseline_totals=None):
    """(report lines, lost tests). changed / added / removed of the results, and the excluded set and
    reasons that changed (shown for review, never hidden: 6.3 "基準の条件"). A test of this run's
    scope that passed in the baseline and now skipped or did not run is lost coverage."""
    lines, lost = [], []
    changed = sorted(t for t in current.keys() & baseline_results.keys() if current[t] != baseline_results[t])
    added = sorted(current.keys() - baseline_results.keys())
    removed = sorted(baseline_results.keys() - current.keys())
    for t in changed:
        lines.append(f"  CHANGED {t}: {baseline_results[t]} -> {current[t]}")
        if baseline_results[t] == "passed" and current[t] == "skipped":
            lost.append(t)
    for t in added:
        lines.append(f"  ADDED {t}: {current[t]}")
    out_of_scope = 0
    for t in removed:
        if t in in_scope:
            lines.append(f"  REMOVED {t}: {baseline_results[t]} (did not run)")
            if baseline_results[t] == "passed":
                lost.append(t)
        else:
            out_of_scope += 1
    excluded_changes = []
    if current_excluded is not None and baseline_excluded is not None:
        for t in sorted(set(current_excluded) | set(baseline_excluded)):
            if current_excluded.get(t) != baseline_excluded.get(t):
                excluded_changes.append(t)
                lines.append(f"  EXCLUDED {t}: {baseline_excluded.get(t, '-')} -> {current_excluded.get(t, '-')}")
    # The expanded runs of parameterized tests (review v3: Codex A-3): fewer runs of a test is lost coverage
    # even when its key and result are the same; without per-test numbers in an older baseline, the totals
    # per target are compared.
    shrunk = grown = 0
    if current_runs is not None:
        if baseline_runs:
            for t in sorted(set(current_runs) & set(baseline_runs)):
                if current_runs[t] != baseline_runs[t]:
                    lines.append(f"  RUNS {t}: {baseline_runs[t]} -> {current_runs[t]}")
                    if current_runs[t] < baseline_runs[t]:
                        shrunk += 1
                        lost.append(t)
                    else:
                        grown += 1
        for target, total in sorted((baseline_totals or {}).items()):
            now = sum(n for t, n in current_runs.items() if t.split("/", 1)[0] == target)
            if any(t.split("/", 1)[0] == target for t in current_runs) and now != total:
                lines.append(f"  RUNS {target} (all): {total} -> {now}")
                if now < total:
                    shrunk += 1
                    lost.append(f"{target}#expandedRuns")
                else:
                    grown += 1
    header = (f"changed={len(changed)}, added={len(added)}, removed={len(removed) - out_of_scope}, "
              f"outside this run={out_of_scope}, excluded changed={len(excluded_changes)}, fewer runs={shrunk}, "
              f"more runs={grown}")
    return [header] + lines, sorted(set(lost))


def in_run_scope(test, plan):
    """Whether a baseline test belongs to this run: its feature ran, it was not excluded here, and
    unit tests count only when they ran."""
    target, _, key = test.partition("/")
    if target in UNIT_TARGETS:
        return any(u["target"] == target for u in plan.get("unitInvocations", []))
    if target != UI_TARGET or "/" not in key:
        return True
    if any(entry["id"] == enumeration_id_from_key(key) for entry in plan["excluded"]):
        return False
    try:
        feature = feature_of_class(class_of(key))
    except RunnerError:
        return plan["feature"] is None
    return plan["feature"] is None or feature in (plan["feature"], COMMON_FEATURE)


def baseline_counts(results, runs=None):
    """Per target (UI tests per feature): the outcomes of the test keys, and for unit tests the expanded
    runs too (`runs`; review v3: Codex A-3)."""
    counts = {}
    for test, n in (runs or {}).items():
        target = test.split("/", 1)[0]
        bucket = counts.setdefault(target, {})
        bucket["runs"] = bucket.get("runs", 0) + n
    for test, outcome in results.items():
        target = test.split("/", 1)[0].split("#", 1)[0]
        if target == UI_TARGET and "/" in test:
            feature = feature_of_class(test.split("/")[1])
            bucket = counts.setdefault(target, {}).setdefault(feature, {})
        else:
            bucket = counts.setdefault(target, {})
        bucket[outcome] = bucket.get(outcome, 0) + 1
    return counts


def excluded_map(plan):
    """{test or unit target: reason} of what this run excluded; the same for saving and comparing a
    baseline, unit targets included (Codex B-6)."""
    excluded = {key_from_enumeration_id(e["id"]): e["reason"] for e in plan["excluded"]
                if e["reason"] != "qualificationOnly"}
    for u in plan.get("unitExcluded", []):
        excluded[u["target"]] = u["reason"]
    return dict(sorted(excluded.items()))


def completeness_problems(plan, records):
    """Every planned test has exactly one record, every planned unit call has its records, and the
    runner's own checks that belong to this run came back (Codex A-7, Claude A-4): a call that returned
    nothing never passes as an empty success."""
    problems = []
    ui = [r["test"] for r in records if r["test"].startswith(UI_TARGET + "/") and "#" not in r["test"]]
    expected = [f"{UI_TARGET}/{k}" for inv in plan["invocations"] for k in inv["expected"]]
    if duplicates(ui):
        problems.append("a test has more than one record")
    if sorted(set(ui)) != sorted(set(expected)):
        problems.append(f"{len(set(expected) - set(ui))} planned test(s) without a record, "
                        f"{len(set(ui) - set(expected))} record(s) outside the plan")
    for u in plan.get("unitInvocations", []):
        got = [r["test"] for r in records if r["test"].split("/", 1)[0].split("#", 1)[0] == u["target"]
               and "#" not in r["test"]]
        if not got and not any(r["test"].startswith(u["target"] + "#") for r in records):
            problems.append(f"no record of {u['target']}")
        elif "expected" in u and (sorted(set(got)) != sorted(set(u["expected"])) or duplicates(got)):
            problems.append(f"the records of {u['target']} are not exactly its planned tests")
    names = {r["test"] for r in records}
    required = []
    if plan["where"] == "vm":
        required.append(f"{UI_TARGET}#fixture")
        if plan["feature"] is None and plan.get("qualification") is None:
            required.append(f"{UI_TARGET}#buttonCoverage")
    elif "panels" in plan["allow"] and any("panels" in plan["declarations"][key_from_enumeration_id(i)]
                                           for i in plan["selected"]):
        required.append(f"{UI_TARGET}#fixture")
    if any(inv["stage"] == "privacy" for inv in plan["invocations"]):
        required.append(f"{UI_TARGET}#privacyRestore")
    stopped = any(r.get("kind") in ("watchStopped", "notificationStopped", "runStopped") for r in records)
    for name in required:
        if name not in names and not (stopped and name.endswith("#buttonCoverage")):
            problems.append(f"no {name.split('#', 1)[1]} result")
    return problems


def baseline_refusal(env, plan, failed, dirty_mac, executed=None, lost=None):
    """6.3 "基準の条件" (U-32): no failure, every eligible test executed (Codex A-7), nothing lost."""
    if plan.get("qualification"):
        return "a qualification stage is never a baseline"
    if failed:
        return "the run has failures"
    eligible = sorted(key_from_enumeration_id(i) for i in plan["selected"])
    if executed is None or sorted(executed) != eligible:
        return "--baseline needs every eligible test executed exactly once"
    if lost:
        return "tests that passed in the previous baseline did not pass now"
    if plan["where"] == "vm":
        if plan["feature"] is not None or not plan["unitInvocations"]:
            return "--baseline needs a full run in the VM (no --feature, no --skip-unit)"
        if dirty_mac:
            return "--baseline needs mac/ without uncommitted changes"
        if (env.get("os"), env.get("osBuild")) != VM_OS or env.get("language") != VM_LANGUAGE:
            return "the VM is not the baseline environment (15.8.3, en-US)"
        return None
    if sorted(plan["allow"]) != sorted(MAC_CATEGORIES):
        return "--baseline on this Mac needs all seven categories allowed (U-32)"
    if plan["feature"] is not None or not plan["unitInvocations"] or plan["unitExcluded"]:
        return "--baseline on this Mac needs every eligible test and the audited unit tests"
    if dirty_mac:
        return "--baseline needs mac/ without uncommitted changes"
    return None


def make_baseline(env, plan, results, durations, created, runs=None):
    """The baseline of a run. Its runner is the plan's `runnerFiles`: the snapshot the run handed over and
    checked, never the files as they are when it ends (review v4: Codex A-3)."""
    eligible = sorted(key_from_enumeration_id(i) for i in plan["selected"])
    excluded = excluded_map(plan)
    executed = sorted(t.split("/", 1)[1] for t in results if t.startswith(UI_TARGET + "/"))
    return {
        "schema": 1, "createdAt": created,
        "where": plan["where"], "os": env.get("os"), "osBuild": env.get("osBuild"), "arch": env.get("arch"),
        "language": env.get("language"), "xcode": env.get("xcode"), "signing": env.get("signing"),
        "vm": env.get("vm"), "allowed": list(CATEGORIES) if plan["where"] == "vm" else plan["allow"],
        "source": {"head": plan["head"], "macTree": plan["macTree"], "declarations": plan["declarationsHash"],
                   "tables": plan["tablesHash"], "audit": plan["auditHash"],
                   "runnerFiles": dict(plan.get("runnerFiles") or {})},
        "eligible": eligible, "executed": executed, "excluded": excluded,
        "counts": baseline_counts(results, runs), "results": dict(sorted(results.items())),
        "runs": dict(sorted((runs or {}).items())),
        "seconds": dict(sorted(durations.items())),
        "expandedRuns": {t: sum(n for k, n in (runs or {}).items() if k.split("/", 1)[0] == t) for t in UNIT_TARGETS
                         if any(k.split("/", 1)[0] == t for k in (runs or {}))},
    }


def estimate_seconds(keys, durations, default=60.0, per_call=12.0, calls=None):
    """A time estimate for --dry-run: the baseline's seconds of each test (the VM's when this Mac has
    none), a default for a test without one, and a cost per xcodebuild call."""
    total = sum(float(durations.get(k, default)) for k in keys)
    return int(total + per_call * (calls if calls is not None else len(keys)))


# --- What this Mac sees and needs (6.5) --------------------------------------------------------

HAPPENINGS = {
    None: ["The sample app (MacLibraryExample) comes to the front again and again; keep hands off the mouse "
           "and keyboard for the whole run",
           "XCUITest records the screen while the tests run. The runner keeps its DerivedData and result bundles "
           "in a private temporary folder (xcodebuild's TMPDIR too) and deletes it at the end; that Xcode leaves "
           "nothing elsewhere is not confirmed yet: the run counts the new names in $TMPDIR before and after",
           "Every run of the runner, this --dry-run too, first removes the runner's own private temporary folders "
           "that an earlier run killed without its cleanup left behind (their owner is no longer running)",
           "The runner registers its own build of the sample with LaunchServices and removes that registration "
           "at the end"],
    "notification": ["Notifications of the sample appear and play their sound; the sample's notifications are "
                     "removed and its schedule cancelled",
                     "Finder comes to the front (your Finder windows and file names may show)"],
    "settings": ["System Settings opens at the Notifications pane and is closed if it was not open before"],
    "badge": ["The Dock badge of the sample is set to 1 and back to 0"],
    "clipboard": ["The general pasteboard is overwritten with test strings and is not restored (its old "
                  "contents are never read)"],
    "sharepicker": ["The share picker opens over the sample and shows the services; only Escape is pressed"],
    "panels": ["Open and save panels open (first in the folder they used last, showing its file names), then "
               "move to the test folder under /private/tmp"],
    "coldstart": ["The sample is quit and launched again from its notification"],
}
PREPARATIONS = {
    None: ["Unlock the Mac, keep it awake (no screen lock or screen saver) and connected to power",
           "Close or move private windows to another Space",
           "Grant the accessibility and automation access the UI test runner asks for (U-31)"],
    "notification": ["Turn on a Focus that allows only MacLibraryExample, and \"Allow notifications when mirroring "
                     "or sharing the display\" (U-20); turn it back afterwards",
                     "The sample's notifications must already be allowed (the run stops otherwise; U-7)"],
    "clipboard": ["Turn off Handoff and Universal Clipboard for the run (otherwise do not allow clipboard)"],
    "coldstart": ["No extra registered copies of the sample (the list below shows them; remove them yourself, "
                  "--allow-lsregister is not implemented)"],
}


def dry_run_text(plan, durations, now_text):
    """The lines --dry-run prints for the user: what runs and why others do not, what happens on this
    Mac, what to prepare and how long (6.5). Only values of 3.4."""
    lines = []
    allowed = plan["allow"]
    lines.append(f"[dry-run] this Mac, allowed categories: {','.join(allowed) or '(none)'}"
                 + (f", feature {plan['feature']}" if plan["feature"] else "")
                 + (f", qualification {plan['qualification']}" if plan["qualification"] else ""))
    lines.append(f"[dry-run] {len(plan['selected'])} UI tests to run, {len(plan['excluded'])} excluded")
    for inv in plan["invocations"]:
        for key in inv["expected"]:
            categories = plan["declarations"][key]
            label = " (watch)" if inv["stage"] == "watch" else ""
            lines.append(f"  RUN     {key}  [{','.join(categories) or '-'}]{label}")
    for entry in plan["excluded"]:
        lines.append(f"  EXCLUDE {key_from_enumeration_id(entry['id'])}  [{','.join(entry['categories']) or '-'}] "
                     f"{entry['reason']}")
    units = [n for u in plan["unitInvocations"] for n in u["onlyTesting"]]
    lines.append(f"[dry-run] unit tests (U-29): {len(units)} suites named" if units else
                 "[dry-run] unit tests (U-29): none" + (" (the audit is expired or not reviewed)"
                                                         if plan["unitExcluded"] else ""))
    for name in units:
        lines.append(f"  UNIT    {name}")
    used = set(c for i in plan["selected"] for c in plan["declarations"][key_from_enumeration_id(i)])
    lines.append("[dry-run] what happens on this Mac:")
    for category in [None] + [c for c in CATEGORIES if c in used]:
        for text in HAPPENINGS.get(category, []):
            lines.append(f"  - {text}")
    if "panels" in used:
        lines.append("  - The runner makes and deletes the test folder /private/tmp/ntk-uitest-<run id>")
    lines.append("[dry-run] what to prepare:")
    for category in [None] + [c for c in CATEGORIES if c in used]:
        for text in PREPARATIONS.get(category, []):
            lines.append(f"  - {text}")
    if plan["lsregister"]:
        lines.append(f"[dry-run] extra registered copies of the sample or the runner: {len(plan['lsregister'])}")
        for copy in plan["lsregister"]:
            lines.append(f"  COPY    {copy['mark']} ({copy['place']})")
        lines.append("  (to see them yourself: lsregister -dump | grep -B2 -A2 " + SAMPLE_BUNDLE_ID + ")")
    if plan["stale"]:
        alive = sum(len(entry.get("writers", [])) for entry in plan["stale"])
        lines.append(f"[dry-run] stopped runs left {len(plan['stale'])} folder(s)"
                     + (f" and NTK-STALE:alive {alive} process(es)" if alive else "")
                     + "; the approved run stops those processes, then removes the folders and their fixtures")
    unchecked = sorted(k for k, v in plan.get("prerequisites", {}).items() if not v)
    if unchecked:
        lines.append(f"[dry-run] NOT READY: checks in the VM that must come first are not recorded ({', '.join(unchecked)}); "
                     "an approval of this list is refused until they are")
    keys = [k for inv in plan["invocations"] for k in inv["expected"]]
    seconds = estimate_seconds(keys, durations, calls=len(plan["invocations"])) + 300 + 120 * bool(units)
    lines.append(f"[dry-run] time: about {max(1, round(seconds / 60))} minutes (a build of about 5 minutes "
                 f"included; from the baseline's times), planned at {now_text}")
    return lines


# --- Command line -----------------------------------------------------------------------------

def _read(path):
    return pathlib.Path(path).read_text(encoding="utf-8")


def _write_json(path, value):
    pathlib.Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


_PATH_START = re.compile(r"(^|[^A-Za-z0-9._-])(/|~/)")
WITHHELD = "NTK-RUNNER:withheld (a message that named a place was not shown)"


def public_message(text):
    """A message as it may be shown (review v3: Codex A-5). The runner's messages are built from fixed
    words, counts and public names, never places; a message that still holds anything that starts like an
    absolute path is not shown at all, only the fixed code `WITHHELD` (nothing of it is cut out and kept,
    so no part of a place, a name with spaces say, can come through)."""
    text = str(text)
    return WITHHELD if _PATH_START.search(text) else text


def _say(text):
    print(public_message(text))


def _fail(message, code=1):
    print(f"Error: {public_message(message)}", file=sys.stderr)
    return code


def _vocabulary(tests_dir):
    return step_vocabulary(_read(pathlib.Path(tests_dir) / STEP_CODE_FILE))


def cmd_check_sources(args):
    problems = check_test_folder(args.tests_dir, _read(args.pbxproj))
    problems += frozen_file_problems(args.tests_dir)
    for problem in problems:
        _say(f"  FAIL {problem}")
    if problems:
        return _fail(f"{len(problems)} closed source rule violation(s) (design 6.1)")
    print("[sources] the closed source rules pass (design 6.1)")
    return 0


def cmd_hashes(args):
    for relative in sorted(TRUSTED_FILES):
        print(f'    "{relative}": "{file_sha256(pathlib.Path(args.tests_dir) / relative)}",')
    for relative in sorted(FROZEN_FILES):
        print(f'    "{relative}": "{file_sha256(pathlib.Path(args.tests_dir) / relative)}",')
    return 0


def _ps_text(source):
    """`ps -axo args=` comes on stdin (`-`), never through a file: the whole process list of this Mac is
    not written anywhere (Codex A-9, Claude A-2)."""
    if source != "-":
        raise RunnerError("the process list is read from stdin only")
    return sys.stdin.read()


def cmd_tart_check(args):
    """Before every command sent to the VM: the VM still runs with --no-clipboard and without a shared
    folder (Claude B-2: it may have been started again with other arguments)."""
    problems = tart_run_problems(_ps_text(args.ps), args.vm)
    if problems:
        return _fail("the VM's tart run arguments changed: " + "; ".join(problems))
    return 0


def cmd_vm_qualify(args):
    facts = json.loads(_read(args.facts))
    facts["tartProblems"] = tart_run_problems(_ps_text(args.ps), args.vm)
    items = vm_qualification(facts)
    failed = [name for name, ok in items if not ok]
    language = vm_language_problem(facts, args.qualification)
    for name, ok in items:
        print(f"  {'pass' if ok else 'FAIL'} {name}")
    result = {"provenance": VM_PROVENANCE, "items": {name: ok for name, ok in items}}
    _write_json(args.out, result)
    pathlib.Path(args.uuid_out).write_text(f"{facts.get('platformUUID', '')}\t{facts.get('vmBoottime', '')}\n",
                                           encoding="utf-8")
    if failed:
        return _fail(f"the VM is not qualified ({', '.join(failed)}); not running there and not switching to this "
                     "Mac (design 6.3 step 0)")
    if language:
        return _fail(language)
    print(f"[vm] qualified ({VM_PROVENANCE}; {len(items)} items)")
    return 0


def _audit_for(repo, where):
    if where != "mac":
        return None
    audit_path = pathlib.Path(repo) / AUDIT_FILE
    if not audit_path.is_file():
        return {"suites": [], "expired": True, "hash": None, "problems": ["no audit table"]}
    audit = json.loads(_read(audit_path))
    tests_root = pathlib.Path(repo) / "mac/MacLibrary/MacLibraryTests"
    texts = {}
    for entry in audit.get("suites", []):
        file = entry.get("file")
        path = tests_root / str(file)
        if file and path.is_file() and not path.is_symlink():
            texts[file] = _read(path)
    helpers = {p.relative_to(tests_root).as_posix(): _read(p) for p in sorted(tests_root.glob(AUDIT_HELPER_GLOB))}
    return audit_state(audit, tree_hash(repo, AUDIT_TREE_PATHS), texts, helpers)


def _durations(baseline_dir, os_version, where):
    for name in ([baseline_name(where, os_version)] if os_version else []) + [baseline_name("vm", VM_OS[0])]:
        path = pathlib.Path(baseline_dir) / name
        if path.is_file():
            data = json.loads(_read(path))
            return dict(data.get("seconds", {}))  # keyed `<Class>/<method>`, as the plan's `expected`
    return {}


def cmd_preflight(args):
    identifiers = parse_enumeration(_read(args.enumeration))
    declarations_path = pathlib.Path(args.tests_dir) / DECLARATIONS_FILE
    declarations = parse_declarations(_read(declarations_path))
    problems = check_enumeration(identifiers, declarations)
    for problem in problems:
        _say(f"  FAIL {problem}")
    if problems:
        return _fail(f"{len(problems)} problem(s) between the enumeration and the declarations (design 6.3 step 3)")
    print(f"[enumeration] {len(identifiers)} UI tests match {DECLARATIONS_FILE} exactly")
    changes = trusted_part_changes(args.tests_dir)
    for relative, pinned, actual in changes:
        print(f"Warning: the trusted part changed: {relative}", file=sys.stderr)
    if args.where == "mac" and args.runner_files and json.loads(_read(args.runner_files)) != runner_file_hashes(args.repo):
        return _fail("the runner changed after its copy was handed to the VM; run again")
    allowed = [c for c in (args.allow or "").split(",") if c]
    audit = _audit_for(args.repo, args.where)
    if audit:
        for problem in audit["problems"]:
            print(f"[audit] {problem}")
    plan = make_plan(args.where, identifiers, declarations, allowed, args.feature or None, args.os_major, args.head,
                     args.mac_tree, changes, args.unit == "1", audit, args.name_each_test,
                     runner_file_hashes(args.repo) if args.where == "mac" else
                     (json.loads(_read(args.runner_files)) if args.runner_files else None), args.qualification or None,
                     declarations_hash=file_sha256(declarations_path),
                     lsregister=json.loads(_read(args.lsregister)) if args.lsregister else None,
                     stale=json.loads(_read(args.stale)) if args.stale else None,
                     unit_keys=parse_unit_enumeration(_read(args.enumeration), (EXAMPLE_UNIT_TARGET,)) +
                     parse_unit_enumeration(_read(args.unit_enumeration), (LIBRARY_UNIT_TARGET,)),
                     environment={"osVersion": args.os_version, "osBuild": args.os_build, "xcode": args.xcode},
                     baseline=args.baseline, prerequisites=prerequisite_status(args.repo))
    _write_json(args.plan, plan)
    if args.where == "vm":
        print(f"[select] vm: {len(plan['selected'])} UI tests to run, {len(plan['excluded'])} excluded, "
              f"{len(plan['invocations'])} xcodebuild calls")
        for entry in plan["excluded"]:
            print(f"  EXCLUDE {key_from_enumeration_id(entry['id'])} {entry['reason']}")
        return 0
    durations = _durations(args.baseline_dir, args.os_version, "mac")
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="minutes")
    for line in dry_run_text(plan, durations, now):
        print(line)
    if changes and args.dry_run:
        print("[dry-run] THE TRUSTED PART CHANGED: this list cannot run on this Mac until its hashes are pinned "
              "after a review by another model")
    if args.dry_run:
        approval = make_approval(plan)
        _write_json(args.approval_out, approval)
        print(f"[dry-run] approval ID {approval['approvalId']}")
        for problem in git_runner_file_changes(args.repo):
            print(f"[dry-run] {problem.upper()}: the run will refuse until the runner is committed")
        dirty = git_mac_changes(args.repo)
        if dirty:
            print(f"[dry-run] UNCOMMITTED CHANGES UNDER mac/ ({len(dirty)}): the run will refuse until they are "
                  "committed")
        print("[dry-run] show the list above to the user; after approval run again with --approved <that file>")
    return 0


def git_mac_changes(repo):
    finished = subprocess.run(["git", "-C", str(repo), "status", "--porcelain=v1", "-uall", "--", "mac"],
                              capture_output=True, text=True)
    if finished.returncode != 0:
        raise RunnerError("git status failed")
    return uncommitted_mac_changes(finished.stdout)


def git_runner_file_changes(repo):
    """The runner's files that are not committed as they are (iOS 0d R-18)."""
    problems = []
    for relative in RUNNER_FILES:
        tracked = subprocess.run(["git", "-C", str(repo), "ls-files", "--error-unmatch", "--", relative],
                                 capture_output=True, text=True)
        if tracked.returncode != 0:
            problems.append(f"{relative} is not committed")
            continue
        status = subprocess.run(["git", "-C", str(repo), "status", "--porcelain=v1", "--", relative],
                                capture_output=True, text=True)
        if status.returncode != 0 or status.stdout.strip():
            problems.append(f"{relative} differs from the commit")
    return problems


def runner_problems(plan, repo):
    problems = git_runner_file_changes(repo)
    if not plan.get("runnerFiles") or runner_file_hashes(repo) != plan["runnerFiles"]:
        problems.append("the runner files differ from the ones the approved plan was made with")
    return problems


def tree_problems(plan, repo, head):
    problems = []
    if head != plan["head"]:
        problems.append("HEAD differs from the enumeration's")
    if tree_hash(repo, ["mac"]) != plan["macTree"]:
        problems.append("mac/ changed after the enumeration")
    dirty = git_mac_changes(repo)
    if dirty:
        problems.append(f"uncommitted changes under mac/ ({len(dirty)})")
    return problems


def gate_problems(plan, approval, repo, head, ledger):
    """Before every xcodebuild on this Mac: the approved plan unchanged (digest), its ID consumed,
    the runner committed and unchanged, the tree as enumerated (iOS 0d R-18, R-19)."""
    problems = []
    if plan.get("where") != "mac" or not isinstance(approval, dict):
        return ["not an approved plan for this Mac"]
    if plan_digest(plan) != approval.get("planDigest"):
        problems.append("the plan differs from the approved one")
    try:
        consumed = approval.get("approvalId") in ledger_ids(pathlib.Path(ledger).read_text(encoding="utf-8"))
    except (OSError, RunnerError):
        consumed = False
    if not consumed:
        problems.append("the approval was not consumed in the ledger")
    problems += runner_problems(plan, repo)
    if approval.get("runnerFiles") != plan.get("runnerFiles"):
        problems.append("the approval names other runner files")
    return problems + tree_problems(plan, repo, head)


def _head(repo):
    return subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()


def cmd_approve(args):
    plan = json.loads(_read(args.plan))
    try:
        approval = json.loads(_read(args.approved))
    except (OSError, ValueError):
        return _fail("cannot read the approval file")
    problems = approval_problems(approval, plan)
    problems += tree_problems(plan, args.repo, _head(args.repo))
    problems += runner_problems(plan, args.repo)
    for problem in problems:
        _say(f"  FAIL {problem}")
    if problems:
        return _fail("the approval does not match this run; run --dry-run and ask the user again")
    ledger = pathlib.Path(args.ledger_for_self_test) if args.ledger_for_self_test else DEFAULT_LEDGER
    try:
        consume_approval(ledger, approval["approvalId"])
    except RunnerError as e:
        return _fail(str(e))
    print(f"[approval] {approval['approvalId']} matches and is now consumed")
    return 0


def cmd_gate(args):
    plan = json.loads(_read(args.plan))
    approval = json.loads(_read(args.approved))
    ledger = pathlib.Path(args.ledger_for_self_test) if args.ledger_for_self_test else DEFAULT_LEDGER
    problems = gate_problems(plan, approval, args.repo, _head(args.repo), ledger)
    for problem in problems:
        print(public_message(f"  FAIL {problem}"), file=sys.stderr)
    if problems:
        return _fail("not running on this Mac: the approved plan, the runner or the tree changed", 97)
    return 0


def cmd_invocations(args):
    plan = json.loads(_read(args.plan))
    for inv in plan["invocations"]:
        print(f"{inv['index']}\t{inv['stage']}\t{inv['name']}\t{inv['timeout']}\t{','.join(inv['prepare']) or '-'}\t"
              f"{','.join(inv['after']) or '-'}\t{inv['class']}")
    return 0


def cmd_only_testing(args):
    plan = json.loads(_read(args.plan))
    if args.unit is not None:
        for argument in unit_only_testing_arguments(plan, args.unit):
            print(argument)
        return 0
    invocation = plan["invocations"][args.index]
    if plan["where"] == "mac":
        problems = mac_selection_leaks(invocation["onlyTesting"], plan["allow"])
        if problems:
            return _fail("; ".join(problems), 97)
    for argument in only_testing_arguments(invocation):
        print(argument)
    return 0


def cmd_record(args):
    plan = json.loads(_read(args.plan))
    invocation = plan["invocations"][args.index]
    tests_text = _read(args.tests_json) if args.tests_json and pathlib.Path(args.tests_json).is_file() else None
    summary_text = _read(args.summary_json) if args.summary_json and pathlib.Path(args.summary_json).is_file() else None
    records, stop = record_invocation(invocation, tests_text, summary_text, args.exit_code, args.timed_out == "1",
                                      _vocabulary(args.tests_dir))
    for record in records:
        record["invocation"] = re.sub(r"[^A-Za-z0-9_/]", "_", invocation["name"])
        print(json.dumps(public_record(record), ensure_ascii=False))
    return 3 if stop and plan["where"] == "mac" else 0


def cmd_unit_record(args):
    plan = json.loads(_read(args.plan))
    invocation = plan["unitInvocations"][args.index]
    tests_text = _read(args.tests_json) if pathlib.Path(args.tests_json).is_file() else None
    summary_text = _read(args.summary_json) if args.summary_json and pathlib.Path(args.summary_json).is_file() else None
    if summary_text is None and tests_text is not None:
        summary_text = "{}"  # a missing summary is a problem, not a pass
    for record in unit_records(invocation["target"], tests_text, args.exit_code, _vocabulary(args.tests_dir),
                               invocation["expected"], summary_text):
        print(json.dumps(record, ensure_ascii=False))
    return 0


def cmd_check_call(args):
    """Right before an xcodebuild on this Mac: the call's own paths and names (call_problems)."""
    plan = json.loads(_read(args.plan))
    if args.kind == "ui":
        expected = [a[len("-only-testing:"):] for a in only_testing_arguments(plan["invocations"][args.index])]
    elif args.kind == "unit":
        expected = [a[len("-only-testing:"):] for a in unit_only_testing_arguments(plan, args.index)]
    else:
        expected = []
    problems = call_problems(args.root, args.arguments, "build" if args.kind == "build" else "test", expected)
    problems += path_symlink_problems(args.root, args.arguments)
    if args.kind == "ui":
        problems += mac_selection_leaks(plan["invocations"][args.index]["onlyTesting"], plan["allow"])
    for problem in problems:
        print(public_message(f"  FAIL {problem}"), file=sys.stderr)
    return _fail("the xcodebuild call is not the planned one in the private folder", 97) if problems else 0


def cmd_not_run(args):
    plan = json.loads(_read(args.plan))
    rest = [inv for inv in plan["invocations"] if inv["index"] >= args.from_index]
    for record in not_run_records(rest, args.kind):
        print(json.dumps(record, ensure_ascii=False))
    return 0


def cmd_accept(args):
    """Re-checks the records that came back from the VM (or a run on this Mac) against 3.4 before they
    are kept: a line that is not a public record stops the run."""
    count = 0
    with open(args.results, "a", encoding="utf-8") as out:
        for line in sys.stdin:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                record = public_record(json.loads(line))
            except (ValueError, RunnerError) as e:
                return _fail(f"a result line outside 3.4 was refused ({e})", 3)
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
            count += 1
            if record["result"] != "passed":
                codes = " ".join(record.get("codes", []))
                print(f"  {record.get('kind', record['result']).upper()} {record['test']} {codes}".rstrip())
    print(f"  {count} result(s)")
    return 0


def cmd_coverage(args):
    plan = json.loads(_read(args.plan))
    sample = pathlib.Path(args.sample_dir)
    buttons = expected_buttons({"dialog": _read(sample / "DialogSampleView.swift"),
                                "notification": _read(sample / "NotificationSampleView.swift"),
                                "share": _read(sample / "ShareSampleView.swift")})
    keys = [k for inv in plan["invocations"] for k in inv["expected"] if class_of(k) not in NO_SAMPLE_CLASSES]
    merged = []
    for manifest in sorted(pathlib.Path(args.attachments_root).glob("*/manifest.json")):
        for entry in json.loads(_read(manifest)):
            for attachment in entry.get("attachments", []):
                attachment["exportedFileName"] = str(manifest.parent.name + "/" + attachment["exportedFileName"])
            merged.append(entry)
    problems = coverage_problems(merged, args.attachments_root, keys, buttons)
    record = {"test": f"{UI_TARGET}#buttonCoverage", "result": "failed" if problems else "passed",
              "codes": ["NTK-RUNNER:buttonCoverage"] if problems else []}
    print(json.dumps(public_record(record)))
    for problem in problems:
        print(f"  coverage: {problem}", file=sys.stderr)
    return 0


def cmd_check_build(args):
    """The built bundle: its copy of the declarations, its Info.plist, and the tests its binary holds
    against the VM's enumeration (pillar 2 (5); in the VM too, as a check of the reading)."""
    products = pathlib.Path(args.products)
    bundles = [str(p) for p in products.rglob(f"{UI_TARGET}.xctest/Contents/Resources/DeviceRequirements.json")]
    problems = bundle_declaration_problems(pathlib.Path(args.tests_dir) / DECLARATIONS_FILE, bundles)
    infos = [str(p) for p in products.rglob(f"{UI_TARGET}.xctest/Contents/Info.plist")]
    if not infos:
        problems.append(f"no Info.plist in the built {UI_TARGET}.xctest")
    problems += bundle_info_plist_problems(infos)
    identifiers = parse_enumeration(_read(args.enumeration))
    keys = binary_test_keys(parse_otool_classes(_read(args.otool_objc), _read(args.otool_load)))
    problems += binary_inventory_problems(keys, identifiers)
    for problem in problems:
        _say(f"  FAIL {problem}")
    if problems:
        return _fail("the built tests do not match the enumeration (design 6.3)")
    print(f"[binary] the built bundle has the {len(keys)} enumerated tests and the same declarations")
    return 0


def cmd_fixture_manifest(args):
    print(json.dumps(fixture_manifest(args.dir), sort_keys=True))
    return 0


def cmd_fixture_compare(args):
    problems = fixture_problems(json.loads(_read(args.before)), json.loads(_read(args.after)))
    record = {"test": f"{UI_TARGET}#fixture", "result": "failed" if problems else "passed",
              "codes": ["NTK-RUNNER:fixture"] if problems else []}
    print(json.dumps(public_record(record)))
    return 0


def cmd_copy_mark(args):
    print(copy_mark(args.app))
    return 0


def cmd_lsregister(args):
    copies = lsregister_copies(_read(args.dump), (SAMPLE_BUNDLE_ID, RUNNER_BUNDLE_ID), args.run_root,
                               args.repo_root, args.derived_root)
    if args.paths:
        for copy in copies:
            print(copy["path"])
    else:
        _write_json(args.out, [{"mark": c["mark"], "place": c["place"]} for c in copies])
        print(f"[lsregister] {len(copies)} extra registered copies of the sample or the runner")
    return 0


def _processes():
    """[{"pid", "pgid", "start", "exe"}] of this Mac (read only: ps and proc_pidpath)."""
    import ctypes
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
    out = subprocess.run(["/bin/ps", "-axo", "pid=,pgid=,ppid=,lstart="], capture_output=True, text=True,
                         env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"}).stdout
    processes = []
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) != 4:
            continue
        ppid = int(parts[2])
        parts = [parts[0], parts[1], parts[3]]
        try:
            start = int(time.mktime(time.strptime(parts[2].strip(), "%a %b %d %H:%M:%S %Y")))
        except ValueError:
            continue
        buf = ctypes.create_string_buffer(4096)
        exe = None
        if libproc.proc_pidpath(int(parts[0]), buf, 4096) > 0:
            exe = os.path.realpath(buf.value.decode(errors="replace"))
        processes.append({"pid": int(parts[0]), "pgid": int(parts[1]), "ppid": ppid, "start": start, "exe": exe})
    return processes


# The real executables of the system perl the shell starts as /usr/bin/perl (review v4: Codex B-1, Claude C-6).
PERL_EXE = re.compile(r"/usr/bin/perl(5\.[0-9]+)?")


def own_child(pid, parent, processes):
    """Whether the process of that number is now the parent's own child running the system perl (the shell's
    background perl), by its real executable path: only then may the shell signal it (review v3: Codex A-1)."""
    found = [p for p in processes if p.get("pid") == pid]
    return len(found) == 1 and found[0].get("ppid") == parent and \
        PERL_EXE.fullmatch(str(found[0].get("exe") or "")) is not None


def cmd_approval_stale(args):
    """The stopped runs an approval lists, for the approved run's plan (review v3: Codex B-5). The approval
    file is the user's, at a place of theirs: any failure to read it is a fixed message, never its place or
    a traceback (review v4: Codex A-1)."""
    try:
        approval = json.loads(_read(args.approved))
        stale = approval.get("stale") if isinstance(approval, dict) else None
    except (OSError, ValueError, UnicodeDecodeError):
        return _fail("the approval file could not be read as an approval list")
    if stale is not None and not isinstance(stale, list):
        return _fail("the approval file could not be read as an approval list")
    _write_json(args.out, stale)
    return 0


def cmd_own_child(args):
    return 0 if own_child(args.pid, args.parent, _processes()) else 1


def tmp_new_names(before, after):
    """The names in $TMPDIR that a run added, its own folders aside (counted, never listed)."""
    return sorted(n for n in set(after) - set(before)
                  if not n.startswith((RUN_FOLDER_PREFIX, PRIVATE_PREFIX, STAGING_PREFIX)))


def cmd_tmp_names(args):
    """Names only, never contents. `--out`: the names before the run (written into the private folder).
    `--compare`: how many new names the run left (review v3: Claude B-1)."""
    names = sorted(os.listdir(args.dir))
    if args.out:
        _write_json(args.out, names)
        return 0
    added = tmp_new_names(json.loads(_read(args.compare)), names)
    print(f"[tmp] {len(added)} new name(s) in $TMPDIR during the run" + (" (look at them before the next run)" if added else ""))
    return 0


def _boottime():
    out = subprocess.run(["/usr/sbin/sysctl", "-n", "kern.boottime"], capture_output=True, text=True).stdout
    m = re.search(r"sec = (\d+)", out)
    if not m:
        raise RunnerError("cannot read kern.boottime")
    return int(m.group(1))


def record_writer(marker, entry, role):
    """The marker with this writer recorded: its identity, its group, and no longer `launching` (review v4:
    Codex A-2)."""
    marker = dict(marker)
    marker["writers"] = list(marker.get("writers", [])) + [
        {"role": role, "pid": entry["pid"], "start": entry["start"], "exe": entry["exe"]}]
    marker["pgid"] = entry["pgid"]
    marker.pop("launching", None)
    return marker


def cmd_marker(args):
    """Writes or extends the run folder's marker: the run, this boot, and each writer's PID, start time,
    real executable and group (the stopped run's cleanup, 6.3 the Mac step 4). A writer is recorded only
    once its executable is the Xcode the runner calls (Claude B-4); otherwise this fails (exit 1) and the
    caller stops the run."""
    path = pathlib.Path(args.root) / MARKER_NAME
    if args.launching:
        # Written before an xcodebuild starts; only recording it clears this. A folder whose marker still
        # says so may hold an xcodebuild nobody recorded, and is never removed in this boot (review v4:
        # Codex A-2, Claude C-5).
        marker = json.loads(_read(path))
        marker["launching"] = True
    elif args.pid is None:
        marker = {"schema": 1, "runId": args.run_id, "boottime": _boottime(), "created": time.time(),
                  "root": os.path.realpath(args.root), "writers": [], "pgid": None}
    else:
        marker = json.loads(_read(path))
        entry = None
        for _ in range(100):
            entry = writer_entry(args.pid, _processes(), args.expect_under)
            if entry:
                break
            time.sleep(0.1)
        if entry is None:
            return _fail("the writer could not be recorded (not running, or not the expected Xcode)")
        marker = record_writer(marker, entry, args.role)
    tmp = path.with_suffix(".tmp")
    _write_json(tmp, marker)
    os.replace(tmp, path)
    return 0


def _tool_roots():
    return [str(p) + "/Contents" for p in pathlib.Path("/Applications").glob("Xcode*.app")]


def _run_folders(scan_root, current_root):
    folders = []
    for folder in sorted(pathlib.Path(scan_root).glob(RUN_FOLDER_PREFIX + "*")):
        if folder.is_symlink() or not folder.is_dir() or folder.stat().st_uid != os.getuid():
            continue
        if current_root and os.path.realpath(folder) == os.path.realpath(current_root):
            continue
        folders.append(str(folder))
    return folders


def _read_marker(folder):
    return json.loads(_read(pathlib.Path(folder) / MARKER_NAME))


STALE_HINT = ("look for folders whose names start with `ntk-test-mac.` in your temporary folder ($TMPDIR); "
              "each holds ntk-run-marker.json. If it stays because processes of its xcodebuild could not be shown "
              "or stopped, restart the Mac (the next run then removes the folder) or look at the processes "
              "yourself (Activity Monitor) before planning again")


def _mark(text):
    return sha256_bytes(str(text).encode())[:12]


def stale_entry(folder, marker, plan):
    """What the approval fixes about one previous run folder (review v2: Codex A-3): the folder (an
    opaque mark of its real path), its run ID, a digest of its marker, and each process to stop by PID,
    start time and an opaque mark of its executable. Not a count, so another folder with as many
    processes is not the same entry."""
    return {"folder": _mark(os.path.realpath(folder)), "runId": str(marker.get("runId", "")),
            "marker": sha256_bytes(json.dumps(marker, sort_keys=True).encode())[:16],
            "writers": sorted(({"pid": p["pid"], "start": p["start"], "exe": _mark(p.get("exe"))}
                               for p in plan["processes"]), key=lambda w: (w["pid"], w["start"]))}


def stale_listing(folders, port, tool_roots, read_marker):
    """The entries of the previous run folders (stale_entry), or RunnerError when a folder has no
    readable marker or its marker cannot be trusted (Codex A-6). The message says where to look
    without naming the place (Claude v2 B-3)."""
    listing = []
    boot = port.boottime()
    for folder in folders:
        try:
            marker = read_marker(folder)
        except (OSError, ValueError):
            raise RunnerError("NTK-STALE:refused a previous run folder has no readable marker; check it by hand: "
                              + STALE_HINT)
        processes = port.processes()
        plan = stale_plan(marker, boot, processes, tool_roots, folder)
        if plan["refuse"]:
            raise RunnerError(f"NTK-STALE:refused a previous run folder's marker cannot be trusted ({plan['refuse']}): "
                              + STALE_HINT)
        plan["processes"] = [p for p in processes if p["pid"] in plan["signal"]]
        listing.append(stale_entry(folder, marker, plan))
    return sorted(listing, key=lambda e: e["folder"])


def stale_changes(approved, now):
    """Problems between the approved entries and the ones of now. A folder that went away, or a process
    that ended, is fine; a new folder, another marker or run, or a process not in the approval is not."""
    if not isinstance(approved, list):
        return ["the approved list of stopped runs is missing"]
    by_folder = {e.get("folder"): e for e in approved if isinstance(e, dict)}
    problems = []
    for entry in now:
        was = by_folder.get(entry["folder"])
        if was is None:
            problems.append("a stopped run folder that was not approved")
            continue
        if (was.get("runId"), was.get("marker")) != (entry["runId"], entry["marker"]):
            problems.append("a stopped run folder whose marker changed")
        approved_writers = [(w.get("pid"), w.get("start"), w.get("exe")) for w in was.get("writers", [])]
        for w in entry["writers"]:
            if (w["pid"], w["start"], w["exe"]) not in approved_writers:
                problems.append("a process to stop that was not approved")
    return problems


def cmd_stale(args):
    """Previous run folders of this Mac. `--list` writes the entries --dry-run puts into the approval;
    `--stop` runs only with a consumed approval whose plan holds those entries (the same gate as every
    xcodebuild), checks that nothing new is there, then stops the writers and removes each folder, its
    registrations and its fixture (review v2: Codex A-3). Exactly one of the two."""
    if args.list == args.stop:
        return _fail("give exactly one of --list and --stop")
    port = OsPort()
    tools = _tool_roots()
    folders = _run_folders(args.scan_root, args.current_root)
    listing = stale_listing(folders, port, tools, _read_marker)
    if args.list:
        _write_json(args.out, listing)
        alive = sum(len(x["writers"]) for x in listing)
        if alive:
            print(f"NTK-STALE:alive {alive} process(es) of a stopped run")
        return 0
    if not (args.plan and args.approved and args.repo):
        return _fail("--stop needs --plan, --approved and --repo")
    plan = json.loads(_read(args.plan))
    approval = json.loads(_read(args.approved))
    ledger = pathlib.Path(args.ledger_for_self_test) if args.ledger_for_self_test else DEFAULT_LEDGER
    problems = gate_problems(plan, approval, args.repo, _head(args.repo), ledger)
    problems += stale_changes(plan.get("stale"), listing)
    if problems:
        return _fail("NTK-STALE:changed the stopped runs or the approval differ; plan and ask again")
    by_folder = {e.get("folder"): e for e in plan.get("stale") or [] if isinstance(e, dict)}
    for folder in folders:
        entry = by_folder.get(_mark(os.path.realpath(folder)))
        if entry is None:
            return _fail("NTK-STALE:changed a stopped run folder that was not approved")
        problem = clean_run_folder(folder, port, tools, _read_marker, entry)
        if problem:
            return _fail(f"NTK-STALE:alive a stopped run's folder stays ({problem})")
        print("[stale] a stopped run's folder was removed")
    return 0


def current_run_problem(marker, approval, ledger_text):
    """The current run's folder is cleaned only as the run its approval made: the marker names that
    approval, and the approval was consumed (review v2: Codex A-3)."""
    if not isinstance(marker, dict) or not isinstance(approval, dict):
        return "no marker or no approval"
    if not APPROVAL_ID.match(str(marker.get("approvalId", ""))) or marker.get("approvalId") != approval.get("approvalId"):
        return "the marker does not name this run's approval"
    try:
        if marker["approvalId"] not in ledger_ids(ledger_text):
            return "the approval was not consumed"
    except RunnerError:
        return "the approval ledger cannot be read"
    return None


def cmd_stop_current(args):
    """The end of a run on this Mac: the folder must be the one the approval made (its marker names the
    consumed approval), its writers stopped and found gone by the same three-way match, then its
    registrations, fixture and folder removed; otherwise nothing is removed and the run fails (Codex A-4)."""
    root = os.path.realpath(args.root)
    if not os.path.basename(root).startswith(RUN_FOLDER_PREFIX):
        return _fail("not a run folder")
    ledger = pathlib.Path(args.ledger_for_self_test) if args.ledger_for_self_test else DEFAULT_LEDGER
    try:
        marker = _read_marker(root)
        approval = json.loads(_read(pathlib.Path(root) / "approval.approved.json"))
        ledger_text = ledger.read_text(encoding="utf-8") if ledger.exists() else ""
    except (OSError, ValueError):
        return _fail("the run's private folder stays: no readable marker or approval; " + STALE_HINT)
    problem = current_run_problem(marker, approval, ledger_text)
    if problem:
        return _fail(f"the run's private folder stays ({problem}); " + STALE_HINT)
    problem = clean_run_folder(root, OsPort(), _tool_roots(), _read_marker)
    if problem:
        return _fail(f"the run's private folder stays because its writers did not stop ({problem}); its place is not shown")
    return 0


STAGING_PREFIX = "ntk-test-mac-staging."


def make_run_folder(scan_root, run_id, approval_id, boottime, now, copies=None):
    """The private run folder, complete before it exists under its name (review v3: Codex B-3): a staging
    folder (another prefix) gets the marker naming the consumed approval, the copies of the plan and the
    approval (read only), and the folder for xcodebuild's TMPDIR; then one rename gives it the run-folder
    name. A run killed before the rename leaves only a staging folder, which `private --clean` removes."""
    if not re.fullmatch(r"[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}", run_id) or not APPROVAL_ID.match(approval_id):
        raise RunnerError("malformed run ID or approval ID")
    staging = os.path.realpath(tempfile.mkdtemp(prefix=STAGING_PREFIX, dir=scan_root))
    root = os.path.join(os.path.dirname(staging), RUN_FOLDER_PREFIX + os.path.basename(staging)[len(STAGING_PREFIX):])
    if os.path.lexists(root):
        raise RunnerError("the run folder name is taken")
    marker = {"schema": 1, "runId": run_id, "approvalId": approval_id, "boottime": boottime, "created": now,
              "root": root, "writers": [], "pgid": None}
    _write_json(pathlib.Path(staging) / MARKER_NAME, marker)
    os.mkdir(os.path.join(staging, "tmp"), 0o700)
    for name, source in (copies or {}).items():
        target = os.path.join(staging, name)
        shutil.copyfile(source, target)
        os.chmod(target, 0o444)
    os.rename(staging, root)
    return root


def cmd_make_run_folder(args):
    approval = json.loads(_read(args.approved))
    ledger = pathlib.Path(args.ledger_for_self_test) if args.ledger_for_self_test else DEFAULT_LEDGER
    if approval.get("approvalId") not in ledger_ids(ledger.read_text(encoding="utf-8") if ledger.exists() else ""):
        return _fail("the approval was not consumed; no run folder")
    copies = {"approval.approved.json": args.approved}
    if args.plan:
        copies["plan.approved.json"] = args.plan
    print(make_run_folder(args.scan_root, args.run_id, approval["approvalId"], _boottime(), time.time(), copies))
    return 0


PRIVATE_PREFIX = "ntk-test-mac-private."
OWNER_NAME = "owner.json"


def orphaned_private_folders(folders, owners, processes, now, grace=120.0):
    """The private folders (VM facts, LaunchServices dumps) a run killed without its trap left (Claude v2
    B-3): those whose owner (the runner's shell: PID and start time) is no longer running. A folder
    without an owner file counts only once it is older than `grace` (a run that is just starting)."""
    alive = {(p.get("pid"), p.get("start")) for p in processes}
    out = []
    for folder in folders:
        owner, made = owners.get(folder, (None, None))
        if owner is None:
            if made is not None and now - made > grace:
                out.append(folder)
        elif (owner.get("pid"), owner.get("start")) not in alive:
            out.append(folder)
    return out


def cmd_private(args):
    """`--own <pid>`: record the runner's shell as the owner of its private folder. Otherwise: remove the
    private folders of earlier runs of this user that their owner left behind, and run folders a run killed
    before it renamed them (staging folders; no owner, older than the grace)."""
    if args.own is not None:
        found = [p for p in _processes() if p["pid"] == args.own]
        if len(found) != 1:
            return _fail("the owner is not running")
        _write_json(pathlib.Path(args.dir) / OWNER_NAME, {"pid": found[0]["pid"], "start": found[0]["start"]})
        return 0
    folders, owners = [], {}
    current = os.path.realpath(args.dir) if args.dir else None
    scan = pathlib.Path(args.scan_root)
    for folder in sorted(list(scan.glob(PRIVATE_PREFIX + "*")) + list(scan.glob(STAGING_PREFIX + "*"))):
        if folder.is_symlink() or not folder.is_dir() or folder.stat().st_uid != os.getuid() \
                or os.path.realpath(folder) == current:
            continue
        try:
            owner = json.loads(_read(folder / OWNER_NAME))
        except (OSError, ValueError):
            owner = None
        folders.append(str(folder))
        owners[str(folder)] = (owner, folder.stat().st_mtime)
    removed = 0
    for folder in orphaned_private_folders(folders, owners, _processes(), time.time()):
        subprocess.run(["/bin/rm", "-rf", "--", folder], check=True)
        removed += 1
    if removed:
        print(f"[private] removed {removed} private folder(s) an earlier run left")
    return 0


def _remove_run_folder(folder):
    folder = pathlib.Path(folder)
    if folder.is_symlink() or not folder.is_dir() or folder.stat().st_uid != os.getuid() \
            or not folder.name.startswith(RUN_FOLDER_PREFIX):
        raise RunnerError("refusing to remove a folder that is not a run folder of this user")
    subprocess.run(["/bin/rm", "-rf", "--", str(folder)], check=True)


def _remove_fixture(path):
    if not FIXTURE_NAME.match(path) or not os.path.lexists(path):
        return
    if _fixture_root_problem(path):
        raise RunnerError("refusing to remove a fixture that is not a folder of this user")
    subprocess.run(["/bin/rm", "-rf", "--", path], check=True)


def cmd_fixture_create(args):
    fixture_create(args.dir)
    return 0


def cmd_audit_check(args):
    state = _audit_for(args.repo, "mac")
    for problem in state["problems"]:
        print(f"  {problem}")
    print(f"[audit] {len(state['suites'])} suites may run on this Mac; expired={state['expired']}")
    return 0


def cmd_audit_hash(args):
    print(tree_hash(args.repo, AUDIT_TREE_PATHS))
    return 0


def copy_tree_hash(root):
    """The tree hash of a copy of `mac/` (the files `git_file_list` gave, copied with tar): the same
    form as tree_hash, so a copy can be compared with the approved tree (Claude B-12)."""
    root = pathlib.Path(root)
    digest = hashlib.sha256()
    entries = []
    for directory, folders, files in os.walk(root / "mac", followlinks=False):
        for name in files + [f for f in folders if os.path.islink(os.path.join(directory, f))]:
            path = pathlib.Path(directory) / name
            if name == ".DS_Store":
                continue
            entries.append((path.relative_to(root).as_posix(), path))
    for relative, path in sorted(entries):
        content = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
        digest.update(relative.encode() + b"\0" + sha256_bytes(content).encode() + b"\n")
    return digest.hexdigest()


def cmd_tree_hash(args):
    print(copy_tree_hash(args.dir) if args.dir else tree_hash(args.repo, ["mac"]))
    return 0


def cmd_file_list(args):
    """The files of mac/ that go to the VM and into this Mac's copy, NUL separated."""
    sys.stdout.write("".join(name + "\0" for name in git_file_list(args.repo, ["mac"])))
    return 0


def cmd_summary(args):
    plan = json.loads(_read(args.plan))
    env = json.loads(_read(args.environment))
    results = [json.loads(line) for line in open(args.results, encoding="utf-8") if line.strip()]
    counts = {}
    for r in results:
        counts[r["result"]] = counts.get(r["result"], 0) + 1
    print(f"[summary] {len(results)} results: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    for r in results:
        if r["result"] == "failed":
            print(f"  FAILED {r['test']} {' '.join(r.get('codes', []))}".rstrip())
    for entry in plan["excluded"]:
        print(f"  EXCLUDED {key_from_enumeration_id(entry['id'])}: {entry['reason']}")
    for entry in plan.get("unitExcluded", []):
        print(f"  EXCLUDED {entry['target']}: {entry['reason']}")
    failed = bool(counts.get("failed"))
    for problem in completeness_problems(plan, results):
        print(f"  FAILED (incomplete) {problem}")
        failed = True
    current = {r["test"]: r["result"] for r in results if "#" not in r["test"]}
    durations = {r["test"].split("/", 1)[1]: r["seconds"] for r in results
                 if "#" not in r["test"] and r["test"].startswith(UI_TARGET + "/") and "seconds" in r}
    if plan["where"] == "mac" and args.approved:
        approval = json.loads(_read(args.approved))
        ran = sorted(enumeration_id_from_key(t.split("/", 1)[1]) for t in current if t.startswith(UI_TARGET + "/"))
        approved = sorted(t["id"] for t in approval.get("tests", []))
        if ran != approved:
            print("[approval] FAILED: the tests that ran differ from the approved list")
            failed = True
    excluded_now = excluded_map(plan)
    baseline_path = pathlib.Path(args.baseline_dir) / baseline_name(plan["where"], env["os"])
    compare_path = baseline_path if baseline_path.is_file() else latest_baseline(args.baseline_dir, plan["where"])
    lost = []
    if compare_path is not None and compare_path != baseline_path:
        print(f"[baseline] none for this OS version; comparing with {compare_path.name} (another version)")
    if compare_path is not None:
        baseline = json.loads(_read(compare_path))
        in_scope = {t for t in baseline["results"] if in_run_scope(t, plan)}
        lines, lost = compare_with_baseline(current, baseline["results"], in_scope, excluded_now,
                                            baseline.get("excluded", {}) if plan["feature"] is None else None,
                                            *runs_to_compare(results, baseline))
        print(f"[baseline] {compare_path.name}: {lines[0]}")
        for line in lines[1:]:
            print(line)
        if lost:
            print(f"[baseline] FAILED: {len(lost)} test(s) that passed in the baseline skipped, did not run or ran "
                  f"fewer arguments: {lost}")
    else:
        print(f"[baseline] none ({baseline_path.name})")
    failed = failed or bool(lost)
    if args.save_baseline:
        executed = [t.split("/", 1)[1] for t in current if t.startswith(UI_TARGET + "/")]
        refusal = baseline_refusal(env, plan, failed, bool(git_mac_changes(args.repo)), executed, lost)
        if refusal is None and snapshot_changed(args.repo, plan):
            refusal = "mac/ or HEAD changed after the run was planned (review v3: Codex A-4)"
        if refusal is None and runner_changed(args.repo, plan):
            refusal = "the runner is not the one the run used (review v4: Codex A-3)"
        if refusal:
            print(f"[baseline] not saved: {refusal}")
            return 1
        if baseline_path.is_file():
            old = json.loads(_read(baseline_path))
            dated = baseline_path.with_name(baseline_path.name[:-len(".json")] + "." +
                                            str(old.get("createdAt", "undated"))[:10] + ".json")
            if dated.exists():
                return _fail(f"{dated.name} exists; not overwriting an earlier baseline")
            os.replace(baseline_path, dated)
            print(f"[baseline] the previous baseline is kept as {dated.name}")
        created = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
        _write_json(baseline_path, make_baseline(env, plan, current, durations, created, unit_runs(results)))
        print(f"[baseline] saved {baseline_path.name}")
    return 1 if failed else 0


def unit_runs(results):
    """{unit test: its expanded runs} of the records (review v3: Codex A-3)."""
    return {r["test"]: r.get("runs", 1) for r in results
            if "#" not in r["test"] and r["test"].split("/", 1)[0] in UNIT_TARGETS}


def runs_to_compare(results, baseline):
    """(this run's runs, the baseline's per-test runs, the baseline's totals per target): the totals only
    for an older baseline without per-test numbers."""
    return unit_runs(results), baseline.get("runs"), ({} if baseline.get("runs") else baseline.get("expandedRuns", {}))


def runner_changed(repo, plan):
    """Whether the runner files are not the ones the run used: the plan's `runnerFiles` (the snapshot handed
    to the VM and checked there; on this Mac, the committed files the gate checked) must be there and be what
    the repository holds now, so a baseline names the runner that made it (review v4: Codex A-3)."""
    return not plan.get("runnerFiles") or runner_file_hashes(repo) != plan["runnerFiles"]


def runner_snapshot_hashes(folder):
    """{runner file: sha256} of a flat copy of the runner files (the snapshot handed to the VM, or the VM's
    copy of it, which holds only the two scripts)."""
    out = {}
    for relative in RUNNER_FILES:
        path = pathlib.Path(folder) / os.path.basename(relative)
        if path.is_file():
            out[relative] = file_sha256(path)
    return out


def runner_copy_matches(vm_hashes, snapshot):
    """The VM's copy holds exactly the two scripts of the snapshot, unchanged."""
    scripts = {k: v for k, v in snapshot.items() if k != "scripts/mac_unit_audit.json"}
    return isinstance(vm_hashes, dict) and len(scripts) == 2 and vm_hashes == scripts


def cmd_runner_hashes(args):
    print(json.dumps(runner_snapshot_hashes(args.dir), sort_keys=True))
    return 0


def cmd_runner_hashes_match(args):
    try:
        vm_hashes = json.loads(args.vm)
    except ValueError:
        return 1
    return 0 if runner_copy_matches(vm_hashes, json.loads(_read(args.snapshot))) else 1


def snapshot_changed(repo, plan):
    """Whether mac/ or HEAD is no longer what the run was planned and built from (review v3: Codex A-4)."""
    return tree_hash(repo, ["mac"]) != plan["macTree"] or _head(repo) != plan["head"]


def latest_baseline(baseline_dir, where):
    """The newest baseline of the same `where` when none matches this OS version (Claude C-10); dated
    copies of earlier baselines are not candidates."""
    candidates = []
    for path in pathlib.Path(baseline_dir).glob(f"test_mac.baseline.{where}-*.json"):
        m = re.fullmatch(rf"test_mac\.baseline\.{where}-(\d+(?:\.\d+)*)\.json", path.name)
        if m:
            candidates.append((tuple(int(x) for x in m.group(1).split(".")), path))
    return max(candidates)[1] if candidates else None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("check-sources")
    p.add_argument("--tests-dir", required=True)
    p.add_argument("--pbxproj", required=True)
    p.set_defaults(func=cmd_check_sources)

    p = sub.add_parser("hashes")
    p.add_argument("--tests-dir", required=True)
    p.set_defaults(func=cmd_hashes)

    p = sub.add_parser("tart-check")
    p.add_argument("--ps", required=True)
    p.add_argument("--vm", required=True)
    p.set_defaults(func=cmd_tart_check)

    p = sub.add_parser("vm-qualify")
    p.add_argument("--facts", required=True)
    p.add_argument("--ps", required=True)
    p.add_argument("--vm", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--uuid-out", required=True)
    p.add_argument("--qualification", default="")
    p.set_defaults(func=cmd_vm_qualify)

    p = sub.add_parser("preflight")
    p.add_argument("--where", required=True, choices=("vm", "mac"))
    p.add_argument("--enumeration", required=True)
    p.add_argument("--unit-enumeration", required=True)
    p.add_argument("--tests-dir", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--allow", default="")
    p.add_argument("--os-build", default="")
    p.add_argument("--xcode", default="")
    p.add_argument("--baseline", action="store_true")
    p.add_argument("--feature", default="")
    p.add_argument("--qualification", default="")
    p.add_argument("--os-major", required=True)
    p.add_argument("--os-version", default="")
    p.add_argument("--head", required=True)
    p.add_argument("--mac-tree", required=True)
    p.add_argument("--unit", choices=("0", "1"), required=True)
    p.add_argument("--plan", required=True)
    p.add_argument("--baseline-dir", required=True)
    p.add_argument("--runner-files", default="")
    p.add_argument("--name-each-test", action="store_true")
    p.add_argument("--lsregister")
    p.add_argument("--stale")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--approval-out")
    p.set_defaults(func=cmd_preflight)

    p = sub.add_parser("approve")
    p.add_argument("--plan", required=True)
    p.add_argument("--approved", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--ledger-for-self-test", help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_approve)

    p = sub.add_parser("gate")
    p.add_argument("--plan", required=True)
    p.add_argument("--approved", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--ledger-for-self-test", help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_gate)

    p = sub.add_parser("invocations")
    p.add_argument("--plan", required=True)
    p.set_defaults(func=cmd_invocations)

    p = sub.add_parser("only-testing")
    p.add_argument("--plan", required=True)
    p.add_argument("--index", type=int)
    p.add_argument("--unit", type=int)
    p.set_defaults(func=cmd_only_testing)

    p = sub.add_parser("record")
    p.add_argument("--plan", required=True)
    p.add_argument("--index", type=int, required=True)
    p.add_argument("--tests-json")
    p.add_argument("--summary-json")
    p.add_argument("--exit-code", type=int, required=True)
    p.add_argument("--timed-out", default="0")
    p.add_argument("--tests-dir", required=True)
    p.set_defaults(func=cmd_record)

    p = sub.add_parser("check-call")
    p.add_argument("--plan", required=True)
    p.add_argument("--root", required=True)
    p.add_argument("--kind", required=True, choices=("build", "unit", "ui"))
    p.add_argument("--index", type=int, default=0)
    p.add_argument("arguments", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_check_call)

    p = sub.add_parser("unit-record")
    p.add_argument("--plan", required=True)
    p.add_argument("--index", type=int, required=True)
    p.add_argument("--summary-json")
    p.add_argument("--tests-json", required=True)
    p.add_argument("--exit-code", type=int, required=True)
    p.add_argument("--tests-dir", required=True)
    p.set_defaults(func=cmd_unit_record)

    p = sub.add_parser("not-run")
    p.add_argument("--plan", required=True)
    p.add_argument("--from-index", type=int, required=True)
    p.add_argument("--kind", required=True, choices=tuple(STOP_CODES))
    p.set_defaults(func=cmd_not_run)

    p = sub.add_parser("accept")
    p.add_argument("--results", required=True)
    p.set_defaults(func=cmd_accept)

    p = sub.add_parser("coverage")
    p.add_argument("--plan", required=True)
    p.add_argument("--sample-dir", required=True)
    p.add_argument("--attachments-root", required=True)
    p.set_defaults(func=cmd_coverage)

    p = sub.add_parser("check-build")
    p.add_argument("--products", required=True)
    p.add_argument("--tests-dir", required=True)
    p.add_argument("--enumeration", required=True)
    p.add_argument("--otool-objc", required=True)
    p.add_argument("--otool-load", required=True)
    p.set_defaults(func=cmd_check_build)

    p = sub.add_parser("fixture-create")
    p.add_argument("--dir", required=True)
    p.set_defaults(func=cmd_fixture_create)

    p = sub.add_parser("fixture-manifest")
    p.add_argument("--dir", required=True)
    p.set_defaults(func=cmd_fixture_manifest)

    p = sub.add_parser("fixture-compare")
    p.add_argument("--before", required=True)
    p.add_argument("--after", required=True)
    p.set_defaults(func=cmd_fixture_compare)

    p = sub.add_parser("copy-mark")
    p.add_argument("--app", required=True)
    p.set_defaults(func=cmd_copy_mark)

    p = sub.add_parser("lsregister")
    p.add_argument("--dump", required=True)
    p.add_argument("--run-root", default="")
    p.add_argument("--repo-root", default="")
    p.add_argument("--derived-root", default="")
    p.add_argument("--paths", action="store_true")
    p.add_argument("--out")
    p.set_defaults(func=cmd_lsregister)

    p = sub.add_parser("marker")
    p.add_argument("--root", required=True)
    p.add_argument("--run-id", default="")
    p.add_argument("--pid", type=int)
    p.add_argument("--role", default="")
    p.add_argument("--expect-under", default="")
    p.add_argument("--launching", action="store_true")
    p.set_defaults(func=cmd_marker)

    p = sub.add_parser("stale")
    p.add_argument("--scan-root", required=True)
    p.add_argument("--current-root", default="")
    p.add_argument("--list", action="store_true")
    p.add_argument("--stop", action="store_true")
    p.add_argument("--plan")
    p.add_argument("--approved")
    p.add_argument("--repo")
    p.add_argument("--out")
    p.add_argument("--ledger-for-self-test", help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_stale)

    p = sub.add_parser("stop-current")
    p.add_argument("--root", required=True)
    p.add_argument("--ledger-for-self-test", help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_stop_current)

    p = sub.add_parser("make-run-folder")
    p.add_argument("--scan-root", required=True)
    p.add_argument("--plan")
    p.add_argument("--run-id", required=True)
    p.add_argument("--approved", required=True)
    p.add_argument("--ledger-for-self-test", help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_make_run_folder)

    p = sub.add_parser("own-child")
    p.add_argument("--pid", type=int, required=True)
    p.add_argument("--parent", type=int, required=True)
    p.add_argument("--exe-name", required=True, choices=["perl"])
    p.set_defaults(func=cmd_own_child)

    p = sub.add_parser("runner-hashes")
    p.add_argument("--dir", required=True)
    p.set_defaults(func=cmd_runner_hashes)

    p = sub.add_parser("runner-hashes-match")
    p.add_argument("--vm", required=True)
    p.add_argument("--snapshot", required=True)
    p.set_defaults(func=cmd_runner_hashes_match)

    p = sub.add_parser("approval-stale")
    p.add_argument("--approved", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_approval_stale)

    p = sub.add_parser("tmp-names")
    p.add_argument("--dir", required=True)
    p.add_argument("--out")
    p.add_argument("--compare")
    p.set_defaults(func=cmd_tmp_names)

    p = sub.add_parser("private")
    p.add_argument("--scan-root", default="")
    p.add_argument("--dir", default="")
    p.add_argument("--own", type=int)
    p.set_defaults(func=cmd_private)

    p = sub.add_parser("audit-check")
    p.add_argument("--repo", required=True)
    p.set_defaults(func=cmd_audit_check)

    p = sub.add_parser("audit-hash")
    p.add_argument("--repo", required=True)
    p.set_defaults(func=cmd_audit_hash)

    p = sub.add_parser("tree-hash")
    p.add_argument("--repo")
    p.add_argument("--dir")
    p.set_defaults(func=cmd_tree_hash)

    p = sub.add_parser("file-list")
    p.add_argument("--repo", required=True)
    p.set_defaults(func=cmd_file_list)

    p = sub.add_parser("summary")
    p.add_argument("--plan", required=True)
    p.add_argument("--environment", required=True)
    p.add_argument("--results", required=True)
    p.add_argument("--baseline-dir", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--approved")
    p.add_argument("--save-baseline", action="store_true")
    p.set_defaults(func=cmd_summary)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except RunnerError as e:
        return _fail(str(e))
    except Exception as e:  # noqa: BLE001 - a traceback would show this Mac's paths (Claude B-13)
        return _fail(f"NTK-RUNNER:internal {type(e).__name__} in {args.command}", 2)


if __name__ == "__main__":
    sys.exit(main())
