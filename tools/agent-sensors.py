#!/usr/bin/env python3
"""Run Volant's fast, deterministic checks for what this branch changed, in the agent's own loop.

CI runs the full suite minutes after a push, which is too late for an agent still making the change.
This runs the subset that takes seconds, chosen from the files that changed (the branch's diff from
origin/main plus staged, unstaged and untracked files), and writes each finding as guidance: what
failed, why the rule exists, what to do, and how to disagree on purpose.

Wired as a Claude Code Stop hook in .claude/settings.json. With --hook it reads the hook payload on
stdin and exits 2 with findings on stderr, which blocks the stop and hands the findings back to the
agent. A hash of HEAD and the working tree makes an unchanged, already-green tree instant, and an
identical repeat failure while stop_hook_active is set is let through, so the hook cannot loop.

Not run here, on purpose: unit tests, UI checks, xcodebuild, string catalogs and anything that needs a
signed build. Those stay with Scripts/test.sh and CI.

Usage:
  python3 tools/agent-sensors.py          run once (exit 1 on findings)
  python3 tools/agent-sensors.py --all    run every sensor whatever changed
  python3 tools/agent-sensors.py --hook   Claude Code Stop-hook protocol
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = "origin/main"


class Sensor:
    """One check: when it applies, the command that runs it, and guidance for a failure."""

    def __init__(self, name, applies, command, why, disagree, needs=None):
        self.name = name
        self.applies = applies
        self.command = command
        self.why = why
        self.disagree = disagree
        self.needs = needs


def any_swift(paths):
    """Return whether any changed path is Swift source."""
    return any(p.endswith(".swift") for p in paths)


def linted_swift(paths):
    """Return whether a change touches the folders SwiftLint covers, or its configuration."""
    return any(p == ".swiftlint.yml" or (p.endswith(".swift") and p.startswith(
        ("Volant/Panel/", "Volant/Import/", "Core/Sources/VolantCore/Launcher/"))) for p in paths)


def entitlements_or_project(paths):
    """Return whether a change touches entitlements or the project definition."""
    return any(p.endswith(".entitlements") or p == "project.yml" for p in paths)


def new_top_level_or_scope(paths):
    """Return whether the test-scope classifier or its inputs could be affected, including a new top-level path."""
    known = set(git("ls-tree", "--name-only", BASE).split())
    return any(p.startswith("tools/test-scope") or p.split("/")[0] not in known for p in paths)


def core_changed(paths):
    """Return whether VolantCore's sources or manifest changed."""
    return any(p.startswith("Core/Sources/") or p == "Core/Package.swift" for p in paths)


def ratchet_inputs(paths):
    """Return whether Swift or the ratchet tool and baseline changed."""
    return any_swift(paths) or any(p.startswith("tools/ratchet") for p in paths)


SENSORS = (
    Sensor("ratchets", ratchet_inputs, ["python3", "tools/ratchets.py"],
           "Counts of patterns Volant wants to shrink may only go down (tools/ratchets.py says why for each).",
           "If an occurrence is genuinely right, raise the baseline with "
           "python3 tools/ratchets.py --update --reason \"...\" and give the reason in the PR."),
    Sensor("swiftlint", linted_swift, ["swiftlint", "lint", "--strict", "--quiet", "--config", ".swiftlint.yml"],
           "Each rule in .swiftlint.yml encodes a launcher or import bug Volant has already had.",
           "If a rule is wrong for a case, change .swiftlint.yml with a comment saying why, in this change.",
           needs="swiftlint"),
    Sensor("input confinement", any_swift, ["python3", "tools/check-input-confinement.py"],
           "Accessibility and event posting live only in VolantInputHost (docs/adr/0004).",
           "Add a narrow method to VolantInputHost instead. Changing the rule needs a new ADR."),
    Sensor("Volant Dev entitlements", entitlements_or_project, ["python3", "tools/check-dev-entitlements.py"],
           "Volant Dev must match the release entitlements minus iCloud (docs/adr/0010).",
           "Change both entitlement files together; the check lists the keys that differ."),
    Sensor("test-scope classifier", new_top_level_or_scope, ["python3", "tools/test-scope-tests.py"],
           "CI picks which macOS jobs to run from tools/test-scope.py; an unclassified path runs everything "
           "and fails these tests.",
           "Add the new path to NATIVE_PATTERNS or OTHER_PATTERNS in tools/test-scope.py."),
    Sensor("VolantCore build", core_changed, ["swift", "build", "--package-path", "Core", "-q"],
           "VolantCore is Foundation-only (docs/adr/0005); a platform import or type error fails here first.",
           "Code that needs a platform framework belongs in the app target, not Core.",
           needs="swift"),
)


def git(*args):
    """Run git in the repository and return its standard output."""
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def changed_paths():
    """List paths changed on this branch, in the index, in the working tree, or untracked."""
    paths = set()
    try:
        merge_base = git("merge-base", BASE, "HEAD").strip()
        paths.update(git("diff", "--name-only", merge_base, "HEAD").split())
    except subprocess.CalledProcessError:
        pass
    paths.update(git("diff", "--name-only", "HEAD").split())
    paths.update(git("ls-files", "--others", "--exclude-standard").split())
    return sorted(paths)


def state_hash():
    """Hash HEAD, the working-tree diff and untracked file contents, so an unchanged tree is recognized."""
    digest = hashlib.sha256()
    digest.update(git("rev-parse", "HEAD").encode())
    digest.update(git("diff", "HEAD", "--binary").encode())
    for path in sorted(git("ls-files", "--others", "--exclude-standard").split()):
        file = ROOT / path
        if file.is_file():
            digest.update(path.encode())
            digest.update(file.read_bytes())
    return digest.hexdigest()


def stamp_path(name):
    """Return a per-worktree stamp file inside the git directory."""
    return Path(git("rev-parse", "--absolute-git-dir").strip()) / f"agent-sensors-{name}"


def whitespace_finding(paths):
    """Run git diff --check over the changed paths and return its output, or None when clean."""
    tracked = [p for p in paths if (ROOT / p).exists()]
    if not tracked:
        return None
    result = subprocess.run(["git", "diff", "--check", "HEAD", "--", *tracked], cwd=ROOT,
                            capture_output=True, text=True)
    return result.stdout.strip() or None


def run(run_all):
    """Run the sensors that apply and return a list of finding texts."""
    paths = changed_paths()
    findings = []
    for sensor in SENSORS:
        if not run_all and not sensor.applies(paths):
            continue
        if sensor.needs and not shutil.which(sensor.needs):
            findings.append(f"[{sensor.name}] skipped: {sensor.needs} is not installed. CI will still run it.")
            continue
        result = subprocess.run(sensor.command, cwd=ROOT, capture_output=True, text=True)
        if result.returncode != 0:
            output = (result.stdout + result.stderr).strip()
            findings.append(f"[{sensor.name}] failed: {' '.join(sensor.command)}\n{output}\n"
                            f"Why: {sensor.why}\nTo disagree: {sensor.disagree}")
    whitespace = whitespace_finding(paths)
    if whitespace:
        findings.append(f"[whitespace] git diff --check found problems:\n{whitespace}\n"
                        "Why: CI runs git diff --check on every PR.\nTo disagree: you can't; fix the lines.")
    return findings


def hook():
    """Stop-hook protocol: exit 2 with findings on stderr to block the stop once, else exit 0."""
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        payload = {}
    state = state_hash()
    green, failed = stamp_path("green"), stamp_path("fail")
    if green.exists() and green.read_text() == state:
        return 0
    if payload.get("stop_hook_active") and failed.exists() and failed.read_text() == state:
        return 0
    findings = [f for f in run(False) if "skipped:" not in f.split("\n", 1)[0]]
    if not findings:
        green.write_text(state)
        failed.unlink(missing_ok=True)
        return 0
    failed.write_text(state)
    print("Volant agent sensors found problems in this change. Fix them, or follow the disagree route "
          "each one names, before finishing.\n\n" + "\n\n".join(findings), file=sys.stderr)
    return 2


def main():
    """Run once from the command line, or follow the Stop-hook protocol with --hook."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--hook", action="store_true", help="Claude Code Stop-hook protocol")
    parser.add_argument("--all", action="store_true", help="run every sensor whatever changed")
    args = parser.parse_args()
    if args.hook:
        return hook()
    findings = run(args.all)
    for finding in findings:
        print(finding + "\n")
    blocking = [f for f in findings if "skipped:" not in f.split("\n", 1)[0]]
    print(f"agent sensors: {len(blocking)} finding(s)" if blocking else "agent sensors: clean")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
