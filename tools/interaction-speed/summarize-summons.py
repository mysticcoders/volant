"""Extract only fixed-metadata readiness events; retain failures in the report."""
import collections, math, re, statistics, sys
samples = collections.defaultdict(list)
failed = collections.Counter()
pattern = re.compile(r'end\] Summon:? source=(hotkey|workspace|menu|other) ready=([01]) elapsed_ms=(\S+)')
for line in open(sys.argv[1]):
    match = pattern.search(line)
    if not match:
        continue
    source, ready, raw = match.groups()
    value = float(raw)
    if not math.isfinite(value) or value < 0:
        raise ValueError('Invalid monotonic timing sample')
    if ready == '0':
        failed[source] += 1
    else:
        samples[source].append(value)
print('Handler entry → native editor readiness; NOT physical key → first displayed frame.')
for source in sorted(samples.keys() | failed.keys()):
    values = samples[source]
    print(f'{source}: ready={len(values)}, incomplete/cancelled={failed[source]}')
    if values:
        print(f'  median={statistics.median(values):.3f} ms, p95={sorted(values)[math.ceil(.95*len(values))-1]:.3f} ms, max={max(values):.3f} ms')
if not samples and not failed:
    print('No completed summon events captured. Use a build containing LauncherOpeningTrace and summon during capture.')
if not samples.get('hotkey'):
    print('No ready hotkey samples; other sources are not a substitute for the real shortcut path.')
