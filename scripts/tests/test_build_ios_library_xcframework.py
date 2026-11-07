"""The iOS build script refuses an output that would delete the tree's public headers.

IosLibraryCApi's loose headers are copied to include/NativeToolkitC next to its
xcframework, after removing what is there. Each case copies the script and the
headers into a temporary tree, runs the script there with an output that is or
holds the headers (directly, relatively, through a symbolic link or with ..),
and asserts that it stops before building and that the headers are still there.
The real tree is never touched, and nothing is built.

Run: python3 -m unittest discover -s scripts/tests
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = "scripts/build_ios_library_xcframework.sh"
HEADERS = "ios/IosLibraryCApi/include/NativeToolkitC"


class HeadersGuardTest(unittest.TestCase):
    def setUp(self):
        self.base = pathlib.Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.base)
        self.tree = self.base / "repo"
        self.make_tree(self.tree)

    @staticmethod
    def make_tree(tree):
        (tree / "scripts").mkdir(parents=True)
        shutil.copy(ROOT / SCRIPT, tree / SCRIPT)
        shutil.copytree(ROOT / HEADERS, tree / HEADERS)

    def refuses(self, tree, *arguments, message="which is or holds the tree's headers"):
        before = sorted(path.name for path in (tree / HEADERS).iterdir())
        finished = subprocess.run(["bash", str(tree / SCRIPT), "-v", "2.0.0", *arguments], cwd=tree,
                                  capture_output=True, text=True, env={**os.environ, "DEVELOPER_DIR": "/nonexistent"})
        self.assertEqual(1, finished.returncode, finished.stdout + finished.stderr)
        self.assertIn(message, finished.stderr)
        self.assertNotIn("[archive]", finished.stdout)
        self.assertEqual(before, sorted(path.name for path in (tree / HEADERS).iterdir()))
        self.assertTrue(before)

    def test_the_capi_folder_as_the_output(self):
        self.refuses(self.tree, "-m", "IosLibraryCApi", "--output-dir", str(self.tree / "ios/IosLibraryCApi"))

    def test_a_relative_output(self):
        self.refuses(self.tree, "-m", "IosLibrary", "-m", "IosLibraryCApi", "--output-dir", "ios/IosLibraryCApi")

    def test_an_output_inside_the_headers(self):
        self.refuses(self.tree, "-m", "IosLibraryCApi", "--output-dir", str(self.tree / HEADERS / "out"))

    def test_an_output_path_next_to_the_headers(self):
        self.refuses(self.tree, "-m", "IosLibraryCApi", "-o", str(self.tree / "ios/IosLibraryCApi/x.xcframework"))

    def test_a_symbolic_link_to_the_capi_folder(self):
        link = self.base / "link"
        link.symlink_to(self.tree / "ios/IosLibraryCApi")
        self.refuses(self.tree, "-m", "IosLibraryCApi", "--output-dir", str(link))

    def test_the_capi_folder_in_another_case(self):
        # bash's pwd -P keeps the case it was given, so only a comparison of the folders themselves stops this.
        other_case = self.tree / "ios/iosLibraryCApi"
        if not other_case.exists():
            self.skipTest("the file system is case-sensitive")
        self.refuses(self.tree, "-m", "IosLibraryCApi", "--output-dir", "ios/iosLibraryCApi")
        self.refuses(self.tree, "-m", "IosLibraryCApi", "--output-dir", str(self.tree / "IOS/IOSLIBRARYCAPI/INCLUDE/NATIVETOOLKITC/out"))

    def test_dot_dot_through_a_missing_folder(self):
        self.refuses(self.tree, "-m", "IosLibraryCApi", "--output-dir", str(self.tree / "ios/missing/../IosLibraryCApi"),
                      message="cannot resolve")

    def test_an_output_that_holds_the_headers(self):
        # The tree under <out>/include/NativeToolkitC: replacing that folder would delete the tree.
        out = self.base / "out"
        tree = out / "include" / "NativeToolkitC" / "repo"
        self.make_tree(tree)
        self.refuses(tree, "-m", "IosLibraryCApi", "--output-dir", str(out))


if __name__ == "__main__":
    unittest.main()
