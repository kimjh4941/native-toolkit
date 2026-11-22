"""Self-tests of `scripts/test_ios.sh --capi` and of its decisions in scripts/ios_capi_runner.py.

C ABI design part 1, C-6 and 6.1; part 2, TB-12. Each case breaks one thing a step must notice (a failed
or skipped test, a sanitizer report, a sanitizer that was not on, a failed or silently skipped check, a
smoke that did not run on the simulator) and asserts that the run fails, next to the run that passes.

The shell cases run test_ios.sh from start to end in a copy of scripts/, with xcodebuild, xcrun, otool
and pgrep replaced by fakes that only record, and with the four scripts the option calls (the build of
the distributable, check_ios_dist.py, check_c_abi_contract_ios.py and the smoke) replaced in the copy
by stand-ins that record their arguments: those scripts have their own self-tests. No simulator, no
device.

Run: python3 -m unittest discover -s scripts/tests
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ios_capi_runner as c  # noqa: E402
import test_ios_ui_runner as base  # noqa: E402  (its TestCase classes are not bound here, so they run once)

SIMULATOR = base.SIMULATOR
FAKE_DEVICE = base.FAKE_DEVICE
ASAN_LINE = "\t@rpath/libclang_rt.asan_iossim_dynamic.dylib (compatibility version 0.0.0, current version 0.0.0)"
TSAN_LINE = "\t@rpath/libclang_rt.tsan_iossim_dynamic.dylib (compatibility version 0.0.0, current version 0.0.0)"
SYSTEM_LINE = "\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)"


def passed_summary(total=474):
    return {"result": "Passed", "totalTestCount": total, "passedTests": total, "failedTests": 0, "skippedTests": 0,
            "expectedFailures": 0}


class Version(unittest.TestCase):
    def test_the_three_numbers(self):
        text = "#define NTK_VERSION_MAJOR 2\n#define NTK_VERSION_MINOR 0\n#define NTK_VERSION_PATCH 0\n"
        self.assertEqual(c.library_version(text), "2.0.0")

    def test_the_tree_s_common_h(self):
        text = (ROOT / "ios" / "IosLibraryCApi" / "include" / "NativeToolkitC" / "Common.h").read_text(encoding="utf-8")
        self.assertRegex(c.library_version(text), r"^\d+\.\d+\.\d+$")

    def test_a_missing_or_repeated_number_stops(self):
        for text in ("#define NTK_VERSION_MAJOR 2\n#define NTK_VERSION_MINOR 0\n",
                     "#define NTK_VERSION_MAJOR 2\n#define NTK_VERSION_MAJOR 3\n#define NTK_VERSION_MINOR 0\n#define NTK_VERSION_PATCH 0\n"):
            with self.subTest(text=text):
                with self.assertRaises(c.RunnerError):
                    c.library_version(text)


class Xcode(unittest.TestCase):
    def test_the_c_abi_s_xcode_passes_and_another_is_told_how_to_choose(self):
        self.assertIsNone(c.xcode_problem("Xcode 26.6 Build version 17F31"))
        self.assertIsNone(c.xcode_problem("Xcode 26.6.1 Build version 17F40"))
        problem = c.xcode_problem("Xcode 26.3 Build version 17C529")
        self.assertIn("DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer", problem)
        self.assertIn("--capi", problem)
        self.assertIsNotNone(c.xcode_problem("Xcode 26.60 Build version 1"))


class SanitizerReports(unittest.TestCase):
    def test_the_forms_of_a_report_are_found(self):
        for line in ("==4242==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000010",
                     "WARNING: ThreadSanitizer: data race (pid=4242)",
                     "SUMMARY: ThreadSanitizer: data race Registry.swift:12 in transition",
                     "SUMMARY: AddressSanitizer: stack-buffer-overflow",
                     "Handle.swift:40:7: runtime error: load of misaligned address",
                     "==1==ERROR: LeakSanitizer: detected memory leaks"):
            with self.subTest(line=line):
                self.assertEqual(c.sanitizer_reports("before\n" + line + "\nafter"), [line])

    def test_a_deadly_signal_a_failed_check_a_fatal_stop_and_tsan_s_count_are_found(self):
        # Each form alone, without an ERROR or SUMMARY line next to it (review B, Codex).
        for line in ("AddressSanitizer:DEADLYSIGNAL",
                     "ThreadSanitizer:DEADLYSIGNAL",
                     "==4242==AddressSanitizer: CHECK failed: asan_allocator.cpp:190 \"((m->chunk_state)) == ((CHUNK_QUARANTINE))\"",
                     "ThreadSanitizer: CHECK failed: tsan_rtl.cpp:12 \"((x)) != (0)\" (0x0, 0x0) (tid=4242)",
                     "FATAL: ThreadSanitizer: unexpected memory mapping 0x7fff00000000-0x7fff00001000",
                     "FATAL: AddressSanitizer: failed to intercept 'memcpy'",
                     "FATAL: Memory layout is incompatible with TSan.",
                     "ThreadSanitizer: reported 1 warnings",
                     "ThreadSanitizer: reported 12 warnings"):
            with self.subTest(line=line):
                self.assertEqual(c.sanitizer_reports("before\n" + line + "\nafter"), [line])

    def test_ordinary_lines_are_not(self):
        text = ("Test Case '-[IosLibraryCApiTests.ThreadContractTests testX]' passed (0.010 seconds).\n"
                "testAddressSanitizerIsOn passed\nThreadSanitizer\n** TEST SUCCEEDED **\n"
                "ThreadSanitizer: reported 0 warnings\nThreadSanitizer: reported 01 warnings\n"
                "a CHECK failed: elsewhere\nAddressSanitizer:DEADLY\n")
        self.assertEqual(c.sanitizer_reports(text), [])


class Runtimes(unittest.TestCase):
    def otool(self, *lines):
        return {framework: f"/x/{framework}:\n" + "\n".join(lines) for framework in c.FRAMEWORKS}

    def test_each_variant_loads_its_runtime_and_no_other(self):
        self.assertEqual(c.runtime_problems("normal", self.otool(SYSTEM_LINE)), [])
        self.assertEqual(c.runtime_problems("asan", self.otool(SYSTEM_LINE, ASAN_LINE)), [])
        self.assertEqual(c.runtime_problems("tsan", self.otool(SYSTEM_LINE, TSAN_LINE)), [])

    def test_a_missing_or_wrong_runtime_fails(self):
        for variant, lines in (("asan", (SYSTEM_LINE,)), ("tsan", (SYSTEM_LINE, ASAN_LINE)), ("normal", (TSAN_LINE,)),
                               ("asan", (ASAN_LINE, TSAN_LINE))):
            with self.subTest(variant=variant, lines=lines):
                self.assertEqual(len(c.runtime_problems(variant, self.otool(*lines))), len(c.FRAMEWORKS))

    def test_one_framework_without_the_runtime_or_without_a_listing_fails(self):
        otool = self.otool(ASAN_LINE)
        otool["IosLibrary"] = "/x/IosLibrary:\n" + SYSTEM_LINE
        self.assertEqual(len(c.runtime_problems("asan", otool)), 1)
        del otool["IosLibrary"]
        self.assertIn("no otool -L", c.runtime_problems("asan", otool)[0])


class Summary(unittest.TestCase):
    def test_every_test_passed(self):
        self.assertEqual(c.summary_problems(passed_summary()), ([], 474))

    def test_a_failed_skipped_expected_failure_or_empty_run_fails(self):
        for change in ({"failedTests": 1, "passedTests": 473, "result": "Failed"}, {"skippedTests": 1, "passedTests": 473},
                       {"expectedFailures": 1, "passedTests": 473}, {"totalTestCount": 0}, {"result": "Failed"},
                       {"totalTestCount": None}):
            with self.subTest(change=change):
                summary = dict(passed_summary(), **change)
                self.assertTrue(c.summary_problems(summary)[0])


class Records(unittest.TestCase):
    def setUp(self):
        self.temp = pathlib.Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.temp)

    def write(self, name, text):
        path = self.temp / name
        path.write_text(text)
        return str(path)

    def unit(self, variant="asan", summary=None, output="Test Suite passed\n", runtime=ASAN_LINE, code=0, timed_out=False):
        summary_path = self.write("summary.json", json.dumps(summary or passed_summary())) if summary != "missing" else "/nonexistent"
        logs = [("test log", self.write("test.log", "** TEST SUCCEEDED **\n"))]
        logs.append(("action log", self.write("action.json", json.dumps({"emittedOutput": output})) if output is not None else "/nonexistent"))
        otool = [(f, self.write(f"otool-{f}.txt", f"/x/{f}:\n{SYSTEM_LINE}\n{runtime}\n")) for f in c.FRAMEWORKS]
        return c.unit_record(variant, code, timed_out, summary_path, logs, otool)

    def test_a_clean_variant_passes(self):
        record = self.unit()
        self.assertEqual((record["status"], record["tests"], record["step"]), ("PASS", 474, "unit-asan"), record)

    def test_each_problem_fails_the_variant(self):
        for name, kwargs in (("report", {"output": "==1==ERROR: AddressSanitizer: heap-use-after-free\n"}),
                             ("no action log", {"output": None}),
                             ("no summary", {"summary": "missing"}),
                             ("failed test", {"summary": dict(passed_summary(), failedTests=1, passedTests=473, result="Failed")}),
                             ("no runtime", {"runtime": ""}),
                             ("exit status", {"code": 65}),
                             ("time limit", {"code": 142, "timed_out": True})):
            with self.subTest(name):
                self.assertEqual(self.unit(**kwargs)["status"], "FAIL")

    def contract(self, *lines, title="== C ABI contract (iOS)"):
        return "\n".join([title, *lines]) + "\n"

    def test_the_reports_of_the_other_steps(self):
        good = {
            "dist-check": self.contract("  OK   files", "  OK   symbols: 134", title="== iOS distribution /x (library 2.0.0)"),
            "contract-ios-arm64": self.contract("  OK   functions", "  OK   symbols: 134 symbols, 1 architectures"),
            "smoke": "== iOS C ABI smoke (Xcode 26.6, library 2.0.0)\n  PASS simulator build: arm64 x86_64\n"
                     "  PASS device build: arm64\n  PASS simulator run: X: 16 steps\n",
        }
        for step, text in good.items():
            with self.subTest(step=step):
                self.assertEqual(c.report_problems(step, text), [])
        bad = (("dist-check", good["dist-check"] + "  FAIL headers: differ\n"),
               ("dist-check", "== something else\n  OK   files\n"),
               ("dist-check", good["dist-check"] + "  SKIP privacy: no plutil\n"),
               ("contract-ios-arm64", good["contract-ios-arm64"] + "  SKIP compile: no clang\n"),
               ("contract-ios-arm64", self.contract("  OK   functions", "  SKIP symbols: no --library")),
               ("contract-ios-arm64", good["contract-ios-arm64"] + "  FAIL complete: NOT_IMPLEMENTED_YET is not empty\n"),
               ("smoke", good["smoke"].replace("  PASS simulator run: X: 16 steps\n", "")),
               ("smoke", good["smoke"].replace("PASS device build", "FAIL device build")),
               ("smoke", "nothing\n"))
        for step, text in bad:
            with self.subTest(step=step, text=text):
                self.assertTrue(c.report_problems(step, text))

    def test_a_step_that_did_not_run_or_failed_is_a_failure(self):
        self.assertEqual(c.step_record("smoke", 0, False, "", "the distributable was not built")["status"], "FAIL")
        log = self.write("dist.log", "== iOS distribution\n  OK   files\n")
        self.assertEqual(c.step_record("dist-check", 0, False, log, "")["status"], "PASS")
        self.assertEqual(c.step_record("dist-check", 1, False, log, "")["status"], "FAIL")
        self.assertEqual(c.step_record("dist-build", 0, False, "/nonexistent", "")["status"], "FAIL")
        with self.assertRaises(c.RunnerError):
            c.step_record("unit-asan", 0, False, log, "")

    def all_passed(self, counts=(474, 474, 474)):
        records = [{"step": f"unit-{v}", "status": "PASS", "tests": n} for v, n in zip(c.VARIANTS, counts)]
        return records + [{"step": s, "status": "PASS"} for s in c.STEPS if not s.startswith("unit-")]

    def test_the_summary_needs_every_step_once_and_the_same_count(self):
        lines, passed = c.summary(self.all_passed())
        self.assertTrue(passed, lines)
        self.assertEqual(lines[-1], f"[summary] {len(c.STEPS)} passed, 0 problem(s)")
        cases = {
            "missing": self.all_passed()[:-1],
            "twice": self.all_passed() + [{"step": "smoke", "status": "PASS"}],
            "unknown": self.all_passed() + [{"step": "unit-ubsan", "status": "PASS"}],
            "failed": [dict(r, status="FAIL") if r["step"] == "contract-ios-arm64" else r for r in self.all_passed()],
            "counts": self.all_passed((474, 474, 473)),
        }
        for name, records in cases.items():
            with self.subTest(name):
                self.assertFalse(c.summary(records)[1])

    def test_the_steps_are_the_ones_of_tb12(self):
        self.assertEqual(c.STEPS, ("unit-normal", "unit-asan", "unit-tsan", "dist-build", "dist-check",
                                   "contract-ios-arm64", "contract-ios-arm64_x86_64-simulator", "smoke"))
        self.assertEqual(dict(c.SLICES), {"ios-arm64": "arm64", "ios-arm64_x86_64-simulator": "arm64,x86_64"})


CAPI_FAKES = {
    "xcodebuild": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("xcodebuild " + json.dumps(args) + " ALLOW=" + os.environ.get("TEST_RUNNER_NTK_DEVICE_ALLOW", "") + "\n")
def opt(name):
    return args[args.index(name) + 1] if name in args else None
if args == ["-version"]:
    print("Xcode " + os.environ.get("FAKE_XCODE", "26.6")); print("Build version 17F31"); sys.exit(0)
if "test" in args and opt("-scheme") == "IosLibraryCApi":
    variant = "asan" if "-enableAddressSanitizer" in args else "tsan" if "-enableThreadSanitizer" in args else "normal"
    applied = os.environ.get("FAKE_IGNORE_SANITIZER") != variant
    runtime = {"asan": "@rpath/libclang_rt.asan_iossim_dynamic.dylib", "tsan": "@rpath/libclang_rt.tsan_iossim_dynamic.dylib"}
    products = pathlib.Path(opt("-derivedDataPath")) / "Build" / "Products" / "Debug-iphonesimulator"
    for framework in ("IosLibraryCApi", "IosLibrary"):
        folder = products / (framework + ".framework")
        folder.mkdir(parents=True, exist_ok=True)
        lines = ["\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)"]
        if applied and variant in runtime:
            lines.append("\t" + runtime[variant] + " (compatibility version 0.0.0)")
        (folder / framework).write_text("\n".join(lines) + "\n")
    bundle = pathlib.Path(opt("-resultBundlePath"))
    bundle.mkdir(parents=True)
    total = int(os.environ.get("FAKE_UNIT_COUNT_" + variant.upper(), "474"))
    failed = 1 if os.environ.get("FAKE_UNIT_FAIL") == variant else 0
    (bundle / "fake-summary.json").write_text(json.dumps({
        "result": "Failed" if failed else "Passed", "totalTestCount": total, "passedTests": total - failed,
        "failedTests": failed, "skippedTests": 0, "expectedFailures": 0}))
    output = "Test Suite 'All tests' started\n"
    if os.environ.get("FAKE_SANITIZER_REPORT") == variant:
        output += "==4242==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000010\n"
    if os.environ.get("FAKE_SANITIZER_REPORT_IN") != "xcodebuild":
        (bundle / "fake-action.json").write_text(json.dumps({"emittedOutput": output}))
    if os.environ.get("FAKE_SANITIZER_REPORT_IN") != "action":
        print(output)
    print("** TEST FAILED **" if failed else "** TEST SUCCEEDED **")
    sys.exit(65 if failed else 0)
sys.exit(98)
''',
    "xcrun": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("xcrun " + json.dumps(args) + "\n")
fixtures = pathlib.Path(os.environ["FAKE_FIXTURES"])
if args[:3] == ["simctl", "list", "-j"]:
    print((fixtures / ("simctl-devices.json" if args[3] == "devices" else "simctl-runtimes.json")).read_text()); sys.exit(0)
if args[:2] in (["simctl", "shutdown"], ["simctl", "bootstatus"]):
    sys.exit(0)
if args[:1] == ["xcresulttool"]:
    bundle = pathlib.Path(args[args.index("--path") + 1])
    name = "fake-action.json" if args[1:3] == ["get", "log"] else "fake-summary.json"
    if args[1:3] == ["get", "log"] and (args[args.index("--type") + 1] != "action" or os.environ.get("FAKE_NO_ACTION_LOG")):
        sys.exit(1)
    print((bundle / name).read_text()); sys.exit(0)
sys.exit(99)
''',
    "otool": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("otool " + json.dumps(args) + "\n")
if args[0] == "-L":
    print(args[1] + ":")
    print(pathlib.Path(args[1]).read_text(), end="")
    sys.exit(0)
sys.exit(97)
''',
    "pgrep": r'''
import json, os, sys
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("pgrep " + json.dumps(sys.argv[1:]) + "\n")
if os.environ.get("FAKE_PGREP_STATUS"):
    sys.exit(int(os.environ["FAKE_PGREP_STATUS"]))
sys.exit(0 if os.environ.get("FAKE_SIMULATOR_APP_OPEN") else 1)
''',
}

# The scripts --capi calls, replaced in the copy by stand-ins that record their arguments.
STAND_INS = {
    "build_ios_library_xcframework.sh": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("build-script " + json.dumps(args) + "\n")
if os.environ.get("FAKE_DIST_BUILD_FAILS"):
    print("error: the fake archive failed"); sys.exit(65)
out = pathlib.Path(args[args.index("--output-dir") + 1])
version = args[args.index("-v") + 1]
for slice_name in ("ios-arm64", "ios-arm64_x86_64-simulator"):
    if os.environ.get("FAKE_DIST_NO_SLICE") == slice_name:
        continue
    framework = out / f"ios-native-toolkit-capi-{version}.xcframework" / slice_name / "IosLibraryCApi.framework"
    framework.mkdir(parents=True)
    (framework / "IosLibraryCApi").write_text("binary")
print("built")
''',
    "check_ios_dist.py": r'''
import json, os, sys
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("check-dist " + json.dumps(sys.argv[1:]) + "\n")
print("== iOS distribution " + sys.argv[-1] + " (library 2.0.0)")
print("  OK   files")
if os.environ.get("FAKE_DIST_CHECK_FAILS"):
    print("  FAIL headers: include/NativeToolkitC differs"); sys.exit(1)
''',
    "check_c_abi_contract_ios.py": r'''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("contract " + json.dumps(args) + "\n")
library = args[args.index("--library") + 1] if "--library" in args else ""
print("== C ABI contract (iOS)")
print("  OK   functions")
if os.environ.get("FAKE_CONTRACT_SKIP") and os.environ["FAKE_CONTRACT_SKIP"] in library:
    print("  SKIP compile: no clang")
if library:
    print("  OK   symbols: 134 symbols")
if os.environ.get("FAKE_CONTRACT_FAILS") and os.environ["FAKE_CONTRACT_FAILS"] in library:
    print("  FAIL complete: NOT_IMPLEMENTED_YET is not empty"); sys.exit(1)
''',
    "run_ios_capi_smoke.sh": r'''
import json, os, sys
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("smoke " + json.dumps(sys.argv[1:]) + "\n")
print("== iOS C ABI smoke (Xcode 26.6, library 2.0.0)")
print("  PASS simulator build: arm64 x86_64")
print("  PASS device build: arm64")
if os.environ.get("FAKE_SMOKE_FAILS"):
    print("  FAIL simulator run: X: see the log"); sys.exit(1)
if not os.environ.get("FAKE_SMOKE_NO_RUN"):
    print("  PASS simulator run: X: 16 steps")
''',
}


class CApiEndToEnd(unittest.TestCase):
    """`test_ios.sh --capi` from start to end with fakes (EndToEnd's copy of scripts/)."""

    setUp_shared = base.EndToEnd.setUp
    tearDown = base.EndToEnd.tearDown
    run_script = base.EndToEnd.run_script

    def setUp(self):
        self.setUp_shared()
        bin_dir = self.temp / "bin"
        for name, body in CAPI_FAKES.items():
            (bin_dir / name).write_text(f"#!{sys.executable}\n{body}")
            (bin_dir / name).chmod(0o755)
        for name, body in STAND_INS.items():
            path = self.root / "scripts" / name
            path.write_text(f"#!{sys.executable}\n{body}")
            path.chmod(0o755)
        shutil.copytree(base.CAPI_HEADERS, self.root / "ios" / "IosLibraryCApi" / "include" / "NativeToolkitC")
        self.env.pop("FAKE_XCODE", None)

    def run_capi(self, *extra, udid=SIMULATOR):
        finished, log = self.run_script("--udid", udid, "--capi", *extra)
        return finished, log

    def calls(self, log, prefix):
        return [json.loads(line[len(prefix) + 1:].split(" ALLOW=")[0]) for line in log.splitlines() if line.startswith(prefix + " ")]

    def run_folder(self, stdout):
        return pathlib.Path(next(line[len("[out] "):] for line in stdout.splitlines() if line.startswith("[out] ")))

    def assert_nothing_ran(self, log):
        for word in ("build-script", "check-dist", "contract ", "smoke ", '"test"', "devicectl", "platform=iOS,id"):
            self.assertNotIn(word, log)

    def test_every_step_runs_with_its_options_and_passes(self):
        finished, log = self.run_capi()
        self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
        self.assertIn(f"[summary] {len(c.STEPS)} passed, 0 problem(s)", finished.stdout)
        run = self.run_folder(finished.stdout)
        tests = [a for a in self.calls(log, "xcodebuild") if "test" in a]
        self.assertEqual(len(tests), 3)
        flags = []
        for args in tests:
            self.assertEqual(args[args.index("-scheme") + 1], "IosLibraryCApi")
            self.assertIn("-only-testing:IosLibraryCApiTests", args)
            self.assertEqual(args[args.index("-destination") + 1], f"platform=iOS Simulator,id={SIMULATOR}")
            for option in ("-derivedDataPath", "-resultBundlePath"):
                self.assertTrue(args[args.index(option) + 1].startswith(str(run) + "/"), args)
            flags.append([a for a in args if a.startswith("-enable") and a.endswith("Sanitizer")])
        self.assertEqual(flags, [[], ["-enableAddressSanitizer"], ["-enableThreadSanitizer"]])
        self.assertEqual(len({a[a.index("-derivedDataPath") + 1] for a in tests}), 3)
        for line in log.splitlines():
            if line.startswith("xcodebuild "):
                self.assertTrue(line.endswith(" ALLOW="), line)
        build, = self.calls(log, "build-script")
        output = build[build.index("--output-dir") + 1]
        self.assertTrue(output.startswith(str(run) + "/"), output)
        self.assertNotIn("/dist/", output + "/")
        self.assertIn("--keep-project-versions", build)
        self.assertEqual(build[build.index("-v") + 1], "2.0.0")
        self.assertEqual([build[i + 1] for i, a in enumerate(build) if a == "-m"], ["IosLibrary", "IosLibraryCApi"])
        dist, = self.calls(log, "check-dist")
        self.assertEqual(dist, ["--dist", output])
        contracts = self.calls(log, "contract")
        self.assertEqual(len(contracts), 2)
        for args, (slice_name, archs) in zip(contracts, c.SLICES):
            self.assertIn("--require-compile", args)
            self.assertIn("--require-complete", args)
            self.assertEqual(args[args.index("--architectures") + 1], archs)
            self.assertEqual(args[args.index("--library") + 1],
                             f"{output}/ios-native-toolkit-capi-2.0.0.xcframework/{slice_name}/IosLibraryCApi.framework/IosLibraryCApi")
        smoke, = self.calls(log, "smoke")
        self.assertEqual(smoke[smoke.index("--dist") + 1], output)
        self.assertEqual(smoke[smoke.index("--udid") + 1], SIMULATOR)
        self.assertIn("--device-build", smoke)
        self.assertTrue(smoke[smoke.index("--work") + 1].startswith(str(run) + "/"))
        order = [line.split(" ")[0] for line in log.splitlines()
                 if line.split(" ")[0] in ("build-script", "check-dist", "contract", "smoke") or '"test"' in line]
        self.assertEqual(order, ["xcodebuild"] * 3 + ["build-script", "check-dist", "contract", "contract", "smoke"])
        self.assertNotIn("devicectl", log)
        self.assertNotIn("platform=iOS,id", log)
        # The run's folder is under ios/IosLibraryExample/build/; the sample's scheme is never built.
        self.assertNotIn('"IosLibraryExample"', log)

    def test_the_device_is_refused_before_anything_runs(self):
        finished, log = self.run_capi(udid=FAKE_DEVICE)
        self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
        self.assertIn("simulator only", finished.stderr)
        self.assert_nothing_ran(log)

    def test_it_takes_no_other_option(self):
        for extra in (["--capi-ui"], ["--feature", "Dialog"], ["--skip-unit"], ["--dry-run"], ["--baseline"],
                      ["--name-each-test"], ["--device-allow", "systemui"], ["--approved", "x"], ["--devicectl-id", "x"],
                      ["--enumerate-udid", SIMULATOR]):
            with self.subTest(extra=extra):
                finished, log = self.run_capi(*extra)
                self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                self.assert_nothing_ran(log)
        finished, log = self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--dry-run", "--capi")
        self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
        self.assert_nothing_ran(log)

    def test_an_option_cannot_be_taken_as_a_value(self):
        # Re-review B (Codex): `--udid --dry-run --udid <id>` took --dry-run as a value and hid it.
        for mode in ("--capi", "--capi-ui"):
            for option in ("--dry-run", "--feature", "--skip-unit"):
                with self.subTest(mode=mode, option=option):
                    finished, log = self.run_script("--udid", option, "--udid", SIMULATOR, mode)
                    self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                    self.assertIn("--udid needs a value", finished.stderr)
                    self.assert_nothing_ran(log)
        finished, log = self.run_script("--udid", SIMULATOR, "--capi", "--feature")
        self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
        self.assertIn("--feature needs a value", finished.stderr)

    def test_an_option_with_an_empty_value_is_refused_too(self):
        # Review B (Codex): whether an option was given counts, not its value; --capi-ui the same.
        for mode in ("--capi", "--capi-ui"):
            for option in ("--feature", "--enumerate-udid", "--approved", "--devicectl-id", "--device-allow"):
                with self.subTest(mode=mode, option=option):
                    finished, log = self.run_script("--udid", SIMULATOR, mode, option, "")
                    self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                    self.assertIn(f"{mode} takes no other option but --udid", finished.stderr)
                    self.assert_nothing_ran(log)
                    self.assertNotIn("simctl", log)

    def test_another_xcode_or_an_open_simulator_app_stops_it_before_anything_runs(self):
        for env, word in (({"FAKE_XCODE": "26.3"}, "DEVELOPER_DIR=/Applications/Xcode26.6.app"),
                          ({"FAKE_SIMULATOR_APP_OPEN": "1"}, "Simulator.app is open"),
                          # Review C-c: only status 1 (no match) says that it is closed.
                          ({"FAKE_PGREP_STATUS": "2"}, "pgrep failed (status 2)"),
                          ({"FAKE_PGREP_STATUS": "3"}, "pgrep failed (status 3)")):
            with self.subTest(env=env):
                self.env.update(env)
                finished, log = self.run_capi()
                for key in env:
                    del self.env[key]
                self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                self.assertIn(word, finished.stderr)
                self.assert_nothing_ran(log)

    def test_each_failure_fails_the_run_and_the_other_steps_still_run(self):
        cases = (
            ("a failed test with ASan", {"FAKE_UNIT_FAIL": "asan"}, "FAIL unit-asan"),
            ("an ASan report in a run that passed", {"FAKE_SANITIZER_REPORT": "asan"}, "sanitizer report"),
            ("a TSan run without TSan", {"FAKE_IGNORE_SANITIZER": "tsan"}, "FAIL unit-tsan"),
            ("an ASan report without a sanitizer", {"FAKE_SANITIZER_REPORT": "normal"}, "FAIL unit-normal"),
            ("no action log", {"FAKE_NO_ACTION_LOG": "1"}, "no action log"),
            ("an ASan report in the xcodebuild log only", {"FAKE_SANITIZER_REPORT": "asan", "FAKE_SANITIZER_REPORT_IN": "xcodebuild"},
             "in the test log"),
            ("a TSan report in the action log only", {"FAKE_SANITIZER_REPORT": "tsan", "FAKE_SANITIZER_REPORT_IN": "action"},
             "in the action log"),
            ("fewer tests in one variant", {"FAKE_UNIT_COUNT_TSAN": "473"}, "different numbers of tests"),
            ("the distributable's check", {"FAKE_DIST_CHECK_FAILS": "1"}, "FAIL dist-check"),
            ("the contract on the device slice", {"FAKE_CONTRACT_FAILS": "/ios-arm64/"}, "FAIL contract-ios-arm64:"),
            ("a SKIP in the contract", {"FAKE_CONTRACT_SKIP": "simulator"}, "FAIL contract-ios-arm64_x86_64-simulator"),
            ("a missing slice", {"FAKE_DIST_NO_SLICE": "ios-arm64_x86_64-simulator"}, "not run: no "),
            ("the smoke", {"FAKE_SMOKE_FAILS": "1"}, "FAIL smoke"),
            ("a smoke that did not run on the simulator", {"FAKE_SMOKE_NO_RUN": "1"}, "no PASS simulator run"),
        )
        for name, env, word in cases:
            with self.subTest(name):
                self.env.update(env)
                finished, log = self.run_capi()
                for key in env:
                    del self.env[key]
                self.assertEqual(finished.returncode, 1, finished.stdout + finished.stderr)
                self.assertIn(word, finished.stdout)
                self.assertEqual(len(self.calls(log, "smoke")), 1, name)

    def test_a_failed_build_of_the_distributable_skips_what_needs_it_and_fails(self):
        self.env["FAKE_DIST_BUILD_FAILS"] = "1"
        finished, log = self.run_capi()
        self.assertEqual(finished.returncode, 1, finished.stdout + finished.stderr)
        self.assertIn("FAIL dist-build", finished.stdout)
        for step in ("dist-check", "contract-ios-arm64", "contract-ios-arm64_x86_64-simulator", "smoke"):
            self.assertIn(f"FAIL {step}: not run: the distributable was not built", finished.stdout)
        for word in ("check-dist", "contract ", "smoke "):
            self.assertNotIn(word, log)

    def test_the_sample_s_runs_never_reach_these_steps(self):
        base_fakes = self.temp / "bin"
        for name, body in base.FAKE_TOOLS.items():
            (base_fakes / name).write_text(f"#!{sys.executable}\n{body}")
        self.env["FAKE_XCODE"] = "26.3"
        (self.temp / "tests.json").write_text(base.fixture("xcresult-d1-tests.json"))
        for args in (["--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--dry-run", "--device-allow", "systemui"],
                     ["--udid", SIMULATOR, "--dry-run"]):
            with self.subTest(args=args):
                finished, log = self.run_script(*args)
                self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
                self.assertNotIn("IosLibraryCApi", log + finished.stdout)
                self.assertNotIn("Sanitizer", log)
                for word in ("build-script", "check-dist", "contract ", "smoke "):
                    self.assertNotIn(word, log)


class TimeLimit(unittest.TestCase):
    """`capped_group` of test_ios.sh (review B, Codex): the build of the distributable and the smoke are
    scripts that start xcodebuild and simctl; when the time is up nothing of them may stay behind."""

    def run_bash(self, body, timeout=60):
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, NTK_TEST_IOS_SOURCE_ONLY="1", WORK=d)
            script = f'source "{ROOT / "scripts" / "test_ios.sh"}"\n{body}\n'
            finished = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env, timeout=timeout)
            files = {p.name: p.read_text().strip() for p in pathlib.Path(d).iterdir()}
            return finished, files

    def test_the_time_limit_kills_the_command_and_what_it_started(self):
        # A script that starts a child and a grandchild (the shape of xcodebuild under the build script). Their
        # output goes to /dev/null so that no pipe waits for them, and whether each is still running is read
        # right after capped_group returns; whatever is left is ended afterwards.
        body = ('''set +e
capped_group 1 bash -c 'sleep 30 > /dev/null 2>&1 & echo $! > "$WORK/child"; bash -c "sleep 30 > /dev/null 2>&1 & echo \\$! > \\"$WORK/grandchild\\"; wait" > /dev/null 2>&1 & wait'
echo "$?" > "$WORK/status"
sleep 0.5
for name in child grandchild; do
  if kill -0 "$(cat "$WORK/$name")" 2>/dev/null; then echo running > "$WORK/$name-state"; kill "$(cat "$WORK/$name")"; else echo gone > "$WORK/$name-state"; fi
done''')
        started = time.monotonic()
        finished, files = self.run_bash(body)
        self.assertLess(time.monotonic() - started, 20, "something kept the run waiting")
        self.assertEqual(files.get("status"), "142", finished.stderr)
        for name in ("child", "grandchild"):
            self.assertEqual(files.get(f"{name}-state"), "gone", f"the {name} is still running")

    def test_an_interrupt_kills_the_command_and_what_it_started(self):
        # Re-review B (Codex): Ctrl-C reaches the terminal's foreground group, not the command's own group.
        body = ('''set +e
capped_group 30 bash -c 'sleep 30 > /dev/null 2>&1 & echo $! > "$WORK/child"; wait' &
watcher=$!
for _ in $(seq 50); do [[ -s "$WORK/child" ]] && break; sleep 0.1; done
# The signal goes to the perl that capped_group runs (the background subshell's child), as Ctrl-C
# would reach it in the terminal's foreground group.
kill -TERM "$(pgrep -P "$watcher" perl)"
wait "$watcher"
echo "$?" > "$WORK/status"
sleep 0.5
if kill -0 "$(cat "$WORK/child")" 2>/dev/null; then echo running > "$WORK/child-state"; kill "$(cat "$WORK/child")"; else echo gone > "$WORK/child-state"; fi''')
        started = time.monotonic()
        finished, files = self.run_bash(body)
        self.assertLess(time.monotonic() - started, 20, "something kept the run waiting")
        self.assertEqual(files.get("status"), "143", finished.stderr)
        self.assertEqual(files.get("child-state"), "gone", "the child is still running")

    def test_the_command_s_own_status_and_no_stdin(self):
        finished, files = self.run_bash('''set +e
capped_group 30 bash -c 'read -r line; echo "read=$?" > "$WORK/read"; exit 3'
echo "$?" > "$WORK/status"''')
        self.assertEqual(files.get("status"), "3", finished.stderr)
        self.assertEqual(files.get("read"), "read=1")  # stdin is /dev/null: read ends at once

    def test_a_bad_time_limit_is_refused(self):
        finished, files = self.run_bash('''set +e
capped_group 0 true
echo "$?" > "$WORK/status"''')
        self.assertNotEqual(files.get("status"), "0", finished.stderr)

    def test_the_build_and_the_smoke_use_it(self):
        text = (ROOT / "scripts" / "test_ios.sh").read_text(encoding="utf-8").replace("\\\n", " ")
        # --capi and --capi-device each call both scripts once.
        for script in ("build_ios_library_xcframework.sh", "run_ios_capi_smoke.sh"):
            lines = [line.strip() for line in text.splitlines() if f'"${{ROOT_DIR}}/scripts/{script}"' in line]
            self.assertEqual(len(lines), 2, script)
            for line in lines:
                self.assertTrue(line.startswith("capped_group 3600 "), line)


class Commands(unittest.TestCase):
    def test_the_command_line(self):
        script = ROOT / "scripts" / "ios_capi_runner.py"
        common_h = ROOT / "ios" / "IosLibraryCApi" / "include" / "NativeToolkitC" / "Common.h"
        finished = subprocess.run([sys.executable, str(script), "version", "--common-h", str(common_h)],
                                  capture_output=True, text=True)
        self.assertEqual(finished.returncode, 0, finished.stderr)
        finished = subprocess.run([sys.executable, str(script), "check-xcode", "--xcode", "Xcode 26.3 Build version 1"],
                                  capture_output=True, text=True)
        self.assertEqual(finished.returncode, 2)
        with tempfile.TemporaryDirectory() as temp:
            results = pathlib.Path(temp) / "results.jsonl"
            results.write_text("")
            finished = subprocess.run([sys.executable, str(script), "summary", "--results", str(results)],
                                      capture_output=True, text=True)
            self.assertEqual(finished.returncode, 1)
            self.assertIn("recorded 0 times", finished.stdout)


# --- --capi-device (stage 2 working notes, 17.1 decision 4; 17.3 review) ----------------------------------------

FAKE_TEAM = "ABCDE12345"  # not a real team; only in the copy's project
FAKE_DEVICECTL_ID = "DCID-0000"
FAKE_UNIT_TESTS = ("CApiStringInputTests/testA()", "ClipboardEntryTests/testB()", "ThreadContractTests/testC()")
SMOKE_LINES = ["SMOKE PASS " + (s.replace("callbacks: ", "callbacks: ", 1) + ": ok") for s in c.SMOKE_STEPS]
DEVICE_FAKES = {
    "xcodebuild": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    seen = ",".join(n for n in sorted(os.environ) if n in ("XCODE_XCCONFIG_FILE", "TOOLCHAINS") or n.startswith("TEST_RUNNER_"))
    log.write("xcodebuild " + json.dumps(args) + " ALLOW=" + os.environ.get("TEST_RUNNER_NTK_DEVICE_ALLOW", "") + "\n")
    log.write("xcodebuild-env " + seen + "\n")
    ledger = pathlib.Path(os.environ["FAKE_LEDGER"])
    log.write("xcodebuild-ledger " + (ledger.read_text() if ledger.exists() else "").replace("\n", "|") + "\n")
def opt(name):
    return args[args.index(name) + 1] if name in args else None
tests = json.loads(os.environ["FAKE_UNIT_TESTS"])
if args == ["-version"]:
    print("Xcode " + os.environ.get("FAKE_XCODE", "26.6")); print("Build version 17F31"); sys.exit(0)
if "build-for-testing" in args:
    products = pathlib.Path(opt("-derivedDataPath")) / "Build" / "Products"
    products.mkdir(parents=True, exist_ok=True)
    (products / "IosLibraryCApi_iphonesimulator26.2-arm64.xctestrun").write_text("")
    sys.exit(0)
if "-enumerate-tests" in args:
    enabled = [{"identifier": "IosLibraryCApiTests/" + t} for t in tests] + [{"identifier": "IosLibraryCApiTests/ThreadContractTests"}]
    pathlib.Path(opt("-test-enumeration-output-path")).write_text(json.dumps({"errors": [], "values": [{"enabledTests": enabled}]}))
    sys.exit(0)
if "test" in args and opt("-scheme") == "IosLibraryCApi" and (opt("-destination") or "").startswith("platform=iOS,id="):
    products = pathlib.Path(opt("-derivedDataPath")) / "Build" / "Products" / "Debug-iphoneos"
    runtime = os.environ.get("FAKE_DEVICE_RUNTIME", "@rpath/libclang_rt.asan_ios_dynamic.dylib")
    for framework in ("IosLibraryCApi", "IosLibrary"):
        folder = products / (framework + ".framework")
        folder.mkdir(parents=True, exist_ok=True)
        lines = ["\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)"]
        if runtime and "-enableAddressSanitizer" in args:
            lines.append("\t" + runtime + " (compatibility version 0.0.0)")
        (folder / framework).write_text("\n".join(lines) + "\n")
    bundle = pathlib.Path(opt("-resultBundlePath"))
    bundle.mkdir(parents=True)
    ran = [t for t in tests if t != os.environ.get("FAKE_DROP_TEST")]
    failed = 1 if os.environ.get("FAKE_UNIT_FAIL") == "asan" else 0
    cases = [{"nodeType": "Test Case", "nodeIdentifier": t, "result": "Failed" if failed and i == 0 else "Passed"}
             for i, t in enumerate(ran)]
    (bundle / "fake-tests.json").write_text(json.dumps({"testNodes": [{"nodeType": "Unit test bundle", "children": cases}]}))
    (bundle / "fake-summary.json").write_text(json.dumps({
        "result": "Failed" if failed else "Passed", "totalTestCount": len(ran), "passedTests": len(ran) - failed,
        "failedTests": failed, "skippedTests": 0, "expectedFailures": 0}))
    output = "Test Suite 'All tests' started\n"
    if os.environ.get("FAKE_SANITIZER_REPORT") == "asan":
        output += "==4242==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000010 at /private/secret/path.c\n"
    (bundle / "fake-action.json").write_text(json.dumps({"emittedOutput": output}))
    print(output)
    sys.exit(65 if failed else 0)
sys.exit(98)
''',
    "xcrun": r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("xcrun " + json.dumps(args) + "\n")
    if args[:1] == ["devicectl"]:
        ledger = pathlib.Path(os.environ["FAKE_LEDGER"])
        log.write("devicectl-ledger " + (ledger.read_text() if ledger.exists() else "").replace("\n", "|") + "\n")
fixtures = pathlib.Path(os.environ["FAKE_FIXTURES"])
if args[:3] == ["simctl", "list", "-j"]:
    print((fixtures / ("simctl-devices.json" if args[3] == "devices" else "simctl-runtimes.json")).read_text()); sys.exit(0)
if args[:2] == ["simctl", "shutdown"]:
    sys.exit(0)
if args[:1] == ["xcresulttool"]:
    bundle = pathlib.Path(args[args.index("--path") + 1])
    name = "fake-action.json" if args[1:3] == ["get", "log"] else "fake-tests.json" if "tests" in args else "fake-summary.json"
    print((bundle / name).read_text()); sys.exit(0)
if args[:4] == ["devicectl", "device", "info", "details"]:
    out = args[args.index("--json-output") + 1]
    pathlib.Path(out).write_text(json.dumps({"result": {
        "hardwareProperties": {"udid": os.environ.get("FAKE_INFO_UDID", os.environ["FAKE_DEVICE"]), "marketingName": "iPhone XS"},
        "deviceProperties": {"osVersionNumber": "18.7.2", "name": "Some Owner's iPhone"}}}))
    print("Some Owner's iPhone details written")
    sys.exit(0)
if args[:4] == ["devicectl", "device", "install", "app"]:
    print("App installed on Some Owner's iPhone")
    sys.exit(1 if os.environ.get("FAKE_INSTALL_FAILS") else 0)
if args[:4] == ["devicectl", "device", "process", "launch"]:
    print("Launched application on Some Owner's iPhone")
    lines = json.loads(os.environ["FAKE_SMOKE_LINES"])
    run = os.environ.get("FAKE_SMOKE_RUN", "pass")
    if run == "missing-step":
        lines = [l for l in lines if not l.startswith("SMOKE PASS dialog cancel:")]
    if run == "repeated-step":
        lines = lines + [lines[0]]
    print("\n".join(lines))
    if run == "fail":
        print("SMOKE FAIL dialog: completion 3")
        print("SMOKE RESULT FAIL failures=1")
    elif run == "result-fail":
        print("SMOKE RESULT FAIL failures=1")
    elif run != "no-result":
        print("SMOKE RESULT PASS failures=0")
    sys.exit(0)
sys.exit(99)
''',
}
DEVICE_SMOKE_STAND_IN = r'''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    seen = ",".join(n for n in sorted(os.environ) if n in ("XCODE_XCCONFIG_FILE", "TOOLCHAINS") or n.startswith("TEST_RUNNER_"))
    log.write("smoke " + json.dumps(args) + " ENV=" + seen + " TEAM=" + os.environ.get("NTK_SMOKE_DEVELOPMENT_TEAM", "") + "\n")
work = pathlib.Path(args[args.index("--work") + 1])
app = work / "dd-device" / "Build" / "Products" / "Release-iphoneos" / "IosLibraryCApiSmoke.app"
print("== iOS C ABI smoke (Xcode 26.6, library 2.0.0)")
print("  PASS simulator build: arm64 x86_64")
if os.environ.get("FAKE_SIGNED_BUILD_FAILS"):
    print("  FAIL device build (signed): see the log"); sys.exit(1)
app.mkdir(parents=True)
for line in ("device build (signed): arm64", "device embeds: IosLibrary.framework IosLibraryCApi.framework",
             "device needs no Swift library", "device imports nothing of IosLibrary"):
    print("  PASS " + line)
'''


class CApiDeviceEndToEnd(unittest.TestCase):
    """`test_ios.sh --capi-device` from start to end with fakes: nothing reaches a device."""

    setUp_shared = base.EndToEnd.setUp
    tearDown = base.EndToEnd.tearDown
    run_script = base.EndToEnd.run_script

    def setUp(self):
        self.setUp_shared()
        bin_dir = self.temp / "bin"
        for name, body in dict(CAPI_FAKES, **DEVICE_FAKES).items():
            (bin_dir / name).write_text(f"#!{sys.executable}\n{body}")
            (bin_dir / name).chmod(0o755)
        # The real smoke script stays in the copy under another name, for the direct calls of its gate.
        shutil.copy(self.root / "scripts" / "run_ios_capi_smoke.sh", self.root / "scripts" / "real_run_ios_capi_smoke.sh")
        for name, body in dict(STAND_INS, **{"run_ios_capi_smoke.sh": DEVICE_SMOKE_STAND_IN}).items():
            path = self.root / "scripts" / name
            path.write_text(f"#!{sys.executable}\n{body}")
            path.chmod(0o755)
        shutil.copytree(base.CAPI_HEADERS, self.root / "ios" / "IosLibraryCApi" / "include" / "NativeToolkitC")
        project = self.root / "ios" / "IosLibraryCApi" / "IosLibraryCApi.xcodeproj"
        project.mkdir(parents=True)
        (project / "project.pbxproj").write_text(
            "".join(f"\t\t\t\tDEVELOPMENT_TEAM = {FAKE_TEAM};\n" for _ in range(6)) + "\t\t\t\tDEVELOPMENT_TEAM = \"\";\n")
        self.env.pop("FAKE_XCODE", None)
        self.env["FAKE_UNIT_TESTS"] = json.dumps(FAKE_UNIT_TESTS)
        self.env["FAKE_SMOKE_LINES"] = json.dumps(SMOKE_LINES)
        self.build_root = self.root / "ios" / "IosLibraryExample" / "build" / "test_ios"

    def dry_run(self):
        finished, log = self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--capi-device", "--dry-run")
        self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
        approvals = sorted(self.build_root.glob("*-capi-device*/approval.json"))
        return finished, log, approvals[-1]

    def run_approved(self, approval):
        return self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--capi-device", "--approved",
                               str(approval), "--devicectl-id", FAKE_DEVICECTL_ID)

    def device_lines(self, log):
        return [line for line in log.splitlines() if "platform=iOS,id" in line or line.startswith('xcrun ["devicectl"')
                or "--signed-device-build" in line]

    def assert_no_device(self, log):
        self.assertEqual(self.device_lines(log), [])
        for word in ("build-script", "smoke "):
            self.assertNotIn(word, log)

    def assert_no_udid(self, finished):
        # Review B-1: the hardware UDID is never printed, nor the device's name.
        self.assertNotIn(FAKE_DEVICE, finished.stdout + finished.stderr)
        self.assertNotIn("Some Owner", finished.stdout + finished.stderr)

    def test_the_dry_run_writes_the_list_and_never_reaches_the_device(self):
        finished, log, approval = self.dry_run()
        self.assert_no_device(log)
        self.assert_no_udid(finished)
        self.assertNotIn("devicectl", log)
        sims = [json.loads(line[len("xcodebuild "):line.rindex(" ALLOW=")]) for line in log.splitlines()
                if line.startswith("xcodebuild [")]
        self.assertEqual(sims[0], ["-version"])
        for args in sims[1:]:
            self.assertEqual(args[args.index("-destination") + 1], f"platform=iOS Simulator,id={SIMULATOR}")
        data = json.loads(approval.read_text())
        self.assertEqual(data["kind"], "capi-device")
        self.assertEqual(data["udid"], FAKE_DEVICE)
        self.assertEqual(data["expectedTests"], sorted(FAKE_UNIT_TESTS))
        self.assertEqual([a["step"] for a in data["actions"]], ["device-identity"] + list(c.DEVICE_STEPS))
        self.assertEqual([a["bundleId"] for a in data["leftOnDevice"]],
                         ["com.jonghyunkim.nativetoolkit.IosLibraryCApiTestHost", c.SMOKE_BUNDLE_ID])
        for word in ("approval ID", "LEFT ON THE DEVICE", "REMOVAL", "SIGNING", "DEVICE device-smoke-run",
                     "DEVICE device-identity", "mac    device-smoke-build", "EXPECTED TESTS: 3 of IosLibraryCApiTests"):
            self.assertIn(word, finished.stdout)
        self.assertNotIn(FAKE_TEAM, finished.stdout + approval.read_text())
        self.assertFalse(self.ledger.exists(), "a dry run consumed nothing")
        self.assertEqual(sorted(p.name for p in self.temp.glob("test_ios-device.*")), [])

    def test_without_an_approval_or_with_other_options_nothing_runs(self):
        for extra in ([], ["--approved", "x"], ["--devicectl-id", "x"], ["--approved", "", "--devicectl-id", "x"],
                      ["--dry-run", "--approved", "x"], ["--dry-run", "--devicectl-id", "x"], ["--dry-run", "--capi"],
                      ["--dry-run", "--capi-ui"], ["--dry-run", "--feature", "Dialog"], ["--dry-run", "--device-allow", ""],
                      ["--dry-run", "--skip-unit"], ["--dry-run", "--baseline"]):
            with self.subTest(extra=extra):
                finished, log = self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--capi-device", *extra)
                self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                self.assert_no_device(log)
                self.assertNotIn("simctl", log)
        finished, log = self.run_script("--udid", FAKE_DEVICE, "--capi-device", "--dry-run")
        self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
        self.assertIn("needs --enumerate-udid", finished.stderr)
        finished, log = self.run_script("--udid", SIMULATOR, "--enumerate-udid", SIMULATOR, "--capi-device", "--dry-run")
        self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
        self.assertIn("device only", finished.stderr)
        self.assert_no_device(log)
        for env, word in (({"FAKE_XCODE": "26.3"}, "--capi-device needs Xcode 26.6"),
                          ({"FAKE_SIMULATOR_APP_OPEN": "1"}, "Simulator.app is open")):
            with self.subTest(env=env):
                self.env.update(env)
                finished, log = self.run_script("--udid", FAKE_DEVICE, "--enumerate-udid", SIMULATOR, "--capi-device", "--dry-run")
                for key in env:
                    del self.env[key]
                self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                self.assertIn(word, finished.stderr)
                self.assertFalse(list(self.build_root.glob("*-capi-device*/approval.json")))

    def test_an_approved_run_passes_and_leaves_nothing_of_the_device(self):
        _, _, approval = self.dry_run()
        approval_id = json.loads(approval.read_text())["approvalId"]
        # Review B5: nothing from outside the list reaches the device's builds.
        self.env.update({"XCODE_XCCONFIG_FILE": "/tmp/evil.xcconfig", "TOOLCHAINS": "evil", "TEST_RUNNER_DYLD_INSERT": "x"})
        finished, log = self.run_approved(approval)
        self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
        self.assertIn(f"[summary] {len(c.DEVICE_STEPS)} passed, 0 problem(s) (the device)", finished.stdout)
        self.assert_no_udid(finished)
        lines = log.splitlines()
        device_tmp = str(self.temp.resolve() / "test_ios-device.")
        test_index = next(i for i, line in enumerate(lines) if line.startswith("xcodebuild [") and "platform=iOS,id=" in line)
        test = json.loads(lines[test_index][len("xcodebuild "):lines[test_index].rindex(" ALLOW=")])
        self.assertEqual(test[test.index("-destination") + 1], f"platform=iOS,id={FAKE_DEVICE}")
        for word in ("-allowProvisioningUpdates", "-enableAddressSanitizer", "-only-testing:IosLibraryCApiTests"):
            self.assertIn(word, test)
        self.assertEqual(test[test.index("-collect-test-diagnostics") + 1], "never")
        for option in ("-derivedDataPath", "-resultBundlePath"):
            self.assertTrue(test[test.index(option) + 1].startswith(device_tmp), test)
        self.assertEqual(lines[test_index + 1], "xcodebuild-env ")
        self.assertIn(approval_id, lines[test_index + 2])
        smoke = next(line for line in lines if line.startswith("smoke "))
        self.assertIn("--signed-device-build", smoke)
        self.assertNotIn("--udid", smoke)
        self.assertIn(" ENV= TEAM=" + FAKE_TEAM, smoke)
        devicectl = [json.loads(line[len("xcrun "):]) for line in lines if line.startswith('xcrun ["devicectl"')]
        self.assertEqual([d[:4] for d in devicectl], [["devicectl", "device", "info", "details"],
                                                       ["devicectl", "device", "install", "app"],
                                                       ["devicectl", "device", "process", "launch"]])
        for call in devicectl:
            self.assertEqual(call[call.index("--device") + 1], FAKE_DEVICECTL_ID)
        self.assertIn("--console", devicectl[2])
        self.assertEqual(devicectl[2][-1], c.SMOKE_BUNDLE_ID)
        self.assertIn(approval_id, next(line for line in lines if line.startswith("devicectl-ledger ")))
        order = [line.split(" ")[0] for line in lines if line.split(" ")[0] in ("build-script", "smoke")
                 or ("platform=iOS,id" in line and line.startswith("xcodebuild [")) or line.startswith('xcrun ["devicectl"')]
        self.assertEqual(order, ["xcrun", "xcodebuild", "build-script", "smoke", "xcrun", "xcrun"])
        self.assertEqual(sorted(p.name for p in self.temp.glob("test_ios-device.*")), [])
        run = sorted(self.build_root.glob("*-capi-device*"))[-1]
        written = "".join(p.read_text(errors="replace") for p in run.rglob("*") if p.is_file() and p.name != "plan.json"
                          and p.name != "approval.json" and not p.name.startswith("simctl-"))
        self.assertNotIn(FAKE_TEAM, written + finished.stdout + finished.stderr)
        self.assertNotIn("Some Owner", written)

    def test_another_device_reaches_nothing_but_the_read(self):
        # Review A: the devicectl identifier must name the --udid device.
        _, _, approval = self.dry_run()
        self.env["FAKE_INFO_UDID"] = "99999999-8888-7777-6666-555555555555"
        finished, log = self.run_approved(approval)
        self.assertEqual(finished.returncode, 1, finished.stdout + finished.stderr)
        self.assertIn("is not the device of the approved list", finished.stderr)
        self.assert_no_udid(finished)
        self.assertNotIn("99999999", finished.stdout + finished.stderr)
        devicectl = [line for line in log.splitlines() if line.startswith('xcrun ["devicectl"')]
        self.assertEqual(len(devicectl), 1)
        self.assertIn('"info", "details"', devicectl[0])
        self.assertFalse([line for line in log.splitlines() if "platform=iOS,id" in line])
        for word in ("build-script", "smoke "):
            self.assertNotIn(word, log)
        self.assertEqual(sorted(p.name for p in self.temp.glob("test_ios-device.*")), [])

    def test_an_approval_runs_once_and_a_changed_list_is_refused(self):
        _, _, approval = self.dry_run()
        finished, _ = self.run_approved(approval)
        self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
        finished, log = self.run_approved(approval)
        self.assertEqual(finished.returncode, 1, finished.stdout + finished.stderr)
        self.assertIn("already used", finished.stderr)
        self.assert_no_device(log)
        for field, value in (("leftOnDevice", []), ("expectedTests", list(FAKE_UNIT_TESTS[:2]))):
            with self.subTest(field=field):
                _, _, approval = self.dry_run()
                data = json.loads(approval.read_text())
                data[field] = value
                approval.write_text(json.dumps(data))
                finished, log = self.run_approved(approval)
                self.assertEqual(finished.returncode, 1, finished.stdout + finished.stderr)
                self.assertIn(f"{field} differs", finished.stdout)
                self.assert_no_device(log)
                self.assertNotIn(data["approvalId"], self.ledger.read_text())

    def test_the_signed_smoke_build_needs_the_consumed_approval_of_this_run(self):
        # Review A (Codex): run_ios_capi_smoke.sh --signed-device-build called directly signs only through the gate.
        _, _, approval = self.dry_run()
        plan = approval.parent / "plan.json"
        real = self.root / "scripts" / "real_run_ios_capi_smoke.sh"
        env = dict(self.env, NTK_SMOKE_DEVELOPMENT_TEAM=FAKE_TEAM, DEVELOPER_DIR="/nonexistent")

        def call(*extra):
            with tempfile.TemporaryDirectory() as directory:
                return subprocess.run(["bash", str(real), "--dist", directory, "--work", str(pathlib.Path(directory) / "w"),
                                       "--signed-device-build", *extra], capture_output=True, text=True, env=env, timeout=120)
        for extra in ([], ["--plan", str(plan)], ["--plan", str(plan), "--approved", str(approval)]):
            with self.subTest(extra=extra):
                finished = call(*extra)
                self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                self.assertIn("signs only with --plan and --approved", finished.stderr)
        # The near miss: once the approval is consumed (an approved run), the same call passes the gate and goes
        # on to the next check (no xcframework in the empty --dist).
        finished, _ = self.run_approved(approval)
        self.assertEqual(finished.returncode, 0, finished.stdout + finished.stderr)
        finished = call("--plan", str(plan), "--approved", str(approval))
        self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
        self.assertIn("ios-native-toolkit-capi-<version>.xcframework", finished.stderr)
        with tempfile.TemporaryDirectory() as directory:
            finished = subprocess.run(["bash", str(real), "--dist", directory, "--work", str(pathlib.Path(directory) / "w"),
                                       "--plan", str(plan)], capture_output=True, text=True, env=env, timeout=60)
        self.assertEqual(finished.returncode, 2)
        self.assertIn("--plan and --approved are for --signed-device-build", finished.stderr)

    def test_each_failure_fails_the_run(self):
        cases = (
            ("an ASan report in a run that passed", {"FAKE_SANITIZER_REPORT": "asan"}, "AddressSanitizer ERROR x1", 3),
            ("a failed test", {"FAKE_UNIT_FAIL": "asan"}, "FAIL device-unit-asan", 3),
            ("a test that did not run", {"FAKE_DROP_TEST": FAKE_UNIT_TESTS[1]}, "1 expected test(s) did not run", 3),
            ("the simulator's runtime", {"FAKE_DEVICE_RUNTIME": "@rpath/libclang_rt.asan_iossim_dynamic.dylib"},
             "FAIL device-unit-asan", 3),
            ("no runtime", {"FAKE_DEVICE_RUNTIME": ""}, "no sanitizer runtime", 3),
            ("the distributable", {"FAKE_DIST_BUILD_FAILS": "1"}, "FAIL device-smoke-build: not run", 1),
            ("the signed build", {"FAKE_SIGNED_BUILD_FAILS": "1"}, "FAIL device-smoke-install: not run", 1),
            ("the install", {"FAKE_INSTALL_FAILS": "1"}, "FAIL device-smoke-run: not run", 2),
            ("a SMOKE FAIL", {"FAKE_SMOKE_RUN": "fail"}, "SMOKE FAIL line(s)", 3),
            ("a SMOKE RESULT FAIL", {"FAKE_SMOKE_RUN": "result-fail"}, "a SMOKE RESULT FAIL line", 3),
            ("no result line", {"FAKE_SMOKE_RUN": "no-result"}, "no single 'SMOKE RESULT PASS failures=0' line", 3),
            ("a missing step", {"FAKE_SMOKE_RUN": "missing-step"}, "1 smoke step(s) without SMOKE PASS: dialog cancel", 3),
            ("a repeated step", {"FAKE_SMOKE_RUN": "repeated-step"}, "passed more than once: version", 3),
        )
        for name, env, word, devicectl_calls in cases:
            with self.subTest(name):
                _, _, approval = self.dry_run()
                self.env.update(env)
                finished, log = self.run_approved(approval)
                for key in env:
                    del self.env[key]
                self.assertEqual(finished.returncode, 1, finished.stdout + finished.stderr)
                self.assertIn(word, finished.stdout)
                self.assertNotIn("/private/secret/path.c", finished.stdout + finished.stderr)
                self.assertNotIn("Some Owner", finished.stdout + finished.stderr)
                self.assertEqual(len([l for l in log.splitlines() if l.startswith('xcrun ["devicectl"')]), devicectl_calls)
                self.assertEqual(sorted(p.name for p in self.temp.glob("test_ios-device.*")), [])
                run = sorted(self.build_root.glob("*-capi-device*"))[-1]
                self.assertNotIn("/private/secret/path.c", (run / "results.jsonl").read_text())


class DeviceDecisions(unittest.TestCase):
    def make_repo(self, directory):
        repo = directory / "repo"
        for relative in c.DEVICE_RUNNER_FILES:
            (repo / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / relative, repo / relative)
        (repo / "ios").mkdir()
        (repo / "ios" / "A.swift").write_text("a\n")
        base.git(repo, "init", "-q")
        base.git(repo, "add", "-A")
        base.git(repo, "commit", "-q", "-m", "init")
        return repo

    def plan(self, repo):
        return c.make_device_plan(FAKE_DEVICE, base.git(repo, "rev-parse", "HEAD"), "Xcode 26.6 Build version 17F31",
                                  "2.0.0", c.device_runner_file_hashes(repo), sorted(FAKE_UNIT_TESTS))

    def test_the_signing_team_is_one_value_and_never_more(self):
        self.assertEqual(c.signing_team(f"DEVELOPMENT_TEAM = {FAKE_TEAM};\n\tDEVELOPMENT_TEAM = \"\";\n"), FAKE_TEAM)
        for text in ("", "DEVELOPMENT_TEAM = \"\";\n", f"DEVELOPMENT_TEAM = {FAKE_TEAM};\nDEVELOPMENT_TEAM = ZZZZZ99999;\n",
                     "DEVELOPMENT_TEAM = abc;\n"):
            with self.subTest(text=text), self.assertRaises(c.RunnerError):
                c.signing_team(text)
        self.assertEqual(c.signing_team((ROOT / c.TEAM_PBXPROJ).read_text()), c.signing_team((ROOT / c.TEAM_PBXPROJ).read_text()))

    def test_an_approval_must_be_the_list_of_this_run(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(pathlib.Path(directory))
            plan = self.plan(repo)
            approval = c.make_device_approval(plan)
            self.assertEqual(c.device_approval_problems(approval, plan), [])
            for field, value in (("udid", "other"), ("head", "0" * 40), ("xcode", "Xcode 26.3"), ("libraryVersion", "2.0.1"),
                                 ("actions", []), ("leftOnDevice", []), ("removal", "x"), ("signing", "x"), ("notTouched", []),
                                 ("runnerFiles", {}), ("expectedTests", []), ("planDigest", "0" * 64), ("approvalId", "x"), ("createdAt", "now")):
                with self.subTest(field=field):
                    changed = dict(approval, **{field: value})
                    self.assertTrue(c.device_approval_problems(changed, plan), field)
            self.assertTrue(c.device_approval_problems(dict(approval, extra=1), plan))
            self.assertTrue(c.device_approval_problems({k: v for k, v in approval.items() if k != "signing"}, plan))
            self.assertTrue(c.device_approval_problems(dict(approval, kind="device"), plan))

    def test_the_gate_needs_the_consumed_id_the_same_plan_runner_and_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            repo = self.make_repo(directory)
            plan = self.plan(repo)
            approval = c.make_device_approval(plan)
            ledger = directory / "ledger.log"
            head = base.git(repo, "rev-parse", "HEAD")
            self.assertIn("the approval was not consumed in the ledger", c.device_gate_problems(plan, approval, repo, head, ledger))
            base.r.consume_approval(ledger, approval["approvalId"], FAKE_DEVICE)
            self.assertEqual(c.device_gate_problems(plan, approval, repo, head, ledger), [])
            self.assertIn("the plan differs from the approved one",
                          c.device_gate_problems(dict(plan, udid="other"), approval, repo, head, ledger))
            (repo / "ios" / "A.swift").write_text("b\n")
            self.assertTrue(any("uncommitted changes under ios/" in p for p in c.device_gate_problems(plan, approval, repo, head, ledger)))
            base.git(repo, "checkout", "--", "ios/A.swift")
            runner = repo / "scripts" / "run_ios_capi_smoke.sh"
            runner.write_text(runner.read_text() + "\n# changed\n")
            problems = c.device_gate_problems(plan, approval, repo, head, ledger)
            self.assertIn("scripts/run_ios_capi_smoke.sh differs from the commit", problems)
            self.assertIn("the runner files differ from the ones the approved plan was made with", problems)
            self.assertTrue(c.device_gate_problems(plan, approval, repo, "0" * 40, ledger))

    def test_the_device_runtime_is_the_ios_one(self):
        device = "\t@rpath/libclang_rt.asan_ios_dynamic.dylib (compatibility version 0.0.0)"
        simulator = ASAN_LINE
        listing = {f: SYSTEM_LINE + "\n" + device for f in c.FRAMEWORKS}
        self.assertEqual(c.runtime_problems("asan", listing, c.DEVICE_SANITIZER_RUNTIME), [])
        self.assertTrue(c.runtime_problems("asan", {f: SYSTEM_LINE + "\n" + simulator for f in c.FRAMEWORKS},
                                           c.DEVICE_SANITIZER_RUNTIME))
        self.assertTrue(c.runtime_problems("asan", listing))  # the simulator's check refuses the device's runtime

    def test_the_smoke_run_counts_only_its_own_lines(self):
        # Review B7: each of the 16 steps exactly once, no FAIL, one PASS result.
        good = "Launched on Some Owner's iPhone\n" + "\n".join(SMOKE_LINES) + "\nSMOKE RESULT PASS failures=0\n"
        self.assertEqual(len(c.SMOKE_STEPS), 16)
        self.assertEqual(c.device_report_problems("device-smoke-run", good), [])
        for text in ("SMOKE PASS version: x\nSMOKE RESULT PASS failures=0\n", good.replace(SMOKE_LINES[3] + "\n", ""),
                     good + SMOKE_LINES[0] + "\n", good + "SMOKE FAIL b\n", good + "SMOKE RESULT FAIL failures=1\n",
                     good + "SMOKE PASS something new: x\n", good + "SMOKE RESULT PASS failures=0\n",
                     good.replace("SMOKE RESULT PASS failures=0\n", ""), ""):
            with self.subTest(text=text[-60:]):
                self.assertTrue(c.device_report_problems("device-smoke-run", text))
        record = c.device_step_record("device-smoke-run", 0, False, None, "")
        self.assertEqual(record["status"], "FAIL")
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "run.log"
            log.write_text(good)
            record = c.device_step_record("device-smoke-run", 0, False, str(log), "")
            self.assertEqual(record, {"step": "device-smoke-run", "status": "PASS",
                                      "detail": "the 16 smoke steps passed once each"})
            self.assertEqual(c.device_step_record("device-smoke-run", 142, True, str(log), "")["status"], "FAIL")

    def test_the_device_summary_needs_every_step_once(self):
        records = [{"step": s, "status": "PASS"} for s in c.DEVICE_STEPS]
        self.assertTrue(c.device_summary(records)[1])
        self.assertFalse(c.device_summary(records[:-1])[1])
        self.assertFalse(c.device_summary(records + records[-1:])[1])
        self.assertFalse(c.device_summary(records + [{"step": "smoke", "status": "PASS"}])[1])
        self.assertFalse(c.device_summary(records[:-1] + [{"step": "device-smoke-run", "status": "FAIL"}])[1])

    def test_the_smoke_steps_are_the_ones_the_app_prints(self):
        source = (ROOT / "ios" / "IosLibraryCApiSmoke" / "IosLibraryCApiSmoke" / "Smoke.c").read_text()
        source += (ROOT / "ios" / "IosLibraryCApiSmoke" / "IosLibraryCApiSmoke" / "main.m").read_text()
        for step in c.SMOKE_STEPS:
            name = step.split(": ")[-1]
            self.assertIn(f'"{name}"', source, step)

    def test_the_expected_tests_come_from_the_enumeration_and_must_all_run_once_and_pass(self):
        enumeration = json.dumps({"errors": [], "values": [{"enabledTests": [
            {"identifier": "IosLibraryCApiTests/B/testB()"}, {"identifier": "IosLibraryCApiTests/A/testA()"},
            {"identifier": "IosLibraryCApiTests/A"}, {"identifier": "OtherTests/C/testC()"}]}]})
        self.assertEqual(c.unit_test_ids(enumeration), ["A/testA()", "B/testB()"])
        for broken in (json.dumps({"errors": ["x"], "values": []}), json.dumps({"errors": [], "values": []})):
            with self.assertRaises(c.RunnerError):
                c.unit_test_ids(broken)

        def tests(*cases):
            return json.dumps({"testNodes": [{"nodeType": "Unit test bundle", "children": [
                {"nodeType": "Test Case", "nodeIdentifier": i, "result": r} for i, r in cases]}]})
        expected = ["A/testA()", "B/testB()"]
        self.assertEqual(c.expected_tests_problems(expected, tests(("A/testA()", "Passed"), ("B/testB()", "Passed"))), [])
        for name, text in (("missing", tests(("A/testA()", "Passed"))),
                           ("extra", tests(("A/testA()", "Passed"), ("B/testB()", "Passed"), ("C/testC()", "Passed"))),
                           ("twice", tests(("A/testA()", "Passed"), ("B/testB()", "Passed"), ("B/testB()", "Passed"))),
                           ("skipped", tests(("A/testA()", "Passed"), ("B/testB()", "Skipped"))),
                           ("not json", "{")):
            with self.subTest(name):
                self.assertTrue(c.expected_tests_problems(expected, text))
        self.assertTrue(c.expected_tests_problems([], tests(("A/testA()", "Passed"))))

    def test_a_report_is_named_by_its_kinds_never_its_lines(self):
        kinds = c.report_kinds(["==1==ERROR: AddressSanitizer: heap-use-after-free at /Users/someone/x.c",
                                "SUMMARY: AddressSanitizer: heap-use-after-free /Users/someone/x.c:3",
                                "/Users/someone/y.c:4:2: runtime error: signed overflow"])
        self.assertEqual(kinds, "AddressSanitizer ERROR x1, AddressSanitizer SUMMARY x1, UBSan runtime error x1")
        self.assertNotIn("/Users", kinds)


class SignedSmokeBuild(unittest.TestCase):
    """run_ios_capi_smoke.sh --signed-device-build: refused without a team, without the approval of a
    --capi-device run, and with --udid or --device-build (the gate itself is CApiDeviceEndToEnd's)."""

    def run_smoke(self, *args, team=None):
        env = {k: v for k, v in os.environ.items() if k != "NTK_SMOKE_DEVELOPMENT_TEAM"}
        if team is not None:
            env["NTK_SMOKE_DEVELOPMENT_TEAM"] = team
        env["DEVELOPER_DIR"] = "/nonexistent"
        with tempfile.TemporaryDirectory() as directory:
            return subprocess.run(["bash", str(ROOT / "scripts" / "run_ios_capi_smoke.sh"), "--dist", directory,
                                   "--work", str(pathlib.Path(directory) / "work"), *args],
                                  capture_output=True, text=True, env=env, timeout=60)

    def test_the_refusals(self):
        for args, team, word in ((["--signed-device-build"], None, "needs NTK_SMOKE_DEVELOPMENT_TEAM"),
                                 (["--signed-device-build"], "abc", "needs NTK_SMOKE_DEVELOPMENT_TEAM"),
                                 (["--signed-device-build", "--udid", SIMULATOR], FAKE_TEAM, "neither --device-build nor --udid"),
                                 (["--signed-device-build", "--device-build"], FAKE_TEAM, "neither --device-build nor --udid"),
                                 (["--signed-device-build"], FAKE_TEAM, "signs only with --plan and --approved"),
                                 (["--signed-device-build", "--plan", "/nonexistent", "--approved", "/nonexistent"], FAKE_TEAM,
                                  "signs only with --plan and --approved")):
            with self.subTest(args=args, team=team):
                finished = self.run_smoke(*args, team=team)
                self.assertEqual(finished.returncode, 2, finished.stdout + finished.stderr)
                self.assertIn(word, finished.stderr)
                self.assertNotIn(FAKE_TEAM, finished.stdout + finished.stderr)


if __name__ == "__main__":
    unittest.main()
