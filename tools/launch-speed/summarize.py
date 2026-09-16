#!/usr/bin/env python3
"""Validate and summarize opening trials, without machine-specific thresholds."""
import csv
import math
import statistics
import sys
from pathlib import Path
root = Path(sys.argv[1])
print("| Test | Trials | Median ms | P95 ms (nearest rank) | Min–max ms |")
print("| --- | ---: | ---: | ---: | ---: |")
for mode, count in [("reopen", 20), ("startup", 5)]:
    with (root / f"{mode}.csv").open() as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == count
    assert [int(row["sample"]) for row in rows] == list(range(1, count + 1))
    assert all(row["mode"] == mode for row in rows)
    values = [float(row["request_to_window_server_visible_ms"]) for row in rows]
    assert all(math.isfinite(value) and 0 < value <= 10000 for value in values)
    ordered = sorted(values)
    print(f"| {mode} | {count} | {statistics.median(values):.1f} | "
          f"{ordered[math.ceil(.95 * count) - 1]:.1f} | {ordered[0]:.1f}–{ordered[-1]:.1f} |")
