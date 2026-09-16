#!/usr/bin/env python3
"""Validate and summarize three matched cohorts; retain every first sample."""
import csv
import math
import statistics
import sys
from pathlib import Path
root = Path(sys.argv[1])
def values(path, mode, count):
    with path.open() as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == count
    assert [int(row['sample']) for row in rows] == list(range(1, count + 1))
    assert all(row['mode'] == mode for row in rows)
    result = [float(row['request_to_window_server_visible_ms']) for row in rows]
    assert all(math.isfinite(value) and 0 < value <= 10000 for value in result)
    return result
print('| App | Reopen median (60) | Reopen p95 | First reopen samples | Fresh-process median (15) | Fresh-process range |')
print('| --- | ---: | ---: | --- | ---: | --- |')
for app in ['volant', 'raycast']:
    warm, first, cold = [], [], []
    for run in range(1, 4):
        cohort = values(root / app / f'run-{run}' / 'reopen.csv', 'reopen', 20)
        warm.extend(cohort); first.append(cohort[0])
        cold.extend(values(root / 'startup' / f'{app}-{run}.csv', 'startup', 5))
    p95 = sorted(warm)[math.ceil(.95 * len(warm)) - 1]
    initial = ', '.join(f'{value:.1f}' for value in first)
    print(f'| {app} | {statistics.median(warm):.1f} ms | {p95:.1f} ms | {initial} ms | '
          f'{statistics.median(cold):.1f} ms | {min(cold):.1f}–{max(cold):.1f} ms |')
