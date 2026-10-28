#!/usr/bin/env python3
"""Regression checks for the security gate, including fail-closed debt expiry."""
import datetime
import importlib.util
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("security", Path(__file__).with_name("security-dependencies.py"))
security = importlib.util.module_from_spec(spec)
spec.loader.exec_module(security)


class GateTests(unittest.TestCase):
    entry = ("website/package-lock.json", "npm", "fixture", "1.0", "GHSA-fictional")
    baseline = {"expires": "2026-11-10", "findings": [entry]}

    def test_known_debt_is_temporarily_allowed(self):
        self.assertEqual(security.evaluate({self.entry}, self.baseline, datetime.date(2026, 11, 9)), (set(), set()))

    def test_expiry_blocks_on_deadline(self):
        self.assertEqual(security.evaluate({self.entry}, self.baseline, datetime.date(2026, 11, 10)), (set(), {self.entry}))

    def test_new_version_or_path_cannot_reuse_exception(self):
        for index in (0, 3, 4):
            entry = list(self.entry)
            entry[index] += "-changed"
            entry = tuple(entry)
            self.assertEqual(security.evaluate({entry}, self.baseline, datetime.date(2026, 11, 9)), ({entry}, set()))

    def test_resolved_debt_does_not_block_after_expiry(self):
        self.assertEqual(security.evaluate(set(), self.baseline, datetime.date(2026, 11, 10)), (set(), set()))

    def test_report_paths_normalized_and_duplicate_ids_collapsed(self):
        report = {"results": [{"source": {"path": str(security.ROOT / self.entry[0])}, "packages": [{
            "package": {"ecosystem": "npm", "name": "fixture", "version": "1.0"},
            "vulnerabilities": [{"id": "GHSA-fictional"}, {"id": "GHSA-fictional"}]}]}]}
        self.assertEqual(security.findings(report), {self.entry})

    def test_website_context_includes_root_and_excludes_release_downloads(self):
        context = ET.parse(security.ROOT / "tools/security/website.context").find("context")
        include = re.compile(context.findtext("incregexes"))
        exclude = re.compile(context.findtext("excregexes"))
        for path in ("", "/", "/docs/notes"):
            self.assertIsNotNone(include.fullmatch("http://127.0.0.1:8787" + path))
        self.assertIsNone(include.fullmatch("https://usevolant.com/"))
        self.assertIsNotNone(exclude.fullmatch("http://127.0.0.1:8787/updates/fictional.dmg"))


unittest.main()
