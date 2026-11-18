#!/usr/bin/env python3
"""Spike for docs/mcp-server-design.md: which local transport can an MCP server for Volant use while
the main app keeps no network entitlement? Builds tools/mcp-transport/probe.c and signs copies with
the release Developer ID identity (team REMBT6JY4N, needed for a team-prefixed app group) and only the
entitlements each case needs, then runs servers and clients against each other:

  1. sandboxed, no network entitlement, app group: listen on a Unix socket in the group container
  2. separate process, same team and app group, sandboxed: connect to it (the volant-mcp bridge)
  3. unsigned, unsandboxed process: connect to it (any local program)
  4. sandboxed with network.server only: listen on 127.0.0.1; control: the same without it

It uses a probe-only app group and probe-only bundle identifiers, never Volant's real containers. macOS
protects container folders from other processes, so the probes' empty containers stay in
~/Library/Containers and ~/Library/Group Containers (names containing transport-probe); remove them in
Finder if wanted. Run it on the owner's Mac; it needs the Developer ID identity in the login keychain."""
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IDENTITY = os.environ.get("VOLANT_SIGNING_IDENTITY", "Developer ID Application: Mystic Coders, LLC (REMBT6JY4N)")
GROUP = "REMBT6JY4N.com.mysticcoders.volant.transport-probe"
SOCKET = Path.home() / "Library/Group Containers" / GROUP / "mcp.sock"


def build(work: Path, name: str, entitlements: dict | None, identity: str | None) -> Path:
    """Compiles the probe with its own bundle identifier and signs it with the given entitlements."""
    info = work / f"{name}.plist"
    info.write_bytes(plistlib.dumps({"CFBundleIdentifier": f"com.mysticcoders.volant.transport-probe.{name}"}))
    binary = work / name
    subprocess.run(["clang", "-O1", "-o", binary, ROOT / "tools/mcp-transport/probe.c",
                    f"-Wl,-sectcreate,__TEXT,__info_plist,{info}", "-framework", "Security", "-framework", "CoreFoundation"], check=True)
    if identity:
        command = ["codesign", "-s", identity, "-f", "-i", f"com.mysticcoders.volant.transport-probe.{name}"]
        if entitlements is not None:
            plist = work / f"{name}.entitlements"
            plist.write_bytes(plistlib.dumps(entitlements))
            command += ["--entitlements", plist]
        subprocess.run(command + [binary], check=True, capture_output=True)
    return binary


def pair(server: list, client) -> tuple[str, str]:
    """Starts a server, waits until it listens (or fails), runs one client built from the server's
    first line, and returns both outputs."""
    process = subprocess.Popen(server, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    first = process.stdout.readline().strip()
    if not first.startswith("LISTENING"):
        process.wait(timeout=20)
        return first, "not run"
    reply = subprocess.run(client(first), capture_output=True, text=True, timeout=20)
    rest = process.communicate(timeout=20)[0].strip()
    return f"{first} {rest}".strip(), (reply.stdout + reply.stderr).strip() or f"exit {reply.returncode}"


def main() -> int:
    sandbox = {"com.apple.security.app-sandbox": True}
    grouped = {**sandbox, "com.apple.security.application-groups": [GROUP]}
    with tempfile.TemporaryDirectory(prefix="volant-transport.") as name:
        work = Path(name)
        server = build(work, "unix-server", grouped, IDENTITY)
        bridge = build(work, "bridge", grouped, IDENTITY)
        stranger = build(work, "stranger", None, None)
        tcp_server = build(work, "tcp-server", {**sandbox, "com.apple.security.network.server": True}, IDENTITY)
        tcp_control = build(work, "tcp-control", sandbox, IDENTITY)
        tcp_client = build(work, "tcp-client", None, None)
        results = []
        for label, client in [("bridge, same team and app group", bridge), ("stranger, unsigned and unsandboxed", stranger)]:
            served, connected = pair([server, "serve-unix", str(SOCKET)], lambda _, c=client: [c, "connect-unix", str(SOCKET)])
            results.append((f"Unix socket in the app group; client: {label}", served, connected))
        for label, binary in [("sandboxed with network.server", tcp_server), ("control: sandboxed, no network entitlement", tcp_control)]:
            served, connected = pair([binary, "serve-tcp", "-"], lambda first: [tcp_client, "connect-tcp", first.split()[-1]])
            results.append((f"Loopback TCP; server: {label}", served, connected))
    for case, served, connected in results:
        print(f"{case}\n  server: {served}\n  client: {connected}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
