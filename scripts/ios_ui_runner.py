#!/usr/bin/env python3
"""Decisions and checks of scripts/test_ios.sh (iOS UI test design, section 6.3).

The shell script runs xcodebuild, simctl and devicectl; everything that decides what runs, and
every check of what ran, is here as pure functions so that scripts/tests/test_ios_ui_runner.py
can break them directly (design 6.3 "純粋な関数と自己テスト", chapter 7).

Design: artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md

The three pillars that protect the private device (design 2, U-9):
  1. The runner selects the tests: on the device, only tests whose declared categories are all
     in --device-allow, each named with -only-testing; the results must be exactly the names.
  2. The declarations are checked: the simulator enumeration against DeviceRequirements.json,
     the per-class minimums, the frozen ClipboardUITests, the closed source rules, the device
     binary's test inventory, and the hashes of the trusted part.
  3. The user approves every device run: --dry-run writes the list with a random approval ID,
     --approved must match it exactly, and the ID is consumed in a ledger outside the repository
     before anything touches the device.

Updating the pinned hashes (TRUSTED_FILES, FROZEN_CLIPBOARD_SHA256): only after a review of the
change by another model (design 2, "信頼する部分"). `python3 scripts/ios_ui_runner.py hashes`
prints the current values; record the review in artifact/topics/ios-c-abi/ next to the change.
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
import subprocess
import sys
import tempfile

# --- Fixed tables ---------------------------------------------------------------------------

UI_TARGET = "IosLibraryExampleUITests"
UNIT_TARGETS = ("IosLibraryTests", "IosLibraryExampleTests")
SAMPLE_BUNDLE_ID = "com.jonghyunkim.ios.nativetoolkit.example"
CATEGORIES = ("systemui", "sharesheet", "clipboard", "files", "reinstall", "credentials")
BASE_CLASS = "SampleUITestCase"

# Classes run one xcodebuild each (U-18), in this order, with their feature for --feature and
# the baseline counts. The two Common classes run with every --feature.
UI_CLASSES = (
    ("NavigationUITests", "Common"),
    ("IdentifierInventoryUITests", "Common"),
    ("DialogUITests", "Dialog"),
    ("NotificationUITests", "Notification"),
    ("NotificationEventUITests", "Notification"),
    ("NotificationColdStartUITests", "Notification"),
    ("ShareUITests", "Share"),
    ("ClipboardUITests", "Clipboard"),
    ("ClipboardPasteUITests", "Clipboard"),
)
PERMISSION_CLASS = "NotificationPermissionUITests"
# NP2 (deny) first, then NP1 (allow): the run ends with the permission granted (U-7).
PERMISSION_ORDER = ("testNP2_denyPermission", "testNP1_allowPermission")
CB2_CLASS = "ClipboardPasteDenyUITests"
SEPARATE_CLASSES = ((PERMISSION_CLASS, "Notification"), (CB2_CLASS, "Clipboard"))
FEATURES = ("Dialog", "Notification", "Share", "Clipboard")
COMMON_FEATURE = "Common"

CLASS_TIMEOUT_SECONDS = {"ClipboardUITests": 75 * 60}
DEFAULT_TIMEOUT_SECONDS = 30 * 60

# Per-class minimum declarations (U-9 (2)).
CLASS_MINIMUMS = {
    "ClipboardUITests": {"clipboard"},
    "ClipboardPasteUITests": {"clipboard"},
    "ClipboardPasteDenyUITests": {"clipboard", "systemui"},
    "ShareUITests": {"sharesheet"},
    "NotificationEventUITests": {"systemui"},
    "NotificationColdStartUITests": {"systemui"},
    "NotificationPermissionUITests": {"reinstall", "systemui"},
}

# The existing ClipboardUITests, frozen (U-9 (3), U-10). Its file is hashed as a whole; pinned in
# stage 0d (2026-10-24) from commit 8fdb429d, after 0c removed the templates and changed the base.
FROZEN_CLIPBOARD_CLASS = "ClipboardUITests"
FROZEN_CLIPBOARD_FILE = "IosLibraryExampleUITests.swift"
FROZEN_CLIPBOARD_METHODS = (
    "testU1_navigatesToClipboardScreenAndShowsSections",
    "testU2_copyPlainTextThenReadReportsOneItem",
    "testU3_snapshotReportsAtLeastOneItem",
    "testU4_appendIncreasesItemCount",
    "testU5_observingReportsEventsAndStopsAfterStopObserving",
    "testU6_scopeControlsAreDisabledWhileObserving",
    "testU7_allErrorCasesReportTheirExpectedErrorCode",
    "testU8_namedPasteboardLifecycleEndsUnavailable",
    "testU9_clearEmptiesTheActiveScope",
    "testU10a_namedPasteboardSurvivesBackgroundAndDiesOnExplicitRemoval",
    "testU10b_namedPasteboardAfterProcessTermination",
    "testU11_loadFileReturnsTheFixedSizeFixtureAndCleansUp",
    "testU12_firstForegroundCheckReportsTheRealReturnValue",
    "testU13_everyContentKindIsWrittenToThePasteboard",
    "testU14_textUrlAndImageLoadsReturnTheirPayload",
    "testU15_detectionReturnsAResultForTheFixture",
    "testU16_readDataAndMatchingSnapshotReturnTheirSuccessPaths",
    "testU17_uniqueAndGeneralScopeSelection",
    "testU18_appendUrlAndUniversalMarkerGrowTheItemList",
    "testU19_copyOptionFixturesReachThePasteboardAtTheirDesignedLength",
    "testU20_controlOnlyOperationsDoNotOverwriteTheResultLine",
    "testU21_isolatedFixturesForWholeContentPatterns",
)
FROZEN_CLIPBOARD_SHA256 = "4612943da3ec0e32562d86d07d7d134521f1db5fed42e7543db742a5b8006cf3"

# The trusted part (design 2): the base file and the fixed Support files, pinned per file.
# Pinned in stage 0d (2026-10-24) from commit 8fdb429d, the end of stage 0c, and updated the same day
# for review v1 (R-1 to R-5: Springboard, SampleUITestCase, NotificationCleanup, SystemLabels) and v2
# (R-21: Springboard, SystemLabels), and after the first device run for the back button of iOS 18
# (SampleApp: the navigation bar buttons carry their labels; not yet reviewed by another model).
BASE_FILE = "Support/SampleUITestCase.swift"
TRUSTED_FILES = {
    "Support/SampleUITestCase.swift": "f9ac9bc5b9aac62afae0499e27bc1ab7b64f5e7361229402b8d34591eb461499",
    "Support/SampleApp.swift": "63edf06e72b7a7e881bf1b85427d16add388d3fe502e69f365e493b7c4d9a3d4",
    "Support/Springboard.swift": "427a3b7bddb7aef5f9604c3bc41df8e2516b1989fa872b62cbfddf5549a05be3",
    "Support/ShareSheet.swift": "b32c3595080dfca93d415e6e70010373edd8cf9471fa41f4e024ef8893f69329",
    "Support/RunnerPasteboard.swift": "003e15590840c3c174f0b181dbacca06b661b476dea0898d7456a3688e4a9bbc",
    "Support/UnexpectedAlertGuard.swift": "5f94e7b007e037cd9ca1393a512332acb3436a9ff2a19cfcaefcf91ea28c6bfa",
    "Support/NotificationCleanup.swift": "64a33263710150a505c14adcfeaf0144b8a43172194878ab652182284595f384",
    "Support/SystemLabels.swift": "f8d3e5807ede8eac4a54384338f4307f2d42a05908cf441c86d3b70a9548c0e7",
}
DECLARATIONS_FILE = "Support/DeviceRequirements.json"

# Names that drive the system, the device or the pasteboard directly (6.1 "危ない型の名前").
DANGEROUS_NAMES = ("XCUIApplication", "XCUIDevice", "UIPasteboard", "addUIInterruptionMonitor")
DANGEROUS_NAME_FILES = (
    "Support/SampleApp.swift", "Support/Springboard.swift", "Support/ShareSheet.swift",
    "Support/RunnerPasteboard.swift", "Support/UnexpectedAlertGuard.swift", "Support/SampleUITestCase.swift",
)
# The frozen file's known occurrences, checked by count (6.1).
FROZEN_DANGEROUS_COUNTS = {"XCUIApplication": 2, "XCUIDevice": 1, "UIPasteboard": 0, "addUIInterruptionMonitor": 0}
# Names that run code when the bundle loads or that expect failures (6.1).
FORBIDDEN_NAMES = ("XCTExpectFailure", "XCTExpectedFailure", "XCTestObservationCenter", "XCTestObservation",
                   "NSPrincipalClass")
ALLOWED_IMPORTS = {"XCTest", "Foundation"}
ALLOWED_SUPPORT_IMPORTS = ALLOWED_IMPORTS | {"UIKit"}
ALLOWED_ATTRIBUTES = {"MainActor", "discardableResult", "escaping", "Sendable", "autoclosure", "unknown"}
ALLOWED_POUND = {"available", "unavailable", "file", "fileID", "filePath", "line", "column", "function", "dsohandle"}
CONDITIONAL_POUND = {"if", "elseif", "else", "endif"}
HOOKS = ("setUpAfterGate", "tearDownAfterGate")
# Identifier strings of the sample (U-17); written only in the trusted part, or inside the frozen
# file's ClipboardID enum.
IDENTIFIER_STRING = re.compile(r"(?<![A-Za-z0-9_])(menu|dialog|notification|share|clipboard)\.(?=[A-Za-z]|$)")
FROZEN_IDENTIFIER_ENUM = "ClipboardID"
FORBIDDEN_IN_TEST_FILES = {"extension", "protocol", "deinit", "required", "convenience", "dynamic"}
MODIFIERS = {"final", "private", "fileprivate", "internal", "public", "open", "nonisolated", "static", "class",
             "override", "mutating", "nonmutating", "lazy", "weak", "unowned", "indirect", "dynamic",
             "required", "convenience", "optional", "package"}

# Intended skips (6.3): (test key, prefix of the skip reason).
INTENDED_SKIPS = (
    ("ClipboardUITests/testU10b_namedPasteboardAfterProcessTermination", "M-08 could not be decided here"),
    ("ClipboardUITests/testU21_isolatedFixturesForWholeContentPatterns",
     "whole-content detection patterns were not all reported"),
)

# The two environments of README D-21 (model, OS version).
BASELINE_ENVIRONMENTS = (("iPhone XS", "18.7.2"), ("iPhone 17", "26.2"))

COVERAGE_ATTACHMENT = re.compile(r"^ntk-button-coverage-v1(_\d+_[0-9A-Fa-f-]+)?\.json$")
APPROVAL_ID = re.compile(r"^[0-9a-f]{32}$")
# The consumed approvals. Always this place, taken from the account (not $HOME); only the
# self-tests pass another path, to the functions (stage 0d review R-6).
DEFAULT_LEDGER = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library" / "Application Support" / "native-toolkit" \
    / "test_ios-approvals.log"
LEDGER_LINE = re.compile(r"^[0-9a-f]{32}\t\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\+00:00|Z)\t[0-9A-Za-z-]+$")
# Under ios/, nothing but the runner's own output may differ from the commit on a device run
# (stage 0d review R-9).
IOS_OUTPUT_PREFIX = "ios/IosLibraryExample/build/"


class RunnerError(Exception):
    """A check failed; the message says which and why."""


# --- Destination (6.3 --udid) ---------------------------------------------------------------

def simulator_udids(simctl_devices_json):
    """UDIDs in `xcrun simctl list -j devices`. Only these are simulators."""
    data = json.loads(simctl_devices_json)
    devices = data.get("devices")
    if not isinstance(devices, dict):
        raise RunnerError("simctl list -j devices has no devices object")
    return {d["udid"] for runtime in devices.values() for d in runtime if isinstance(d, dict) and "udid" in d}


def classify_destination(udid, sim_udids):
    """'simulator' only for a UDID simctl lists; anything else is the device (fail closed)."""
    if not udid:
        raise RunnerError("--udid is empty")
    return "simulator" if udid in sim_udids else "device"


def enumeration_destination(kind, udid, enumerate_udid, sim_udids):
    """The simulator that is built for and enumerated. Never the device (6.3 step 2)."""
    target = udid if kind == "simulator" else enumerate_udid
    if kind == "simulator" and enumerate_udid and enumerate_udid != udid:
        raise RunnerError("--enumerate-udid must be the --udid simulator (or left out) for a simulator run")
    if not target:
        raise RunnerError("--enumerate-udid is required for a device run")
    if target not in sim_udids:
        raise RunnerError(f"the enumeration destination {target} is not a simulator in simctl list")
    return target


def simulator_environment(udid, simctl_devices_json, simctl_runtimes_json, language):
    data = json.loads(simctl_devices_json)
    for runtime_id, devices in data["devices"].items():
        for d in devices:
            if d.get("udid") == udid:
                runtimes = {r["identifier"]: r for r in json.loads(simctl_runtimes_json)["runtimes"]}
                runtime = runtimes.get(runtime_id, {})
                return {"kind": "simulator", "model": d["name"], "os": runtime.get("version", "unknown"),
                        "osBuild": runtime.get("buildversion", "unknown"), "language": language or "unknown"}
    raise RunnerError(f"{udid} is not in simctl list")


def device_environment(udid, devicectl_json):
    """Environment of the device from `devicectl device info details --json-output`. The hardware
    UDID there must be --udid, so the devicectl identifier names the same device."""
    result = json.loads(devicectl_json).get("result", {})
    hardware = result.get("hardwareProperties", {})
    device = result.get("deviceProperties", {})
    if hardware.get("udid") != udid:
        raise RunnerError("the --devicectl-id device is not the --udid device (hardware UDIDs differ)")
    language = device.get("preferredLanguages") or device.get("language") or "unknown"
    if isinstance(language, list):
        language = language[0] if language else "unknown"
    return {"kind": "device", "model": hardware.get("marketingName", "unknown"),
            "os": device.get("osVersionNumber", "unknown"), "osBuild": device.get("osBuildUpdate", "unknown"),
            "language": language}


def environment_warnings(env, baseline):
    warnings = []
    language = str(env.get("language", "unknown"))
    if env["kind"] == "simulator" and not language.startswith("en"):
        warnings.append(f"the simulator's language is {language}, not en (U-16)")
    if env["kind"] == "device" and not language.startswith("ja"):
        warnings.append(f"the device's language is {language}, not ja (U-16)")
    if baseline and baseline.get("osBuild") != env.get("osBuild"):
        warnings.append(f"the OS build {env.get('osBuild')} differs from the baseline's {baseline.get('osBuild')}; "
                        "take the baseline again (README D-21)")
    return warnings


def baseline_name(env):
    return f"test_ios.baseline.{env['model'].replace(' ', '_')}-{env['os']}.json"


# --- Names (6.1 DeviceRequirements.json) ----------------------------------------------------

_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]*$")


def key_from_enumeration_id(identifier):
    """`IosLibraryExampleUITests/<Class>/<method>()` -> `<Class>/<method>`."""
    parts = identifier.split("/")
    if len(parts) != 3 or parts[0] != UI_TARGET or not parts[2].endswith("()"):
        raise RunnerError(f"unexpected enumeration identifier: {identifier}")
    return _checked_key(f"{parts[1]}/{parts[2][:-2]}", identifier)


def key_from_node_id(node_id):
    """`<Class>/<method>()` (xcresult nodeIdentifier) -> `<Class>/<method>`."""
    if not node_id.endswith("()") or node_id.count("/") != 1:
        raise RunnerError(f"unexpected nodeIdentifier: {node_id}")
    return _checked_key(node_id[:-2], node_id)


def key_from_self_name(name):
    """`-[<Class> <method>]` (XCTestCase.name) -> `<Class>/<method>`."""
    m = re.fullmatch(r"-\[([^ \]]+) ([^ \]]+)\]", name)
    if not m:
        raise RunnerError(f"unexpected test name: {name}")
    return _checked_key(f"{m.group(1)}/{m.group(2)}", name)


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


# --- Enumeration (6.3 step 2) ----------------------------------------------------------------

def parse_enumeration(text):
    """The UI test identifiers of `-enumerate-tests ... -test-enumeration-format json`, in order.

    Only `IosLibraryExampleUITests/` entries are kept (the unit tests come too). The base class
    is listed as `<target>/<class>` without methods; that one is dropped, any other such entry
    stops the run."""
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
        identifier = test["identifier"]
        if not identifier.startswith(UI_TARGET + "/"):
            continue
        if identifier.count("/") == 1:
            if identifier != f"{UI_TARGET}/{BASE_CLASS}":
                raise RunnerError(f"a class without test methods other than {BASE_CLASS}: {identifier}")
            continue
        key_from_enumeration_id(identifier)
        identifiers.append(identifier)
    return identifiers


def duplicates(items):
    seen, repeated = set(), []
    for item in items:
        if item in seen and item not in repeated:
            repeated.append(item)
        seen.add(item)
    return repeated


def parse_declarations(text):
    """`Support/DeviceRequirements.json` -> {key: [categories]}. Duplicated keys fail even
    though JSON parsers keep the last one silently."""
    def no_duplicates(pairs):
        keys = [k for k, _ in pairs]
        repeated = duplicates(keys)
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


def check_enumeration(identifiers, declarations):
    """Step 2: the enumeration against the table, the class list, the minimums and the frozen
    ClipboardUITests. Returns the problems (an empty list passes)."""
    problems = []
    repeated = duplicates(identifiers)
    if repeated:
        problems.append(f"the enumeration repeats identifiers: {repeated}")
    keys = [key_from_enumeration_id(i) for i in identifiers]
    missing = sorted(set(keys) - set(declarations))
    extra = sorted(set(declarations) - set(keys))
    if missing:
        problems.append(f"tests without a declaration in {DECLARATIONS_FILE}: {missing}")
    if extra:
        problems.append(f"declarations without a test: {extra}")
    known_classes = {c for c, _ in UI_CLASSES} | {c for c, _ in SEPARATE_CLASSES}
    classes = {class_of(k) for k in keys}
    if classes != known_classes:
        problems.append(f"the enumerated classes differ from UI_CLASSES and the separate stages: "
                        f"not listed {sorted(classes - known_classes)}, not enumerated {sorted(known_classes - classes)}")
    problems += check_class_minimums(declarations)
    problems += check_frozen_clipboard(keys)
    return problems


def check_class_minimums(declarations):
    problems = []
    for key, categories in sorted(declarations.items()):
        minimum = CLASS_MINIMUMS.get(class_of(key), set())
        if not minimum <= set(categories):
            problems.append(f"{key} declares {sorted(categories)}, below the minimum of its class {sorted(minimum)}")
    return problems


def check_frozen_clipboard(keys):
    problems = []
    methods = [method_of(k) for k in keys if class_of(k) == FROZEN_CLIPBOARD_CLASS]
    if sorted(methods) != sorted(FROZEN_CLIPBOARD_METHODS):
        problems.append(f"{FROZEN_CLIPBOARD_CLASS} methods differ from the frozen 22: "
                        f"added {sorted(set(methods) - set(FROZEN_CLIPBOARD_METHODS))}, "
                        f"removed {sorted(set(FROZEN_CLIPBOARD_METHODS) - set(methods))}")
    elsewhere = sorted(k for k in keys if class_of(k) != FROZEN_CLIPBOARD_CLASS and method_of(k) in FROZEN_CLIPBOARD_METHODS)
    if elsewhere:
        problems.append(f"frozen {FROZEN_CLIPBOARD_CLASS} methods appear under another class: {elsewhere}")
    return problems


# --- Hashes (6.3 step 2, design 2 "信頼する部分") --------------------------------------------

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def file_sha256(path):
    return sha256_bytes(pathlib.Path(path).read_bytes())


def trusted_part_changes(tests_dir, pinned=None):
    """[(file, pinned, actual)] for the trusted files that differ (actual is None when missing)."""
    pinned = TRUSTED_FILES if pinned is None else pinned
    changes = []
    for relative, expected in sorted(pinned.items()):
        path = pathlib.Path(tests_dir) / relative
        actual = file_sha256(path) if path.is_file() else None
        if actual != expected:
            changes.append((relative, expected, actual))
    return changes


def frozen_file_problems(tests_dir, pinned=None):
    pinned = FROZEN_CLIPBOARD_SHA256 if pinned is None else pinned
    path = pathlib.Path(tests_dir) / FROZEN_CLIPBOARD_FILE
    actual = file_sha256(path) if path.is_file() else None
    if actual != pinned:
        return [f"{FROZEN_CLIPBOARD_FILE} differs from the frozen file (sha256 {actual}, pinned {pinned})"]
    return []


def tests_folder_hash(tests_dir):
    """One hash over every file of the test folder (relative path and content), for the
    approval and for 'the device build is the tree that was enumerated'."""
    root = pathlib.Path(tests_dir)
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file() and p.name != ".DS_Store"):
        digest.update(path.relative_to(root).as_posix().encode() + b"\0" + file_sha256(path).encode() + b"\n")
    return digest.hexdigest()


def bundle_declaration_problems(source_path, bundle_paths):
    if not bundle_paths:
        return [f"no {DECLARATIONS_FILE} in the built test bundle"]
    expected = file_sha256(source_path)
    return [f"the bundled copy differs from {DECLARATIONS_FILE}: {p}" for p in bundle_paths if file_sha256(p) != expected]


def bundle_info_plist_problems(info_plist_paths):
    problems = []
    for path in info_plist_paths:
        with open(path, "rb") as f:
            info = plistlib.load(f)
        if "NSPrincipalClass" in info:
            problems.append(f"the built Info.plist sets NSPrincipalClass: {path}")
    return problems


# --- Closed source rules (6.1) ----------------------------------------------------------------

class Token:
    __slots__ = ("kind", "text", "line", "segments")

    def __init__(self, kind, text, line, segments=None):
        self.kind = kind          # ident, eident (`escaped`), string, pound, attr, number, punct
        self.text = text
        self.line = line
        self.segments = segments  # literal parts of a string

    def __repr__(self):
        return f"Token({self.kind}, {self.text!r}, {self.line})"


class LexError(Exception):
    pass


_IDENT = re.compile(r"[^\W\d]\w*|\$\w+", re.UNICODE)
_NUMBER = re.compile(r"0[xob][0-9A-Fa-f_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?")


def lex(text):
    """Swift tokens without comments; string literals become one token with their literal parts,
    followed by the tokens of their interpolations (so code inside `\\(...)` is still checked)."""
    tokens, _, _ = _lex(text, 0, 1, stop_at_paren=False)
    return tokens


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
    if relative == FROZEN_CLIPBOARD_FILE:
        return "frozen"
    return "test"


def _word(token, *words):
    return token is not None and token.kind == "ident" and token.text in words


def _at(tokens, i):
    return tokens[i] if 0 <= i < len(tokens) else None


def _brace_range(tokens, open_index):
    depth = 0
    for j in range(open_index, len(tokens)):
        if tokens[j].kind == "punct" and tokens[j].text == "{":
            depth += 1
        elif tokens[j].kind == "punct" and tokens[j].text == "}":
            depth -= 1
            if depth == 0:
                return open_index, j
    return open_index, len(tokens) - 1


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

    frozen_enum = None
    if role == "frozen":
        for i, t in enumerate(tokens):
            if _word(t, "enum") and _at(tokens, i + 1) is not None and _at(tokens, i + 1).text == FROZEN_IDENTIFIER_ENUM:
                k = i + 2
                while k < len(tokens) and not (tokens[k].kind == "punct" and tokens[k].text == "{"):
                    k += 1
                frozen_enum = _brace_range(tokens, k)
                break

    conditional_seen = []
    dangerous_counts = {name: 0 for name in DANGEROUS_NAMES}
    for i, t in enumerate(tokens):
        nxt = _at(tokens, i + 1)
        prev = _at(tokens, i - 1)
        if t.kind == "pound":
            if t.text in CONDITIONAL_POUND:
                conditional_seen.append((i, t))
            elif t.text not in ALLOWED_POUND:
                problem(t, f"#{t.text} is not allowed")
            continue
        if t.kind == "attr":
            if t.text not in ALLOWED_ATTRIBUTES:
                problem(t, f"the attribute @{t.text} is not allowed")
            continue
        if t.kind == "string":
            if role in ("test", "frozen"):
                in_enum = frozen_enum is not None and frozen_enum[0] <= i <= frozen_enum[1]
                if not in_enum and any(IDENTIFIER_STRING.search(s) for s in t.segments):
                    problem(t, "an identifier string of the sample outside the trusted part")
            if "NSPrincipalClass" in t.text:
                problem(t, "NSPrincipalClass is not allowed")
            continue
        if t.kind not in ("ident", "eident"):
            continue
        word = t.text
        if word in DANGEROUS_NAMES:
            dangerous_counts[word] += 1
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
            problems += [f"{relative}:{t.line}: {m}" for m in _test_method_problems(tokens, i)]

    problems += [f"{relative}:{line}: {m}" for line, m in _conditional_problems(tokens, conditional_seen, role)]
    if role == "frozen":
        for name, expected in FROZEN_DANGEROUS_COUNTS.items():
            if dangerous_counts[name] != expected:
                problems.append(f"{relative}: {name} appears {dangerous_counts[name]} times, the frozen file has {expected}")
    elif relative not in DANGEROUS_NAME_FILES:
        for name, count in dangerous_counts.items():
            if count:
                problems.append(f"{relative}: {name} is allowed only in {', '.join(DANGEROUS_NAME_FILES)}")
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
    if inherits:
        return [f"class {name.text}: a class of the trusted part may not inherit ({' '.join(inherits)})"]
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


def _conditional_problems(tokens, seen, role):
    if role != "base":
        return [(t.line, f"#{t.text} is not allowed (only the base file tells the simulator from the device)")
                for _, t in seen]
    kinds = [t.text for _, t in seen]
    if kinds == []:
        return []
    if kinds != ["if", "else", "endif"]:
        return [(seen[0][1].line, f"the base file may have one '#if targetEnvironment(simulator) / #else / #endif', "
                                  f"found {kinds}")]
    i = seen[0][0]
    condition = [(_at(tokens, i + k).text if _at(tokens, i + k) else "") for k in range(1, 5)]
    if condition != ["targetEnvironment", "(", "simulator", ")"]:
        return [(seen[0][1].line, "the base file's #if must be '#if targetEnvironment(simulator)'")]
    return []


def check_test_folder(tests_dir, pbxproj_text):
    """6.1 over the whole folder: only Swift files and the declaration table, every Swift file
    under the closed rules, no Info.plist switch for the UI test target."""
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
        problems += check_swift_source(relative, path.read_text(encoding="utf-8"))
    problems += pbxproj_problems(pbxproj_text)
    return problems


def pbxproj_problems(pbxproj_text):
    problems = []
    if "NSPrincipalClass" in pbxproj_text:
        problems.append("project.pbxproj mentions NSPrincipalClass")
    blocks = re.findall(r"isa = XCBuildConfiguration;\s*buildSettings = \{(.*?)\n\t\t\t\};", pbxproj_text, re.S)
    ui_blocks = [b for b in blocks if "TEST_TARGET_NAME = IosLibraryExample;" in b]
    if not ui_blocks:
        problems.append("project.pbxproj: the UI test target's build configurations were not found")
    for block in ui_blocks:
        if "GENERATE_INFOPLIST_FILE = YES;" not in block or re.search(r"\bINFOPLIST_FILE\s*=", block):
            problems.append("project.pbxproj: the UI test target must generate its Info.plist (no INFOPLIST_FILE)")
    return problems


# --- Selection (6.3 step 3) and the plan ------------------------------------------------------

def feature_of_class(name):
    for c, feature in UI_CLASSES + SEPARATE_CLASSES:
        if c == name:
            return feature
    raise RunnerError(f"unknown class {name}")


def in_feature(key, feature):
    return feature is None or feature_of_class(class_of(key)) in (feature, COMMON_FEATURE)


def select_tests(identifiers, declarations, kind, allowed, feature=None):
    """(selected identifiers, excluded [(identifier, categories, missing)]).

    The simulator runs every test of the feature. The device runs a test only when every
    category it declares is allowed."""
    allowed = set(allowed)
    unknown = allowed - set(CATEGORIES)
    if unknown:
        raise RunnerError(f"unknown categories in --device-allow: {sorted(unknown)}")
    if kind == "simulator" and allowed:
        raise RunnerError("--device-allow is for the device only")
    selected, excluded = [], []
    for identifier in identifiers:
        key = key_from_enumeration_id(identifier)
        if not in_feature(key, feature):
            continue
        categories = declarations[key]
        missing = [c for c in categories if c not in allowed]
        if kind == "device" and missing:
            excluded.append((identifier, categories, missing))
        else:
            selected.append(identifier)
    return selected, excluded


def build_invocations(identifiers, selected, kind, feature=None, name_each_test=False):
    """The xcodebuild runs: the permission stage, the classes, the CB2 stage (6.3 steps 5-7).

    On the simulator a class is named as a whole and must give back exactly its enumerated
    tests. On the device every selected test is named on its own; a class with none is not run."""
    chosen = set(selected)
    by_class = {}
    for identifier in identifiers:
        by_class.setdefault(class_of(key_from_enumeration_id(identifier)), []).append(identifier)
    invocations = []

    def add(stage, name, cls, named, expected, uninstall):
        if not expected:
            return
        if not named:
            raise RunnerError(f"{name}: nothing to name with -only-testing")
        invocations.append({"index": len(invocations), "stage": stage, "name": name, "class": cls,
                            "onlyTesting": named, "expected": [key_from_enumeration_id(i) for i in expected],
                            "timeout": CLASS_TIMEOUT_SECONDS.get(cls, DEFAULT_TIMEOUT_SECONDS),
                            "uninstallBefore": uninstall})

    if feature in (None, "Notification"):
        for method in PERMISSION_ORDER:
            identifier = enumeration_id_from_key(f"{PERMISSION_CLASS}/{method}")
            if identifier in chosen:
                add("permission", f"{PERMISSION_CLASS}/{method}", PERMISSION_CLASS, [identifier], [identifier], True)
        stray = [i for i in by_class.get(PERMISSION_CLASS, []) if i in chosen and
                 method_of(key_from_enumeration_id(i)) not in PERMISSION_ORDER]
        if stray:
            raise RunnerError(f"tests of {PERMISSION_CLASS} outside the permission order: {stray}")
    for cls, _ in UI_CLASSES:
        tests = [i for i in by_class.get(cls, []) if i in chosen]
        if not tests:
            continue
        if kind == "simulator" and not name_each_test:
            add("ui", cls, cls, [f"{UI_TARGET}/{cls}"], by_class[cls] if len(tests) == len(by_class[cls]) else tests,
                False)
        else:
            add("ui", cls, cls, tests, tests, False)
    if feature in (None, "Clipboard"):
        tests = [i for i in by_class.get(CB2_CLASS, []) if i in chosen]
        if tests:
            named = [f"{UI_TARGET}/{CB2_CLASS}"] if kind == "simulator" and not name_each_test else tests
            add("cb2", CB2_CLASS, CB2_CLASS, named, tests, False)
    return invocations


def only_testing_arguments(invocation):
    """`-only-testing:<name>` for each name. Never empty: without -only-testing every test runs."""
    names = invocation.get("onlyTesting") or []
    if not names:
        raise RunnerError(f"{invocation.get('name')}: refusing to build an xcodebuild call without -only-testing")
    for name in names:
        if not name.startswith(UI_TARGET + "/"):
            raise RunnerError(f"{name}: not a test of {UI_TARGET}")
    return [f"-only-testing:{name}" for name in names]


def device_names_tests_only(invocations):
    """On the device every -only-testing is one test (`<target>/<class>/<method>()`), never a class."""
    problems = []
    for invocation in invocations:
        for name in invocation["onlyTesting"]:
            if name.count("/") != 2 or not name.endswith("()"):
                problems.append(f"{invocation['name']}: the device names a test, not a class: {name}")
    return problems


def make_plan(kind, udid, enumerate_udid, identifiers, declarations, allowed, feature, head, folder_hash,
              trusted_changes, unit_tests, name_each_test=False, runner_files=None):
    selected, excluded = select_tests(identifiers, declarations, kind, allowed, feature)
    if kind == "device" and not selected:
        raise RunnerError("no test is selected for the device; nothing to approve or run (stage 0d review R-15)")
    if kind == "device":
        name_each_test = True
    invocations = build_invocations(identifiers, selected, kind, feature, name_each_test)
    if name_each_test:
        problems = device_names_tests_only(invocations)
        if problems:
            raise RunnerError("; ".join(problems))
    named = [k for inv in invocations for k in inv["expected"]]
    if sorted(named) != sorted(key_from_enumeration_id(i) for i in selected):
        raise RunnerError("the invocations do not cover exactly the selected tests")
    return {
        "schema": 1, "kind": kind, "udid": udid, "enumerateUdid": enumerate_udid, "feature": feature,
        "deviceAllow": sorted(allowed), "head": head, "testsFolderHash": folder_hash,
        "trustedPart": {"unchanged": not trusted_changes,
                        "changed": [{"file": f, "pinned": p, "actual": a} for f, p, a in trusted_changes]},
        "enumeration": identifiers, "declarations": declarations, "selected": selected,
        "excluded": [{"id": i, "categories": c, "missing": m} for i, c, m in excluded],
        "invocations": invocations, "unitTests": unit_tests, "nameEachTest": name_each_test,
        "runnerFiles": dict(runner_files or {}),
    }


# --- Approval (U-9 pillar 3, 6.3 --dry-run / --approved) --------------------------------------

RUNNER_FILES = ("scripts/ios_ui_runner.py", "scripts/test_ios.sh")


def plan_digest(plan):
    """SHA-256 of the whole plan in a canonical form (stage 0d review R-19): the approval names
    exactly these invocations, names and expected results."""
    return sha256_bytes(json.dumps(plan, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())


def runner_file_hashes(repo):
    return {relative: file_sha256(pathlib.Path(repo) / relative) for relative in RUNNER_FILES}


def make_approval(plan, created_at=None, approval_id=None):
    if plan["kind"] != "device":
        raise RunnerError("approval lists are for device runs")
    return {
        "planDigest": plan_digest(plan),
        "runnerFiles": plan.get("runnerFiles", {}),
        "schema": 1,
        "approvalId": approval_id or secrets.token_hex(16),
        "createdAt": created_at or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "udid": plan["udid"], "enumerateUdid": plan["enumerateUdid"], "feature": plan["feature"],
        "deviceAllow": plan["deviceAllow"], "head": plan["head"], "testsFolderHash": plan["testsFolderHash"],
        "trustedPart": plan["trustedPart"],
        "tests": [{"id": i, "categories": plan["declarations"][key_from_enumeration_id(i)]} for i in plan["selected"]],
        "excluded": plan["excluded"],
    }


_CREATED_AT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\+00:00|Z)$")


def approval_problems(approval, plan):
    """The approved list must be exactly the list the runner would write now: the same keys, and
    the same value for each (the tests in order with their categories, the excluded tests, the
    trusted part), apart from the ID and the time (stage 0d review R-8)."""
    if not isinstance(approval, dict) or approval.get("schema") != 1:
        return ["the approval file is not a schema 1 approval list"]
    if plan.get("kind") != "device":
        return ["approvals are for device runs"]
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
                approved = [(t.get("id"), t.get("categories")) if isinstance(t, dict) else t for t in approval[field]]
                now = [(t["id"], t["categories"]) for t in expected[field]]
                problems.append(f"the approved tests differ from the selection: approved only "
                                f"{[t for t in approved if t not in now][:5]}, selected only "
                                f"{[t for t in now if t not in approved][:5]}"
                                + (", order differs" if sorted(map(str, approved)) == sorted(map(str, now)) else ""))
            else:
                problems.append(f"{field} differs: approved {approval[field]!r}, now {expected[field]!r}")
    if not plan["trustedPart"]["unchanged"]:
        problems.append("the trusted part changed; the device cannot run until its hashes are pinned after a review")
    return problems


def ledger_ids(text):
    """The IDs of a ledger. Every line must be `<ID><TAB><time><TAB><udid>`; a broken line (for
    example cut off by a crash) refuses the device (fail closed. Stage 0d review R-7)."""
    if text and not text.endswith("\n"):
        raise RunnerError("the approval ledger's last line is incomplete; check it by hand before a device run")
    ids = []
    for number, line in enumerate(text.splitlines(), 1):
        if not LEDGER_LINE.match(line):
            raise RunnerError(f"the approval ledger has a malformed line {number}; check it by hand before a device run")
        ids.append(line.split("\t", 1)[0])
    return ids


def consume_approval(path, approval_id, udid, now=None):
    """Records the ID as used before anything touches the device; an ID already there is refused
    (an approval runs once, and a run that stopped needs a new approval).

    Under a lock file of its own, the whole ledger is read and checked, then the new ledger is
    written to a temporary file, synced, renamed over the old one, and the folder is synced."""
    if not APPROVAL_ID.match(approval_id):
        raise RunnerError("malformed approval ID")
    if not re.fullmatch(r"[0-9A-Za-z-]+", udid):
        raise RunnerError("malformed udid for the ledger")
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.parent / (path.name + ".lock"), "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise RunnerError(f"the approval ledger is not a regular file: {path}")
        text = path.read_text(encoding="utf-8") if path.exists() else ""
        if approval_id in ledger_ids(text):
            raise RunnerError(f"the approval {approval_id} was already used; run --dry-run and ask again")
        stamp = now or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
        line = f"{approval_id}\t{stamp}\t{udid}\n"
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


def uncommitted_ios_changes(porcelain):
    """Paths under ios/ that differ from the commit (`git status --porcelain=v1 -uall -- ios`),
    apart from the runner's own output."""
    paths = []
    for line in porcelain.splitlines():
        if not line.strip():
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        path = path.strip('"')
        if not path.startswith(IOS_OUTPUT_PREFIX):
            paths.append(path)
    return paths


# --- Device binary inventory (6.3 step 4) ------------------------------------------------------

def selrefs_address(load_commands_text):
    """Start of (__DATA*, __objc_selrefs) from `otool -l`."""
    m = re.search(r"sectname __objc_selrefs\s+segname __DATA\w*\s+addr (0x[0-9a-f]+)", load_commands_text)
    if not m:
        raise RunnerError("otool -l has no __objc_selrefs section")
    return int(m.group(1), 16)


def _swift_class_name(objc_name):
    """`_TtC24IosLibraryExampleUITests13DialogUITests` -> `DialogUITests`; plain names stay."""
    m = re.fullmatch(r"_TtC(\d+)(\w+)", objc_name)
    if not m:
        return objc_name
    module_length = int(m.group(1))
    rest = m.group(2)[module_length:]
    m2 = re.fullmatch(r"(\d+)(\w+)", rest)
    if not m2 or len(m2.group(2)) != int(m2.group(1)):
        return objc_name
    return m2.group(2)


def parse_otool_classes(objc_text, load_commands_text):
    """{class address: {"name", "superclass" (address or external name), "selectors"}} from
    `otool -ov`, with relative method list names resolved through __objc_selrefs."""
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
        # Only the instance method list holds tests; ivars and properties have names too.
        m = re.match(r"^        (\w+)\s", line)
        if m:
            in_methods = m.group(1) == "baseMethods"
            continue
        if not in_methods:
            continue
        # Relative method lists: otool prints the selector reference's address and, for some
        # binaries, the selector after it; the test bundles of Xcode 26.3 leave it out.
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
    """`<Class>/<method>` for every XCTestCase subclass of the binary, inherited tests included
    (XCTest runs a superclass's tests under each subclass)."""
    def chain(entry):
        seen = []
        while entry is not None:
            if entry["address"] in seen:
                raise RunnerError("a class cycle in the binary")
            seen.append(entry["address"])
            parent = entry["superclass"]
            if isinstance(parent, int):
                entry_parent = classes.get(parent)
                if entry_parent is None:
                    return None, seen
                entry = entry_parent
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
        problems.append(f"the device binary's tests differ from the simulator enumeration: "
                        f"only in the binary {only_binary}, only in the enumeration {only_enumeration}")
    return problems


# --- Results (6.3 step 8, "結果の読み方") -----------------------------------------------------

# The only children a Test Case may have (closed list. Stage 0d review R-20): a failure or skip
# message. Anything else (repetitions, arguments, devices, configurations, or a kind not seen yet)
# may carry results of its own, so the runner stops instead of trusting the parent's result.
KNOWN_CASE_CHILDREN = {"Failure Message"}


def parse_xcresult_tests(text):
    """[{"node", "result", "skipReason", "message", "unknownShape"}] for every Test Case of
    `xcresulttool get test-results tests`, in order."""
    data = json.loads(text)
    cases = []

    def walk(node, bundle):
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            bundle = node.get("name")
        if node.get("nodeType") == "Test Case":
            messages = [c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == "Failure Message"]
            skip = next((m[len("Test skipped - "):] for m in messages if m.startswith("Test skipped - ")), None)
            shapes = sorted({str(c.get("nodeType")) for c in node.get("children", [])} - KNOWN_CASE_CHILDREN)
            cases.append({"node": node.get("nodeIdentifier", ""), "bundle": bundle, "result": node.get("result", ""),
                          "skipReason": skip if skip is not None else ("" if node.get("result") == "Skipped" else None),
                          "message": "; ".join(messages)[:300], "unknownShape": shapes})
            return
        for child in node.get("children", []):
            walk(child, bundle)

    for node in data.get("testNodes", []):
        walk(node, None)
    return cases, [d.get("deviceId") for d in data.get("devices", [])]


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
    """(passed|failed|skipped, note). Expected Failure, gated, precondition and unlisted skips fail."""
    if result == "Passed":
        return "passed", ""
    if result == "Failed":
        return "failed", ""
    if result == "Expected Failure":
        return "failed", "Expected Failure (XCTExpectFailure is not allowed. 6.1)"
    if result == "Skipped":
        reason = skip_reason or ""
        if "NTK-GATED:" in reason:
            return "failed", f"gated inside the test although the runner selected it: {reason}"
        if "NTK-PRECONDITION:" in reason:
            return "failed", f"precondition not met: {reason}"
        for allowed_key, prefix in INTENDED_SKIPS:
            if key == allowed_key and reason.startswith(prefix):
                return "skipped", reason[:200]
        return "failed", f"skip not in the intended list: {reason[:200]}"
    return "failed", f"unknown result {result!r}"


def ran_exactly_problems(result_keys, expected_keys):
    """The results must be exactly the named tests: no duplicate, none missing, none extra."""
    problems = []
    if duplicates(result_keys):
        problems.append(f"the results repeat tests: {duplicates(result_keys)}")
    if len(result_keys) != len(set(result_keys)) or sorted(set(result_keys)) != sorted(set(expected_keys)):
        missing = sorted(set(expected_keys) - set(result_keys))
        extra = sorted(set(result_keys) - set(expected_keys))
        if missing:
            problems.append(f"named but not in the results: {missing}")
        if extra:
            problems.append(f"in the results but not named: {extra}")
    if duplicates(expected_keys):
        problems.append(f"the names repeat tests: {duplicates(expected_keys)}")
    return problems


def record_invocation(invocation, tests_text, summary_text, exit_code, timed_out, expected_device):
    """Results of one UI xcodebuild run as baseline records, and whether a device run must stop
    now: no result bundle, a time-out, a destination other than the requested one, a test case
    whose name cannot be read or that has a shape the runner does not know, a summary that does
    not agree, or results that are not exactly the named tests (stage 0d review R-11)."""
    name = invocation["name"]
    records = []
    stop = False

    def pseudo(problem, message, stops=True):
        nonlocal stop
        records.append({"test": f"{UI_TARGET}/{name}#{problem}", "result": "failed", "message": message})
        stop = stop or stops

    if timed_out:
        pseudo("timeout", f"cut off after {invocation['timeout']} s")
    if tests_text is None:
        pseudo("noResult", f"xcodebuild exited with {exit_code} and left no result bundle")
        return records, True
    cases, devices = parse_xcresult_tests(tests_text)
    if devices != [expected_device]:
        pseudo("destination", f"the result bundle ran on {devices}, not on the requested destination")
    if not cases:
        pseudo("zeroTests", "no test ran")
    for problem in (summary_problems(summary_text, cases) if summary_text is not None else ["no summary"]):
        pseudo("summary", problem)
    pairs = []
    for case in cases:
        try:
            key = key_from_node_id(case["node"])
        except RunnerError as e:
            pseudo("unreadableName", str(e))
            continue
        if case["bundle"] != UI_TARGET:
            pseudo("otherBundle", f"{case['node']} is in {case['bundle']}, not in {UI_TARGET}")
            continue
        if case["unknownShape"]:
            pseudo("unknownShape", f"{case['node']} has {case['unknownShape']}")
            continue
        pairs.append((case, key))
    if len(pairs) != len(cases):
        pseudo("readable", f"{len(pairs)} of {len(cases)} results could be read")
    for problem in ran_exactly_problems([key for _, key in pairs], invocation["expected"]):
        pseudo("namedSet", problem)
    if exit_code != 0 and cases and all(c["result"] in ("Passed", "Skipped") for c in cases):
        pseudo("exitCode", f"xcodebuild exited with {exit_code} although no test failed", stops=False)
    for case, key in pairs:
        outcome, note = classify(key, case["result"], case["skipReason"])
        records.append({"test": f"{UI_TARGET}/{key}", "result": outcome, "message": note or case["message"],
                        "raw": case["result"]})
    return records, stop


def unit_records(target, tests_text, exit_code):
    """Unit test results as `<target>/<nodeIdentifier without ()>`. Skips fail like UI skips."""
    if tests_text is None:
        return [{"test": f"{target}#noResult", "result": "failed", "message": f"xcodebuild exited with {exit_code}"}]
    cases, _ = parse_xcresult_tests(tests_text)
    records = []
    for case in cases:
        if case["bundle"] != target:
            continue
        node = case["node"][:-2] if case["node"].endswith("()") else case["node"]
        outcome, note = classify(node, case["result"], case["skipReason"])
        records.append({"test": f"{target}/{node}", "result": outcome, "message": note or case["message"],
                        "raw": case["result"]})
    if not records:
        records.append({"test": f"{target}#zeroTests", "result": "failed", "message": "no test ran"})
    if exit_code != 0 and all(r["result"] == "passed" for r in records):
        records.append({"test": f"{target}#exitCode", "result": "failed",
                        "message": f"xcodebuild exited with {exit_code} although no test failed"})
    return records


# --- Button coverage (3.7, full simulator runs) -----------------------------------------------

def expected_buttons(sample_sources):
    """`<screen>.button.<name>` for every `enum ButtonName` entry of the Dialog, Notification and
    Share identifier enums (`{"dialog": text, ...}`)."""
    buttons = []
    for screen, text in sample_sources.items():
        m = re.search(r"enum ButtonName \{(.*?)\n    \}", text, re.S)
        if not m:
            raise RunnerError(f"no ButtonName enum for {screen}")
        buttons += [f"{screen}.button.{name}" for name in re.findall(r'static let \w+ = "(\w+)"', m.group(1))]
    return buttons


def coverage_problems(manifest_text, attachment_dir, keys_using_sample, buttons):
    """Each test that uses SampleApp leaves exactly one `ntk-button-coverage-v1.json` (a JSON array
    of unique strings); together they press every button of Dialog, Notification and Share."""
    manifest = json.loads(manifest_text)
    found = {}
    for entry in manifest:
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
        except (OSError, ValueError) as e:
            problems.append(f"{key}: the button coverage attachment is not JSON ({e})")
            continue
        if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
            problems.append(f"{key}: the button coverage attachment is not an array of strings")
            continue
        if duplicates(values):
            problems.append(f"{key}: the button coverage attachment repeats {duplicates(values)}")
        pressed |= set(values)
    not_pressed = sorted(set(buttons) - pressed)
    if not_pressed:
        problems.append(f"buttons no test pressed: {not_pressed}")
    return problems


# --- Baseline (6.3 "基準のファイル", "基準との比べ方") -----------------------------------------

def compare_with_baseline(current, baseline_results, in_scope):
    """(report lines, lost tests). A test of this run's scope that passed in the baseline and now
    skipped or did not run is lost coverage; tests outside the scope (--feature, gated on the
    device) are only reported."""
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
    header = (f"changed={len(changed)}, added={len(added)}, removed={len(removed) - out_of_scope}, "
              f"outside this run={out_of_scope}")
    return [header] + lines, sorted(set(lost))


def in_run_scope(test, plan):
    """Whether a baseline test belongs to this run: its feature was run (all of them without
    --feature), it was not excluded by category on the device, and unit tests count only when
    they ran. A UI test of a class that no longer exists is in scope of a full run."""
    target, _, key = test.partition("/")
    if target in UNIT_TARGETS:
        return bool(plan.get("unitTests"))
    if target != UI_TARGET or "/" not in key:
        return True
    if any(entry["id"] == enumeration_id_from_key(key) for entry in plan["excluded"]):
        return False
    try:
        feature = feature_of_class(class_of(key))
    except RunnerError:
        return plan["feature"] is None
    return plan["feature"] is None or feature in (plan["feature"], COMMON_FEATURE)


def baseline_counts(results):
    counts = {}
    for test, outcome in results.items():
        target = test.split("/", 1)[0].split("#", 1)[0]
        if target == UI_TARGET and "/" in test:
            feature = feature_of_class(test.split("/")[1])
            bucket = counts.setdefault(target, {}).setdefault(feature, {})
        else:
            bucket = counts.setdefault(target, {})
        bucket[outcome] = bucket.get(outcome, 0) + 1
    return counts


def baseline_refusal(env, plan, failed, xcode):
    if plan["feature"] is not None or (plan["kind"] == "simulator" and not plan["unitTests"]):
        return "--baseline needs a full run (no --feature, no --skip-unit)"
    if (env["model"], env["os"]) not in BASELINE_ENVIRONMENTS:
        return f"{env['model']} {env['os']} is not one of the baseline environments {BASELINE_ENVIRONMENTS} (U-16)"
    if failed:
        return "the run has failures"
    return None


def make_baseline(env, plan, results, xcode):
    allowed = list(CATEGORIES) if plan["kind"] == "simulator" else plan["deviceAllow"]
    return {"model": env["model"], "os": env["os"], "osBuild": env["osBuild"], "language": env["language"],
            "xcode": xcode, "allowed": allowed, "counts": baseline_counts(results),
            "results": dict(sorted(results.items()))}


# --- Command line -----------------------------------------------------------------------------

def _read(path):
    return pathlib.Path(path).read_text(encoding="utf-8")


def _write_json(path, value):
    pathlib.Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _fail(message, code=1):
    print(f"Error: {message}", file=sys.stderr)
    return code


def cmd_destination(args):
    sims = simulator_udids(_read(args.simctl_devices))
    print(classify_destination(args.udid, sims))
    return 0


def cmd_enumeration_destination(args):
    sims = simulator_udids(_read(args.simctl_devices))
    print(enumeration_destination(args.kind, args.udid, args.enumerate_udid, sims))
    return 0


def cmd_environment(args):
    if args.kind == "simulator":
        env = simulator_environment(args.udid, _read(args.simctl_devices), _read(args.simctl_runtimes), args.language)
    else:
        env = device_environment(args.udid, _read(args.devicectl_json))
    env["xcode"] = args.xcode
    baseline_path = pathlib.Path(args.baseline_dir) / baseline_name(env)
    baseline = json.loads(_read(baseline_path)) if baseline_path.is_file() else None
    _write_json(args.out, env)
    print(f"[device] {env['kind']} {env['model']} / iOS {env['os']} ({env['osBuild']}) / {env['language']} / "
          f"{args.xcode}")
    for warning in environment_warnings(env, baseline):
        print(f"Warning: {warning}", file=sys.stderr)
    return 0


def cmd_check_sources(args):
    problems = check_test_folder(args.tests_dir, _read(args.pbxproj))
    problems += frozen_file_problems(args.tests_dir)
    for problem in problems:
        print(f"  FAIL {problem}")
    if problems:
        return _fail(f"{len(problems)} closed source rule violation(s) (design 6.1)")
    print("[sources] the closed source rules pass (design 6.1)")
    return 0


def git_ios_changes(repo):
    finished = subprocess.run(["git", "-C", str(repo), "status", "--porcelain=v1", "-uall", "--", "ios"],
                              capture_output=True, text=True)
    if finished.returncode != 0:
        raise RunnerError(f"git status failed: {finished.stderr.strip()}")
    return uncommitted_ios_changes(finished.stdout)


def bundle_problems(tests_dir, products):
    """The built test bundle's copy of the declarations and its Info.plist (6.3 step 2; for the
    device build too, stage 0d review R-14)."""
    bundles = [str(p) for p in pathlib.Path(products).rglob(f"{UI_TARGET}.xctest/DeviceRequirements.json")]
    problems = bundle_declaration_problems(pathlib.Path(tests_dir) / DECLARATIONS_FILE, bundles)
    infos = [str(p) for p in pathlib.Path(products).rglob(f"{UI_TARGET}.xctest/Info.plist")]
    if not infos:
        problems.append(f"no Info.plist in the built {UI_TARGET}.xctest")
    return problems + bundle_info_plist_problems(infos)


def cmd_preflight(args):
    identifiers = parse_enumeration(_read(args.enumeration))
    declarations = parse_declarations(_read(pathlib.Path(args.tests_dir) / DECLARATIONS_FILE))
    problems = check_enumeration(identifiers, declarations)
    problems += bundle_problems(args.tests_dir, args.products)
    for problem in problems:
        print(f"  FAIL {problem}")
    if problems:
        return _fail(f"{len(problems)} problem(s) between the enumeration and the declarations (design 6.3 step 2)")
    print(f"[enumeration] {len(identifiers)} UI tests match {DECLARATIONS_FILE} exactly")
    changes = trusted_part_changes(args.tests_dir)
    for relative, pinned, actual in changes:
        print(f"Warning: the trusted part changed: {relative} (sha256 {actual}, pinned {pinned})", file=sys.stderr)
    allowed = [c for c in (args.allow or "").split(",") if c]
    feature = args.feature or None
    plan = make_plan(args.kind, args.udid, args.enumerate_udid, identifiers, declarations, allowed, feature,
                     args.head, tests_folder_hash(args.tests_dir), changes, args.unit == "1", args.name_each_test,
                     runner_file_hashes(args.repo) if args.kind == "device" else None)
    _write_json(args.plan, plan)
    print_selection(plan)
    if args.kind == "device" and changes and not args.dry_run:
        return _fail("the trusted part changed; not running on the device (design 2, 6.3 step 2)")
    if args.kind == "device" and args.dry_run:
        approval = make_approval(plan)
        _write_json(args.approval_out, approval)
        print(f"[dry-run] approval ID {approval['approvalId']}")
        for problem in git_runner_file_changes(args.repo):
            print(f"[dry-run] {problem.upper()}: the device run will refuse until the runner is committed")
        dirty = git_ios_changes(args.repo)
        if dirty:
            print(f"[dry-run] UNCOMMITTED CHANGES UNDER ios/ ({len(dirty)}, e.g. {dirty[:3]}): the device run will "
                  "refuse until they are committed")
        if changes:
            print("[dry-run] THE TRUSTED PART CHANGED: this list cannot be run on the device until its hashes are "
                  "pinned after a review by another model")
        print(f"[dry-run] approval list: {args.approval_out}")
        print("[dry-run] show the list above to the user; after approval run again with --approved <that file>")
    return 0


def print_selection(plan):
    where = "device" if plan["kind"] == "device" else "simulator"
    print(f"[select] {where}: {len(plan['selected'])} tests to run, {len(plan['excluded'])} excluded by category"
          + (f" (--device-allow {','.join(plan['deviceAllow']) or '(none)'})" if where == "device" else ""))
    for identifier in plan["selected"]:
        categories = plan["declarations"][key_from_enumeration_id(identifier)]
        print(f"  RUN     {identifier}  [{','.join(categories) or '-'}]")
    for entry in plan["excluded"]:
        print(f"  EXCLUDE {entry['id']}  [{','.join(entry['categories'])}] missing {','.join(entry['missing'])}")
    for invocation in plan["invocations"]:
        print(f"  CALL {invocation['index']}: {invocation['stage']} {invocation['name']} "
              f"({len(invocation['onlyTesting'])} -only-testing, {len(invocation['expected'])} tests"
              f"{', uninstall first' if invocation['uninstallBefore'] else ''})")


def cmd_approve(args):
    plan = json.loads(_read(args.plan))
    try:
        approval = json.loads(_read(args.approved))
    except (OSError, ValueError) as e:
        return _fail(f"cannot read the approval file: {e}")
    problems = approval_problems(approval, plan)
    problems += tree_problems(plan, args.repo, args.head, args.tests_dir)
    problems += runner_problems(plan, args.repo)
    for problem in problems:
        print(f"  FAIL {problem}")
    if problems:
        return _fail("the approval does not match this run; run --dry-run and ask the user again")
    ledger = pathlib.Path(args.ledger_for_self_test) if args.ledger_for_self_test else DEFAULT_LEDGER
    try:
        consume_approval(ledger, approval["approvalId"], plan["udid"])
    except RunnerError as e:
        return _fail(str(e))
    print(f"[approval] {approval['approvalId']} matches and is now consumed ({ledger})")
    return 0


def git_runner_file_changes(repo):
    """The runner's two files that are not committed as they are (stage 0d review R-18)."""
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
    """On the device, the runner itself must be committed and be the files the plan was made with."""
    problems = git_runner_file_changes(repo)
    if not plan.get("runnerFiles") or runner_file_hashes(repo) != plan["runnerFiles"]:
        problems.append("the runner files differ from the ones the approved plan was made with")
    return problems


def tree_problems(plan, repo, head, tests_dir):
    """The device builds the commit that was enumerated and approved, with nothing under ios/
    changed or added (stage 0d review R-9)."""
    problems = []
    if head != plan["head"]:
        problems.append(f"HEAD is {head}, the enumeration was made at {plan['head']}")
    if tests_folder_hash(tests_dir) != plan["testsFolderHash"]:
        problems.append("the test folder changed after the enumeration")
    dirty = git_ios_changes(repo)
    if dirty:
        problems.append(f"uncommitted changes under ios/ ({len(dirty)}): {dirty[:5]}")
    return problems


def gate_problems(plan, approval, repo, head, tests_dir, ledger):
    """Before every call that reaches the device: the approved plan unchanged (digest), its ID
    consumed, the runner committed and unchanged, the tree as enumerated (stage 0d review R-18,
    R-19)."""
    problems = []
    if plan.get("kind") != "device" or not isinstance(approval, dict):
        return ["not an approved device plan"]
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
    return problems + tree_problems(plan, repo, head, tests_dir)


def cmd_device_gate(args):
    plan = json.loads(_read(args.plan))
    approval = json.loads(_read(args.approved))
    head = subprocess.run(["git", "-C", str(args.repo), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    problems = gate_problems(plan, approval, args.repo, head, args.tests_dir, DEFAULT_LEDGER)
    for problem in problems:
        print(f"  FAIL {problem}", file=sys.stderr)
    if problems:
        return _fail("not touching the device: the approved plan, the runner or the tree changed")
    return 0


def cmd_verify_tree(args):
    plan = json.loads(_read(args.plan))
    problems = tree_problems(plan, args.repo, args.head, args.tests_dir)
    for problem in problems:
        print(f"  FAIL {problem}")
    if problems:
        return _fail("the tree changed after the enumeration; not building for the device")
    return 0


def cmd_check_binary(args):
    plan = json.loads(_read(args.plan))
    keys = binary_test_keys(parse_otool_classes(_read(args.otool_objc), _read(args.otool_load)))
    problems = binary_inventory_problems(keys, plan["enumeration"])
    problems += bundle_problems(args.tests_dir, args.products)
    for problem in problems:
        print(f"  FAIL {problem}")
    if problems:
        return _fail("the device binary does not match the simulator enumeration (design 6.3 step 4)")
    print(f"[binary] the device build has the {len(keys)} enumerated tests")
    return 0


def cmd_invocations(args):
    plan = json.loads(_read(args.plan))
    for inv in plan["invocations"]:
        print(f"{inv['index']}\t{inv['stage']}\t{inv['name']}\t{inv['timeout']}\t{1 if inv['uninstallBefore'] else 0}")
    return 0


def cmd_only_testing(args):
    plan = json.loads(_read(args.plan))
    for argument in only_testing_arguments(plan["invocations"][args.index]):
        print(argument)
    return 0


def cmd_may_uninstall(args):
    plan = json.loads(_read(args.plan))
    if plan["kind"] == "simulator":
        return 0
    approval = json.loads(_read(args.approved))
    if "reinstall" in plan["deviceAllow"] and "reinstall" in approval.get("deviceAllow", []):
        return 0
    return _fail("reinstall is not allowed and approved; not removing the sample from the device")


def cmd_record(args):
    plan = json.loads(_read(args.plan))
    invocation = plan["invocations"][args.index]
    tests_text = _read(args.tests_json) if args.tests_json and pathlib.Path(args.tests_json).is_file() else None
    summary_text = _read(args.summary_json) if args.summary_json and pathlib.Path(args.summary_json).is_file() else None
    records, stop = record_invocation(invocation, tests_text, summary_text, args.exit_code, args.timed_out == "1",
                                      plan["udid"])
    with open(args.results, "a", encoding="utf-8") as out:
        for record in records:
            record["invocation"] = invocation["name"]
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
    for record in records:
        if record["result"] != "passed":
            print(f"  {record['result'].upper()} {record['test']}: {record['message']}")
    passed = sum(1 for r in records if r["result"] == "passed")
    print(f"  {passed}/{len(records)} passed")
    if stop and plan["kind"] == "device":
        return _fail("the device results are not exactly the named tests; stopping the device run", 3)
    return 0


def cmd_unit_record(args):
    tests_text = _read(args.tests_json) if pathlib.Path(args.tests_json).is_file() else None
    records = unit_records(args.target, tests_text, args.exit_code)
    with open(args.results, "a", encoding="utf-8") as out:
        for record in records:
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
    failed = [r for r in records if r["result"] == "failed"]
    for record in failed:
        print(f"  FAILED {record['test']}: {record['message']}")
    print(f"  {args.target}: {len(records) - len(failed)}/{len(records)} without failure")
    return 0


def cmd_coverage(args):
    plan = json.loads(_read(args.plan))
    sample = pathlib.Path(args.sample_dir)
    buttons = expected_buttons({"dialog": _read(sample / "DialogSampleView.swift"),
                                "notification": _read(sample / "NotificationSampleView.swift"),
                                "share": _read(sample / "ShareSampleView.swift")})
    keys = [k for inv in plan["invocations"] for k in inv["expected"] if class_of(k) != FROZEN_CLIPBOARD_CLASS]
    manifests = [p for p in pathlib.Path(args.attachments_root).glob("*/manifest.json")]
    merged, problems = [], []
    for manifest in manifests:
        for entry in json.loads(_read(manifest)):
            for attachment in entry.get("attachments", []):
                attachment["exportedFileName"] = str(manifest.parent.name + "/" + attachment["exportedFileName"])
            merged.append(entry)
    problems = coverage_problems(json.dumps(merged), args.attachments_root, keys, buttons)
    with open(args.results, "a", encoding="utf-8") as out:
        out.write(json.dumps({"test": f"{UI_TARGET}#buttonCoverage", "result": "failed" if problems else "passed",
                              "message": "; ".join(problems)[:1000]}, ensure_ascii=False) + "\n")
    for problem in problems:
        print(f"  FAIL {problem}")
    print(f"[coverage] {len(buttons)} buttons, {len(keys)} tests: {'failed' if problems else 'passed'}")
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
            print(f"  FAILED {r['test']}: {r.get('message', '')}")
    for entry in plan["excluded"]:
        print(f"  EXCLUDED (category) {entry['id']}: missing {','.join(entry['missing'])}")
    failed = bool(counts.get("failed"))
    current = {r["test"]: r["result"] for r in results if "#" not in r["test"]}
    if plan["kind"] == "device" and args.approved:
        approval = json.loads(_read(args.approved))
        ran = sorted(enumeration_id_from_key(t.split("/", 1)[1]) for t in current if t.startswith(UI_TARGET + "/"))
        approved = sorted(t["id"] for t in approval.get("tests", []))
        if ran != approved:
            print(f"[approval] FAILED: the tests that ran differ from the approved list "
                  f"(ran only {sorted(set(ran) - set(approved))}, approved only {sorted(set(approved) - set(ran))})")
            failed = True
    baseline_path = pathlib.Path(args.baseline_dir) / baseline_name(env)
    lost = []
    if baseline_path.is_file():
        baseline = json.loads(_read(baseline_path))
        base_results = baseline["results"]
        in_scope = {t for t in base_results if in_run_scope(t, plan)}
        lines, lost = compare_with_baseline(current, base_results, in_scope)
        print(f"[baseline] {baseline_path.name}: {lines[0]}")
        for line in lines[1:]:
            print(line)
        if lost and not args.save_baseline:
            print(f"[baseline] FAILED: {len(lost)} test(s) that passed in the baseline skipped or did not run: {lost}")
    else:
        print(f"[baseline] none for {env['model']}-{env['os']} ({baseline_path.name})")
    failed = failed or (bool(lost) and not args.save_baseline)
    if plan["kind"] == "device":
        print("[device] left on the device: copies in Files (On My iPhone) if files was allowed, the test strings "
              "on the pasteboard if clipboard was allowed, the category sample-category, words the keyboard may "
              "have learned (design 6.3 step 9)")
    if args.save_baseline:
        refusal = baseline_refusal(env, plan, failed, env.get("xcode", ""))
        if refusal:
            print(f"[baseline] not saved: {refusal}")
            return 1
        _write_json(baseline_path, make_baseline(env, plan, current, env.get("xcode", "")))
        if plan["kind"] == "device":
            print(f"[baseline] categories not allowed ({sorted(set(CATEGORIES) - set(plan['deviceAllow']))}) are not "
                  "in the baseline")
        print(f"[baseline] saved {baseline_path.name}")
    return 1 if failed else 0


def cmd_hashes(args):
    for relative in sorted(TRUSTED_FILES):
        path = pathlib.Path(args.tests_dir) / relative
        print(f'    "{relative}": "{file_sha256(path)}",')
    print(f"FROZEN_CLIPBOARD_SHA256 = \"{file_sha256(pathlib.Path(args.tests_dir) / FROZEN_CLIPBOARD_FILE)}\"")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("destination")
    p.add_argument("--udid", required=True)
    p.add_argument("--simctl-devices", required=True)
    p.set_defaults(func=cmd_destination)

    p = sub.add_parser("enumeration-destination")
    p.add_argument("--kind", required=True, choices=["simulator", "device"])
    p.add_argument("--udid", required=True)
    p.add_argument("--enumerate-udid", default="")
    p.add_argument("--simctl-devices", required=True)
    p.set_defaults(func=cmd_enumeration_destination)

    p = sub.add_parser("environment")
    p.add_argument("--kind", required=True, choices=["simulator", "device"])
    p.add_argument("--udid", required=True)
    p.add_argument("--simctl-devices")
    p.add_argument("--simctl-runtimes")
    p.add_argument("--language", default="")
    p.add_argument("--devicectl-json")
    p.add_argument("--xcode", default="")
    p.add_argument("--baseline-dir", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_environment)

    p = sub.add_parser("check-sources")
    p.add_argument("--tests-dir", required=True)
    p.add_argument("--pbxproj", required=True)
    p.set_defaults(func=cmd_check_sources)

    p = sub.add_parser("preflight")
    p.add_argument("--kind", required=True, choices=["simulator", "device"])
    p.add_argument("--udid", required=True)
    p.add_argument("--enumerate-udid", required=True)
    p.add_argument("--enumeration", required=True)
    p.add_argument("--tests-dir", required=True)
    p.add_argument("--products", required=True)
    p.add_argument("--feature", default="")
    p.add_argument("--allow", default="")
    p.add_argument("--head", required=True)
    p.add_argument("--unit", default="0")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--name-each-test", action="store_true")
    p.add_argument("--repo", required=True)
    p.add_argument("--plan", required=True)
    p.add_argument("--approval-out")
    p.set_defaults(func=cmd_preflight)

    p = sub.add_parser("approve")
    p.add_argument("--plan", required=True)
    p.add_argument("--approved", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--tests-dir", required=True)
    # Only scripts/tests/test_ios_ui_runner.py passes this; test_ios.sh never does (R-6).
    p.add_argument("--ledger-for-self-test", help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_approve)

    p = sub.add_parser("device-gate")
    p.add_argument("--plan", required=True)
    p.add_argument("--approved", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--tests-dir", required=True)
    p.set_defaults(func=cmd_device_gate)

    p = sub.add_parser("verify-tree")
    p.add_argument("--plan", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--tests-dir", required=True)
    p.set_defaults(func=cmd_verify_tree)

    p = sub.add_parser("check-binary")
    p.add_argument("--plan", required=True)
    p.add_argument("--otool-objc", required=True)
    p.add_argument("--otool-load", required=True)
    p.add_argument("--tests-dir", required=True)
    p.add_argument("--products", required=True)
    p.set_defaults(func=cmd_check_binary)

    p = sub.add_parser("invocations")
    p.add_argument("--plan", required=True)
    p.set_defaults(func=cmd_invocations)

    p = sub.add_parser("only-testing")
    p.add_argument("--plan", required=True)
    p.add_argument("--index", type=int, required=True)
    p.set_defaults(func=cmd_only_testing)

    p = sub.add_parser("may-uninstall")
    p.add_argument("--plan", required=True)
    p.add_argument("--approved", default="")
    p.set_defaults(func=cmd_may_uninstall)

    p = sub.add_parser("record")
    p.add_argument("--plan", required=True)
    p.add_argument("--index", type=int, required=True)
    p.add_argument("--tests-json")
    p.add_argument("--summary-json")
    p.add_argument("--exit-code", type=int, required=True)
    p.add_argument("--timed-out", default="0")
    p.add_argument("--results", required=True)
    p.set_defaults(func=cmd_record)

    p = sub.add_parser("unit-record")
    p.add_argument("--target", required=True, choices=list(UNIT_TARGETS))
    p.add_argument("--tests-json", required=True)
    p.add_argument("--exit-code", type=int, required=True)
    p.add_argument("--results", required=True)
    p.set_defaults(func=cmd_unit_record)

    p = sub.add_parser("coverage")
    p.add_argument("--plan", required=True)
    p.add_argument("--sample-dir", required=True)
    p.add_argument("--attachments-root", required=True)
    p.add_argument("--results", required=True)
    p.set_defaults(func=cmd_coverage)

    p = sub.add_parser("summary")
    p.add_argument("--plan", required=True)
    p.add_argument("--environment", required=True)
    p.add_argument("--results", required=True)
    p.add_argument("--baseline-dir", required=True)
    p.add_argument("--save-baseline", action="store_true")
    p.add_argument("--approved", default="")
    p.set_defaults(func=cmd_summary)

    p = sub.add_parser("hashes")
    p.add_argument("--tests-dir", required=True)
    p.set_defaults(func=cmd_hashes)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except RunnerError as e:
        return _fail(str(e))


if __name__ == "__main__":
    sys.exit(main())
