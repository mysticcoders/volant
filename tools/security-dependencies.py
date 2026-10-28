#!/usr/bin/env python3
"""Scan tracked lockfiles only; fail on new, expired debt, or scanner errors."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
LOCKFILES = {"package-lock.json", "Cargo.lock", "Package.resolved", "uv.lock", "requirements.txt"}


def findings(report, root=ROOT):
    found = set()
    for result in report["results"]:
        path = Path(result["source"]["path"])
        if path.is_absolute():
            path = path.relative_to(root)
        for entry in result["packages"]:
            package = entry["package"]
            for vulnerability in entry.get("vulnerabilities", []):
                found.add((path.as_posix(), package["ecosystem"], package["name"],
                           package["version"], vulnerability["id"]))
    return found


def evaluate(current, baseline, today):
    known = {tuple(entry) for entry in baseline["findings"]}
    new = current - known
    expired = current & known if today >= datetime.date.fromisoformat(baseline["expires"]) else set()
    return new, expired


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scanner", default="osv-scanner")
    parser.add_argument("--output", default="/tmp/volant-dependencies.json")
    args = parser.parse_args()
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    locks = sorted(p for p in tracked if Path(p).name in LOCKFILES)
    if not locks:
        raise RuntimeError("No tracked dependency inputs found")
    print("Scanning tracked inputs:\n" + "\n".join(locks), flush=True)
    output = Path(args.output).resolve()
    output.unlink(missing_ok=True)  # Never accept a report left by a failed prior scan.
    command = [args.scanner, "scan", "source", "--no-resolve", "--format", "json", "--output-file", str(output)]
    for lock in locks:
        command += ["--lockfile", lock]
    scan = subprocess.run(command, cwd=ROOT, check=False)
    if scan.returncode not in (0, 1) or not output.is_file():
        raise RuntimeError(f"OSV failed: exit {scan.returncode}")
    current = findings(json.loads(output.read_text()))
    if (scan.returncode == 1) != bool(current):
        raise RuntimeError("OSV exit status and vulnerability report disagree")
    baseline = json.loads((ROOT / "tools/security-dependency-debt.json").read_text())
    new, expired = evaluate(current, baseline, datetime.datetime.now(datetime.timezone.utc).date())
    print(f"{len(current)} package/version/advisory matches; {len(new)} new; {len(expired)} expired.")
    if current:
        print(f"Known debt expires {baseline['expires']}; see docs/security-review-2026-10-27.md. Full findings: {output}")
    for entry in sorted(new | expired):
        print("BLOCKED: " + " | ".join(entry))
    return 1 if new or expired else 0


if __name__ == "__main__":
    sys.exit(main())
