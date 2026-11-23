#!/usr/bin/env python3
"""Count Swift patterns Volant wants to shrink and fail if any count rises above its baseline.

Agents copy what the code shows them, so a pattern with hundreds of examples on main keeps coming
back however often review rejects it. Each pattern here has a committed count in
tools/ratchet-baseline.json. A change may not add occurrences. A change that removes some must lower
the baseline in the same PR, so the count only moves down. Raising a baseline needs a written reason,
recorded in the baseline file and repeated in the PR.

Counts cover shipping Swift tracked by git or newly added, excluding tests and tools. Comment lines
are ignored.

Usage:
  python3 tools/ratchets.py                       check against the baseline (exit 1 on findings)
  python3 tools/ratchets.py --update              lower the baseline to the current counts
  python3 tools/ratchets.py --update --reason ""  also allow a count to rise, recording why
  python3 tools/ratchets.py --self-test           check the counting and comparison logic
"""
import argparse
import datetime
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "tools" / "ratchet-baseline.json"
SOURCE_ROOTS = ("Volant/", "Core/Sources/", "Shared/", "VolantAgentHost/", "VolantAIHost/", "VolantExtensionHost/",
                "VolantFetchHost/", "VolantInputHost/", "VolantMCPBridge/", "VolantRatesHost/", "VolantWeatherHost/",
                "ios/")
EXCLUDED_PARTS = ("Tests", "UITests", "Fixtures", "Previews")


class Pattern:
    """One ratcheted pattern: how to find it, why it should shrink and what to write instead."""

    def __init__(self, name, regex, why, instead):
        self.name = name
        self.regex = re.compile(regex)
        self.why = why
        self.instead = instead


PATTERNS = (
    Pattern("dispatch_main_async", r"DispatchQueue\.main\.async\b",
            "A GCD hop to the main queue hides actor isolation from the Swift 6 checker, so data races it "
            "would catch go unseen.",
            "Mark the work @MainActor, or use Task { @MainActor in ... } from non-isolated code."),
    Pattern("try_bang", r"\btry!(?!\s*NSRegularExpression\()",
            "A thrown error crashes the app for the owner. (try! NSRegularExpression on a literal pattern is "
            "exempt: a typo fails as soon as any test loads the type.)",
            "Handle the error, or use try? with an explicit fallback and say what the fallback means."),
    Pattern("force_cast", r"\bas!\s",
            "A failed cast crashes the app for the owner.",
            "Use as? and handle the failure, or type the value so no cast is needed."),
    Pattern("unchecked_sendable", r"@unchecked\s+Sendable\b",
            "It turns off data-race checking for the whole type.",
            "Make the type genuinely Sendable, make it an actor, or isolate it to the main actor."),
    Pattern("nonisolated_unsafe", r"\bnonisolated\(unsafe\)",
            "It turns off data-race checking for one declaration.",
            "Isolate the state to an actor, or protect it with a lock-backed Sendable type."),
)


def is_counted(path):
    """Return whether a repository-relative path is shipping Swift that the ratchets cover."""
    if not path.endswith(".swift") or not path.startswith(SOURCE_ROOTS):
        return False
    return not any(part.endswith(EXCLUDED_PARTS) for part in Path(path).parts[:-1])


def source_files(root):
    """List counted Swift files: tracked files plus untracked, unignored ones, so new files count too.
    Outside a git checkout, such as the source copy tools/test-ui-vm.py sends to the UI VM (which holds
    exactly those files), every Swift file under the root is listed instead."""
    listed = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.swift"],
                            cwd=root, capture_output=True)
    if listed.returncode == 0:
        paths = listed.stdout.decode().split("\0")
    elif subprocess.run(["git", "rev-parse", "--git-dir"], cwd=root, capture_output=True).returncode != 0:
        paths = [str(path.relative_to(root)) for path in root.rglob("*.swift")]
    else:
        raise subprocess.CalledProcessError(listed.returncode, listed.args, listed.stdout, listed.stderr)
    return sorted(p for p in set(paths) if p and is_counted(p) and (root / p).is_file())


def code_lines(text):
    """Yield (line number, line) for lines that are not comments."""
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if stripped.startswith(("//", "/*", "*")):
            continue
        yield number, line


def count(root, files, patterns=PATTERNS):
    """Count each pattern per file. Returns {pattern: {"total": n, "files": {path: n}}, ...} and line locations."""
    counts = {p.name: {"total": 0, "files": {}} for p in patterns}
    locations = {p.name: {} for p in patterns}
    for path in files:
        text = (root / path).read_text(encoding="utf-8", errors="replace")
        for number, line in code_lines(text):
            for pattern in patterns:
                hits = len(pattern.regex.findall(line))
                if not hits:
                    continue
                entry = counts[pattern.name]
                entry["total"] += hits
                entry["files"][path] = entry["files"].get(path, 0) + hits
                locations[pattern.name].setdefault(path, []).append(number)
    return counts, locations


def compare(baseline, current, patterns=PATTERNS):
    """Return (rises, drops): patterns whose total went above or below the baseline."""
    rises, drops = [], []
    for pattern in patterns:
        was = baseline.get("patterns", {}).get(pattern.name, {}).get("total", 0)
        now = current[pattern.name]["total"]
        if now > was:
            rises.append((pattern, was, now))
        elif now < was:
            drops.append((pattern, was, now))
    return rises, drops


def grown_files(baseline, current, name):
    """List files whose count for one pattern is above their baseline count, the likely new occurrences."""
    before = baseline.get("patterns", {}).get(name, {}).get("files", {})
    return sorted(path for path, n in current[name]["files"].items() if n > before.get(path, 0))


def report(baseline, current, locations, rises, drops):
    """Print a finding for each change, written as guidance: what grew, why it matters, what to do instead."""
    for pattern, was, now in rises:
        print(f"ratchet {pattern.name}: {was} -> {now}. {pattern.why}")
        for path in grown_files(baseline, current, pattern.name):
            lines = ", ".join(str(n) for n in locations[pattern.name][path])
            print(f"  {path}: line {lines}")
        print(f"  Instead: {pattern.instead}")
    for pattern, was, now in drops:
        print(f"ratchet {pattern.name}: {was} -> {now}. Lower the baseline in this change so it stays down: "
              "python3 tools/ratchets.py --update")
    if rises:
        print("If a new occurrence is genuinely right, raise the baseline with "
              "python3 tools/ratchets.py --update --reason \"...\" and give the same reason in the PR. "
              "Do not hide an occurrence from the counter.")


def write_baseline(path, baseline, current, reason):
    """Write current counts as the baseline, appending a record of any raise and its reason."""
    raised = list(baseline.get("raised", []))
    for name, entry in current.items():
        was = baseline.get("patterns", {}).get(name, {}).get("total", 0)
        if name in baseline.get("patterns", {}) and entry["total"] > was:
            raised.append({"date": datetime.date.today().isoformat(), "pattern": name, "from": was,
                           "to": entry["total"], "reason": reason})
    data = {"about": "Counts for tools/ratchets.py. They may only go down; see that file before editing.",
            "patterns": {name: {"total": e["total"], "files": dict(sorted(e["files"].items()))}
                         for name, e in current.items()},
            "raised": raised}
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main():
    """Check or update the baseline from the command line."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--update", action="store_true", help="write current counts as the baseline")
    parser.add_argument("--reason", help="with --update, allow counts to rise and record why")
    parser.add_argument("--self-test", action="store_true", help="test the counting and comparison logic")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.main(argv=[sys.argv[0]], exit=False).result
        return 0 if result.wasSuccessful() else 1
    baseline = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.exists() else {}
    current, locations = count(ROOT, source_files(ROOT))
    rises, drops = compare(baseline, current)
    if args.update:
        new_patterns = [p for p, _, _ in rises if p.name not in baseline.get("patterns", {})]
        if len(new_patterns) < len(rises) and not (args.reason and args.reason.strip()):
            report(baseline, current, locations, rises, [])
            print("Refusing to raise a baseline without --reason.")
            return 1
        write_baseline(BASELINE, baseline, current, (args.reason or "").strip())
        print(f"Wrote {BASELINE.relative_to(ROOT)}: " + ", ".join(f"{n} {e['total']}" for n, e in current.items()))
        return 0
    if not rises and not drops:
        print("ratchets: " + ", ".join(f"{n} {e['total']}" for n, e in current.items()))
        return 0
    report(baseline, current, locations, rises, drops)
    return 1


class RatchetTests(unittest.TestCase):
    """Self-tests for path selection, counting and comparison."""

    def test_counts_only_shipping_swift(self):
        """Tests, fixtures, tools and non-Swift files are not counted."""
        self.assertTrue(is_counted("Volant/Launcher/LauncherView.swift"))
        self.assertTrue(is_counted("Core/Sources/VolantCore/Focus/Focus.swift"))
        self.assertFalse(is_counted("VolantTests/LauncherTests.swift"))
        self.assertFalse(is_counted("Core/Tests/VolantCoreTests/FocusTests.swift"))
        self.assertFalse(is_counted("tools/input-spike/main.swift"))
        self.assertFalse(is_counted("Volant/Launcher/notes.md"))
        self.assertTrue(is_counted("Volant/Camera/CameraPreviewWindow.swift"))

    def test_literal_regex_try_is_exempt(self):
        """try! NSRegularExpression is not counted; any other try! is."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "C.swift").write_text("let r = try! NSRegularExpression(pattern: \"a\")\nlet d = try! load()\n")
            counts, _ = count(root, ["C.swift"])
            self.assertEqual(counts["try_bang"]["total"], 1)

    def test_ignores_comment_lines(self):
        """A pattern mentioned in a comment is not an occurrence."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "A.swift").write_text("// try! is banned\n/// as! too\nlet x = try! f()\n")
            counts, locations = count(root, ["A.swift"])
            self.assertEqual(counts["try_bang"]["total"], 1)
            self.assertEqual(counts["force_cast"]["total"], 0)
            self.assertEqual(locations["try_bang"]["A.swift"], [3])

    def test_counts_every_occurrence_on_a_line(self):
        """Two occurrences on one line count twice."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "B.swift").write_text("let a = x as! A, b = y as! B\nDispatchQueue.main.async { }\n")
            counts, _ = count(root, ["B.swift"])
            self.assertEqual(counts["force_cast"]["total"], 2)
            self.assertEqual(counts["dispatch_main_async"]["total"], 1)

    def test_compare_reports_rises_and_drops(self):
        """A rise and a drop are both findings; an unchanged count is not."""
        baseline = {"patterns": {"try_bang": {"total": 2}, "force_cast": {"total": 3}, "dispatch_main_async": {"total": 1}}}
        current = {p.name: {"total": 0, "files": {}} for p in PATTERNS}
        current["try_bang"]["total"] = 3
        current["force_cast"]["total"] = 1
        current["dispatch_main_async"]["total"] = 1
        rises, drops = compare(baseline, current)
        self.assertEqual([(p.name, a, b) for p, a, b in rises], [("try_bang", 2, 3)])
        self.assertEqual([(p.name, a, b) for p, a, b in drops], [("force_cast", 3, 1)])

    def test_grown_files_names_only_files_that_grew(self):
        """Files at or below their baseline count are not blamed for a rise."""
        baseline = {"patterns": {"try_bang": {"total": 2, "files": {"A.swift": 2}}}}
        current = {"try_bang": {"total": 3, "files": {"A.swift": 2, "B.swift": 1}}}
        self.assertEqual(grown_files(baseline, current, "try_bang"), ["B.swift"])

    def test_raise_is_recorded_with_reason(self):
        """Writing a higher count records the pattern, the change and the reason."""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "baseline.json"
            baseline = {"patterns": {"try_bang": {"total": 1, "files": {}}}}
            current = {p.name: {"total": 0, "files": {}} for p in PATTERNS}
            current["try_bang"] = {"total": 2, "files": {"A.swift": 2}}
            write_baseline(path, baseline, current, "Bundled resource, cannot fail")
            raised = json.loads(path.read_text())["raised"]
            self.assertEqual(len(raised), 1)
            self.assertEqual((raised[0]["pattern"], raised[0]["from"], raised[0]["to"]), ("try_bang", 1, 2))
            self.assertEqual(raised[0]["reason"], "Bundled resource, cannot fail")


if __name__ == "__main__":
    sys.exit(main())
