"""Summarize fixed-content signposts and matched installed-app timings."""
import collections
import csv
import datetime
import math
from pathlib import Path
import re
import statistics
import sys
from zoneinfo import ZoneInfo

root = Path(sys.argv[1])
def summarize(values):
    return f"n={len(values)}, median={statistics.median(values):.1f} ms, p95={sorted(values)[math.ceil(.95 * len(values))-1]:.1f} ms"

for mode, count in [('reopen', 20)]:
    for target in ['baseline', 'candidate']:
        values = []
        for trial in range(1, 4):
            rows = list(csv.DictReader((root / f'{target}-{mode}-{trial}.csv').open()))
            assert len(rows) == count
            assert [int(row['sample']) for row in rows] == list(range(1, count + 1))
            assert all(row['mode'] == mode for row in rows)
            cohort = [float(row['request_to_window_server_visible_ms']) for row in rows]
            assert all(math.isfinite(value) and 0 < value < 10000 for value in cohort)
            values += cohort
        print(target, mode, summarize(values))

records = collections.defaultdict(dict)
pattern = re.compile(r'(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) Sp Volant\[(\d+):[^]]+\].*\[spid (0x\w+), process,\s*(begin|end|event)\] (.*)')
for line in (root / 'signposts.log').read_text().splitlines():
    match = pattern.match(line)
    if match:
        timestamp, pid, signpost, kind, name = match.groups()
        records[(pid, signpost)][kind + ' ' + name] = datetime.datetime.fromisoformat(timestamp)

for target in ['baseline', 'candidate']:
    intervals = collections.defaultdict(list)
    unmatched = []
    for trial in range(1, 4):
        pid = (root / f'{target}-{trial}.pid').read_text().strip()
        cohort = [events for (process, _), events in records.items() if process == pid and 'begin Prepare launcher' in events]
        samples = list(csv.DictReader((root / f'{target}-reopen-{trial}.csv').open()))
        used = set()
        for sample in samples:
            assert sample['pid'] == pid
            request_start = float(sample['request_unix_seconds'])
            request_end = request_start + float(sample['request_to_window_server_visible_ms']) / 1000
            matching = [events for events in cohort if request_start - .002 <= events['begin Prepare launcher'].replace(tzinfo=ZoneInfo('America/Los_Angeles')).timestamp() <= request_end + .002]
            if not matching:
                # A cohort's initial unhide can use the already-visible window path,
                # which does not run toggle preparation. Keep it in end-to-end results.
                assert int(sample['sample']) == 1, (target, trial, sample['sample'])
                unmatched.append((trial, int(sample['sample'])))
                continue
            assert len(matching) == 1, (target, trial, sample['sample'], len(matching))
            events = matching[0]
            assert id(events) not in used
            used.add(id(events))
            ready = 'event Layout complete' if target == 'baseline' else 'event Search editor ready'
            pairs = {
                'prepare': ('begin Prepare launcher', 'end Prepare launcher'),
                'order window': ('begin Present and focus', 'event Window ordered'),
                'editor preparation': ('event Window ordered', ready),
                'focus': (ready, 'end Present and focus'),
                'total synchronous open': ('begin Prepare launcher', 'end Present and focus'),
            }
            for name, (start, end) in pairs.items():
                intervals[name].append((events[end] - events[start]).total_seconds() * 1000)
            prepare_time = events['begin Prepare launcher'].replace(tzinfo=ZoneInfo('America/Los_Angeles')).timestamp()
            intervals['request to toggle entry'].append((prepare_time - request_start) * 1000)
            intervals['forced layout count'].append(int('begin Required layout' in events))
    print(target, "unmatched initial reopen samples", unmatched)
    for name, values in intervals.items():
        if name == 'forced layout count':
            if target == 'candidate': print(target, name, sum(values), '/', len(values))
        else: print(target, name, summarize(values))
