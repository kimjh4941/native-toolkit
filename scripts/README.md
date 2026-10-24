# scripts

Build, check, test and publish scripts for the repository. The prefix of a file
name says what it does, which is the grouping: there are no subfolders for it.

| Prefix | What it does |
|---|---|
| `build_` | Produces a distributable from source, under `dist/<release>/<os>/` |
| `check_` | Compares two things that must agree and fails when they do not |
| `test_` | Runs a platform's test suites |
| `publish_`, `verify_` | The documentation site, and the manual before a release |

## Build

Each script builds one platform's library and copies it with its distributable
name. They take the module to build, the configuration, the library version and
an explicit output path; run one with `--help` (or `-Help`) for its options.

| Script | Platform | Notes |
|---|---|---|
| `build_android_library_aar.sh` | Android | `android_library`, `android_library_capi`（`--m2` で Maven のリポジトリも） |
| `build_ios_library_xcframework.sh` | iOS | `IosLibrary`, `UnityIosPlugin` |
| `build_xcode26_library_xcframework.sh` | macOS | What the implement-feature workflow uses. Takes `--minimum-macos` (default 15.0) |
| `build_xcode16_library_xcframework.sh` | macOS | The earlier variant, named after the Xcode it was written for; no `--minimum-macos` |
| `build_windows_library_dll.ps1` | Windows | Builds both modules and, with `-Package`, packs the two NuGet packages. See `agent-rules/coding-rules/windows.md` ("配布") |

The Windows script is the one that differs most, because Windows ships two
artifacts from one source tree:

```powershell
# Both modules, both packages, into dist/1.12.0/windows/
./scripts/build_windows_library_dll.ps1 -c release -v 2.0.0 -r 1.12.0 -Package
```

`-LibraryVersion` (`-v`) has to match what the module's public headers declare;
`-ReleaseVersion` (`-r`) names the `dist/<release>/` folder and is a different
number (the repository's release, not the library's).

A full release build (both modules, `-Package`, the default output) also writes
`dist/<release>/windows/SOURCE-HASH.txt`, a hash of the sources it read, which
`check_windows_dist.py` compares with the tree. Any other build leaves that
file alone, so a partial rebuild cannot make stale packages look current.

## Check

These read both sides of a comparison from source, so neither side can drift
without the other noticing. They are fast, need no toolchain, and are meant to
run while writing a design or before a commit; the optional parts of the
Android ones (`--library`, the compile check) use the NDK's `llvm-nm` and
`clang` and say SKIP without them. The C ABI and manual example checkers are
one file per OS; what they share is `c_abi_contract_common.py` and
`manual_c_examples_common.py`. The cross-OS `Common.h` check lives in the
Android checker, so run it too after changing the Windows `Common.h`.

| Script | Compares |
|---|---|
| `check_design_consistency.py <design.md>` | A design document against itself: counts, ids, tables, heading order |
| `check_cpp_api_contract.py` | The Windows C++ API design against the public headers and what it cites |
| `check_c_abi_contract_windows.py` | The Windows C ABI: the `.def`, the public headers, the design's tables and Appendix A, and the C++ API it mirrors |
| `check_c_abi_contract_android.py [--design-only] [--library <libntk.so> [--nm <llvm-nm>]]` | The Android C ABI: the public headers, the design's tables and Appendix A, the Kotlin entries it calls, the behaviours of chapter 10, and its `Common.h` against the Windows one. `--design-only` reads Appendix A in place of the headers until stage 2b writes them; `--library` also compares the symbols `libntk.so` exports |
| `check_sample_app_inputs.py` | That no sample app screen declares a text input field (`agent-rules/coding-rules/common.md`) |
| `check_manual_c_examples_windows.py [<version>]` | The manual's Windows C examples against the C ABI: every exported function is shown, every name exists, the three languages carry the same code, and the examples compile as C (MSBuild) |
| `check_manual_c_examples_android.py [<version>] [--require-examples]` | The same for the Android C examples, compiled with the NDK's clang. Says SKIP while no page has an Android C ABI section, unless `--require-examples` is given |
| `check_windows_dist.py [<release>]` | `dist/<release>/windows/` against the tree: built from the current sources, the same public headers (loose and in both packages), the declared versions in the file names, every `.def` export in the DLL. Run before a release |

## Test

| Script | Runs |
|---|---|
| `test_windows.ps1` | The whole Windows suite: unit tests, the C ABI smoke executables, then the FlaUI UI tests against the real desktop |
| `test_windows.baseline.json` | The recorded outcome of the last full run, which `-Baseline` rewrites |

```powershell
./scripts/test_windows.ps1                       # everything
./scripts/test_windows.ps1 -SkipUnitTests        # UI tests only
./scripts/test_windows.ps1 -Filter "TestCategory=Dialog"   # some UI tests
./scripts/test_windows.ps1 -IncludeDestructive   # also ClipboardHistoryDestructive
```

The UI tests drive the real desktop, so nothing else should use the machine
while they run, and the screen must not lock. `-Filter` takes a dotnet test
filter and applies to the UI tests only. `-IncludeDestructive` adds
ClipboardHistoryDestructive, which deletes every unpinned item in the user's
clipboard history and cannot be undone: ask before running it. `-Baseline`
needs a full run, so it refuses `-Filter` and `-SkipUnitTests`.

| Script | Runs |
|---|---|
| `test_ios.sh` | The iOS unit tests (simulator only) and the sample's UI tests on one simulator or the device. What runs and every check of what ran is in `ios_ui_runner.py` |
| `test_ios.baseline.<model>-<os>.json` | The recorded outcome of the last full run in each of the two environments, which `--baseline` rewrites |

```bash
scripts/test_ios.sh --udid <simulator>                       # everything on a simulator
scripts/test_ios.sh --udid <simulator> --feature Dialog      # one feature's UI tests
scripts/test_ios.sh --udid <device> --enumerate-udid <simulator> --dry-run --device-allow systemui
scripts/test_ios.sh --udid <device> --enumerate-udid <simulator> --devicectl-id <id> \
  --device-allow systemui --approved <approval.json>         # after the user approved the list
```

The device is the user's own iPhone (`artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md`,
U-9 and 6.3): a UDID that `xcrun simctl list` does not show is treated as the device,
`--dry-run` never touches it, and a device run needs an approval list from `--dry-run` that the
user approved, used once (the IDs are recorded outside the repository in
`~/Library/Application Support/native-toolkit/test_ios-approvals.log`; nothing moves it), and
nothing under `ios/` may differ from the commit. `--name-each-test` makes a simulator run name
every test the way the device does. The hashes of the
trusted test files are pinned in `ios_ui_runner.py`; change them only after another model has
reviewed the change.

## `tests/` is not the test suite

`scripts/tests/` holds the **self-tests of the `check_` scripts** and of the
decisions of `test_ios.sh` (`ios_ui_runner.py`), not tests of the product. Each case copies the files a checker reads into a temporary tree,
breaks exactly one of them there, and asserts that the matching check fails - so
a checker cannot quietly stop checking. The real tree is never touched.

```bash
python -m unittest discover -s scripts/tests    # 337 cases
```

`tests/ios_ui_runner_mutations.py` is not a unit test: it breaks one decision of the iOS runner
at a time in a copy (with the copy's approval ledger moved into the copy) and checks that the
self-tests catch each one.

`test_windows.ps1`, by contrast, runs the product's own tests. The two are
unrelated despite the similar names.

## Publish and verify

| Script | Does |
|---|---|
| `publish_docs.sh <version> [--skip-build] [--os <targets>]` | Generates each platform's API reference, copies it and `manual/<version>/` to `docs/<version>/`, and refreshes `docs/latest/` |
| `verify_manual.sh <version> [--strict]` | Seven checks over `manual/<version>/`: image references, sample conformance, anchors, artifact names, prose style, language parity, the index feature list |

Check 2 of `verify_manual.sh` compares code examples against the sample app,
which is C++ or Kotlin, so the C examples are outside it.
`check_manual_c_examples_<os>.py` is what covers those; the compile check needs
Visual Studio (Windows) or the NDK's clang (Android) and reports SKIP without
it, unless `--require-compile` is given.

`publish_docs.sh` also moves `docs/latest/`, so it belongs to a release rather
than to day-to-day work. The workflows that call these two are
`agent-rules/workflows/write-manual/` and `.../verify-manual/`.

## Other entries

- `nuget/` - the two NuGet package templates (`NativeToolkit`, `NativeToolkitCApi`) that `build_windows_library_dll.ps1 -Package` fills in. `nuget/nuget.exe` is local tooling and is not committed.
- `__pycache__/` - Python bytecode; ignored by git.

## Why this folder is flat

Script paths are quoted in about 260 places, and roughly 150 of those are in
`artifact/`, which records what was run at the time and is not rewritten. Moving
files into subfolders would fix the live references and leave the records
pointing at paths that no longer exist, in exchange for grouping that the name
prefixes already give. Revisit when the folder passes roughly 20 files; split
the new growth then, and leave `artifact/` alone.
