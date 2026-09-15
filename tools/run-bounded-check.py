#!/usr/bin/env python3
"""Run an owned check process group with a deadline and visible stage diagnostics."""
import os
import signal
import subprocess
import sys
import time

seconds, label, *command = sys.argv[1:]
start = time.monotonic()
print(f"START: {label} (timeout {seconds}s)", flush=True)
process = subprocess.Popen(command, start_new_session=True)
try:
    result = process.wait(timeout=float(seconds))
except subprocess.TimeoutExpired:
    print(f"TIMEOUT: {label}", file=sys.stderr, flush=True)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    result = 124
print(f"END: {label}: exit {result}, {time.monotonic() - start:.1f}s", flush=True)
sys.exit(result)
