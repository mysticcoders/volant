#!/usr/bin/env python3
"""Fail a release whose website still announces an older version as new.

The home page carried "New in 0.2.0" through 0.3.13 because badges and download copy are written by
hand and nothing checked them. `Scripts/ship.sh` runs this in preflight against the release branch:
every "New in X.Y.Z" in the website's pages, in any capitalization and even when JSX splits it across
lines, must name the version being released. A release with no such mention passes, so a release with
nothing to announce is not blocked. Run with --self-test to check the matcher itself.
"""
import argparse
import os
import re
import sys
import unittest

ANNOUNCEMENT = re.compile(r"\bnew\s+in\s+v?(\d+\.\d+\.\d+)\b", re.IGNORECASE)
PAGE_SUFFIXES = (".tsx", ".ts", ".jsx", ".js", ".mdx", ".md", ".html")
SKIPPED_DIRECTORIES = {"node_modules", "dist", ".next", ".vinext", ".wrangler"}


def stale(files, version):
    """Yields (path, line number, announced version) for each announcement in `files`, a mapping of
    path to text, that does not name `version`."""
    for path, text in sorted(files.items()):
        if not path.endswith(PAGE_SUFFIXES):
            continue
        for match in ANNOUNCEMENT.finditer(text):
            if match.group(1) != version:
                yield path, text.count("\n", 0, match.start()) + 1, match.group(1)


def page_files(root):
    """Every page source under `root`, keyed by path relative to it."""
    files = {}
    for directory, names, filenames in os.walk(root):
        names[:] = [name for name in names if name not in SKIPPED_DIRECTORIES]
        for filename in filenames:
            if filename.endswith(PAGE_SUFFIXES):
                path = os.path.join(directory, filename)
                with open(path, encoding="utf-8") as handle:
                    files[os.path.relpath(path, root)] = handle.read()
    return files


class StaleAnnouncementTests(unittest.TestCase):
    def test_current_version_and_no_mention_pass(self):
        self.assertEqual(list(stale({"page.tsx": "<span>New in 0.3.14</span>", "about.tsx": "No badge here."}, "0.3.14")), [])

    def test_older_version_fails_with_its_line(self):
        self.assertEqual(list(stale({"page.tsx": "intro\n<span className=\"release-badge\">New in 0.2.0</span>"}, "0.3.14")),
                         [("page.tsx", 2, "0.2.0")])

    def test_capitals_and_lines_split_by_jsx(self):
        text = "<p className=\"eyebrow\">\n  NEW IN 0.3.13\n</p>\n<a href=\"#agents\">New in\n  0.3.12</a>"
        self.assertEqual([found for _, _, found in stale({"page.tsx": text}, "0.3.14")], ["0.3.13", "0.3.12"])

    def test_only_page_sources_are_read(self):
        self.assertEqual(list(stale({"notes.txt": "New in 0.1.0", "page.tsx": "New in v0.1.0"}, "0.3.14")),
                         [("page.tsx", 1, "0.1.0")])

    def test_prose_about_newness_without_a_version_passes(self):
        self.assertEqual(list(stale({"page.tsx": "Whatever is new in this release, and new in town."}, "0.3.14")), [])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--version", help="the version being released, such as 0.3.14")
    parser.add_argument("--root", default="website/app", help="the website's page sources")
    args = parser.parse_args()
    if args.self_test:
        sys.argv = sys.argv[:1]
        unittest.main(verbosity=1)
    if not args.version or not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("--version must be major.minor.patch")
    found = list(stale(page_files(args.root), args.version))
    for path, line, announced in found:
        print(f"{args.root}/{path}:{line}: announces New in {announced}, but this release is {args.version}")
    if found:
        sys.exit(f"Update or remove the website's New in labels for {args.version} before shipping.")
    print(f"Website announcements name {args.version} or nothing.")
