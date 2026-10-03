"""Break each check of the Windows dist checker and confirm it notices.

Each case builds a temporary repository: the tracked build inputs copied from
the real tree, and a stand-in dist/<release>/windows/ made from them (the real
headers, a DLL that is just the export names, packages that are zips of
those). It stamps that tree, makes one change, and asserts that the named check
fails. The real tree and the real dist/ are never touched. A case whose own
anchor text is missing fails too, so a case cannot go quiet because the file it
edits has moved on.

Run: python3 -m unittest discover -s scripts/tests
"""

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts" / "check_windows_dist.py"
sys.path.insert(0, str(ROOT / "scripts"))
import check_windows_dist  # noqa: E402  (the list of build inputs)

RELEASE = "9.9.9"
DIST = f"dist/{RELEASE}/windows"
DEF = check_windows_dist.DEF
SOURCE_FILE = "windows/WindowsLibraryCApi/src/Clipboard/ClipboardCApi.cpp"
C_COMMON = "windows/WindowsLibraryCApi/include/NativeToolkitC/Common.h"
C_CLIPBOARD_HEADER = "include/NativeToolkitC/Clipboard.h"


def failures(output):
    return [line.strip() for line in output.splitlines() if line.strip().startswith("FAIL")]


def version(root, fragment, macro):
    text = (root / fragment).read_text(encoding="utf-8")
    return ".".join(re.search(rf"#define\s+{macro}_{p}\s+(\d+)", text).group(1)
                    for p in ("MAJOR", "MINOR", "PATCH"))


def fake_dll(root, drop=()):
    names = [line.split()[0] for line in (root / DEF).read_text(encoding="utf-8").splitlines()
             if line.strip().startswith("ntk_")]
    return b"MZ" + b"".join(n.encode("ascii") + b"\0" for n in names if n not in drop)


def pack(path, entries):
    with zipfile.ZipFile(path, "w") as z:
        for name, data in entries.items():
            z.writestr(name, data)


class WindowsDistChecker(unittest.TestCase):

    def make_tree(self, directory):
        root = pathlib.Path(directory)
        tracked = subprocess.run(["git", "ls-files", "--", *check_windows_dist.SOURCES], cwd=ROOT,
                                 capture_output=True, text=True, encoding="utf-8").stdout.split("\n")
        for fragment in filter(None, tracked):
            destination = root / fragment
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / fragment, destination)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=root, check=True)

        dist = root / DIST
        headers = {}
        for source_dir, leaf in check_windows_dist.HEADERS.items():
            (dist / "include" / leaf).mkdir(parents=True)
            for h in (root / source_dir).glob("*.h"):
                shutil.copy(h, dist / "include" / leaf / h.name)
                headers[f"build/native/include/{leaf}/{h.name}"] = h.read_bytes()
        cpp = version(root, *check_windows_dist.CPP_VERSION)
        capi = version(root, *check_windows_dist.C_VERSION)
        (dist / f"windows-native-toolkit-{cpp}.lib").write_bytes(b"lib")
        (dist / f"windows-native-toolkit-capi-{capi}.lib").write_bytes(b"lib")
        (dist / f"windows-native-toolkit-capi-{capi}.dll").write_bytes(fake_dll(root))
        pack(dist / f"windows-native-toolkit-{cpp}.nupkg",
             {k: v for k, v in headers.items() if "/NativeToolkit/" in k})
        pack(dist / f"windows-native-toolkit-capi-{capi}.nupkg",
             {**{k: v for k, v in headers.items() if "/NativeToolkitC/" in k},
              "runtimes/win-x64/native/NativeToolkitC.dll": fake_dll(root)})
        self.run_checker(root, "--stamp")
        return root, dist, capi

    def run_checker(self, root, *extra):
        finished = subprocess.run([sys.executable, str(CHECKER), RELEASE, "--root", str(root), *extra],
                                  capture_output=True, text=True, encoding="utf-8")
        return finished.stdout, finished.returncode

    def edit(self, path, old, new):
        text = path.read_text(encoding="utf-8")
        self.assertTrue(old in text, f"the test's own anchor is missing from {path.name}")
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def assert_catches(self, name, breaking):
        with tempfile.TemporaryDirectory() as directory:
            root, dist, capi = self.make_tree(directory)
            breaking(root, dist, capi)
            output, code = self.run_checker(root)
        reported = failures(output)
        self.assertTrue(any(line.startswith(f"FAIL {name}") for line in reported),
                        f"breaking {name!r} was not reported; failures were {reported}")
        self.assertEqual(code, 1, "a failure must make the exit status 1")

    # --- the unbroken tree --------------------------------------------------

    def test_nothing_fails_when_nothing_is_wrong(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _, _ = self.make_tree(directory)
            output, code = self.run_checker(root)
        self.assertEqual(failures(output), [], output)
        self.assertEqual(code, 0, output)

    def test_a_missing_dist_fails_rather_than_skips(self):
        self.assert_catches("the distributables are readable", lambda root, dist, capi: shutil.rmtree(dist))

    # --- source -------------------------------------------------------------

    def test_a_source_that_changed_after_the_build(self):
        self.assert_catches("source", lambda root, dist, capi: self.edit(
            root / SOURCE_FILE, "#include", "// changed after the build\n#include"))

    def test_a_build_input_added_after_the_build(self):
        def add(root, dist, capi):
            (root / "windows/WindowsLibrary/src/New.cpp").write_text("int x;\n", encoding="utf-8")
            subprocess.run(["git", "add", "-A"], cwd=root, check=True)
        self.assert_catches("source", add)

    def test_no_record_of_the_build(self):
        self.assert_catches("source", lambda root, dist, capi: (dist / check_windows_dist.STAMP).unlink())

    def test_a_line_ending_change_alone_is_not_a_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root, _, _ = self.make_tree(directory)
            path = root / SOURCE_FILE
            data = path.read_bytes().replace(b"\r\n", b"\n")
            path.write_bytes(data.replace(b"\n", b"\r\n"))
            output, code = self.run_checker(root)
        self.assertEqual(failures(output), [], output)

    # --- headers ------------------------------------------------------------

    def test_a_header_in_dist_that_is_stale(self):
        self.assert_catches("headers", lambda root, dist, capi: self.edit(
            dist / C_CLIPBOARD_HEADER, "@file Clipboard.h", "@file Clipboard.h (stale)"))

    def test_a_header_missing_from_dist(self):
        self.assert_catches("headers", lambda root, dist, capi: (dist / C_CLIPBOARD_HEADER).unlink())

    def test_a_header_dist_has_that_the_tree_does_not(self):
        self.assert_catches("headers", lambda root, dist, capi: (dist / "include/NativeToolkitC/Old.h").write_text(
            "#pragma once\n", encoding="utf-8"))

    def test_a_header_in_a_package_that_is_stale(self):
        def stale(root, dist, capi):
            package = dist / f"windows-native-toolkit-capi-{capi}.nupkg"
            with zipfile.ZipFile(package) as z:
                entries = {n: z.read(n) for n in z.namelist()}
            key = "build/native/" + C_CLIPBOARD_HEADER
            self.assertIn(key, entries)
            entries[key] += b"// stale\n"
            pack(package, entries)
        self.assert_catches("headers", stale)

    # --- names --------------------------------------------------------------

    def test_a_version_the_distributables_do_not_carry(self):
        self.assert_catches("names", lambda root, dist, capi: self.edit(
            root / C_COMMON, f"#define NTK_VERSION_PATCH {capi.split('.')[2]}",
            f"#define NTK_VERSION_PATCH {int(capi.split('.')[2]) + 1}"))

    def test_a_distributable_that_is_missing(self):
        self.assert_catches("names", lambda root, dist, capi: (dist / f"windows-native-toolkit-capi-{capi}.lib").unlink())

    # --- exports ------------------------------------------------------------

    def test_a_dll_without_an_export(self):
        self.assert_catches("exports", lambda root, dist, capi: (dist / f"windows-native-toolkit-capi-{capi}.dll")
                            .write_bytes(fake_dll(root, drop=("ntk_clipboard_clear",))))

    def test_a_packaged_dll_without_an_export(self):
        def drop(root, dist, capi):
            package = dist / f"windows-native-toolkit-capi-{capi}.nupkg"
            with zipfile.ZipFile(package) as z:
                entries = {n: z.read(n) for n in z.namelist()}
            entries["runtimes/win-x64/native/NativeToolkitC.dll"] = fake_dll(root, drop=("ntk_version",))
            pack(package, entries)
        self.assert_catches("exports", drop)

    def test_a_missing_dll_fails_rather_than_skips(self):
        self.assert_catches("exports", lambda root, dist, capi: (dist / f"windows-native-toolkit-capi-{capi}.dll").unlink())


if __name__ == "__main__":
    unittest.main()
