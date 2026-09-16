import csv, math, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
for mode in ('baseline', 'prepared'):
    cohort = [r for r in rows if r['mode'] == mode]
    assert cohort and [int(r['cycle']) for r in cohort] == list(range(len(cohort)))
    assert all(int(r['launches']) == int(r['cycle']) + 1 for r in cohort)
    assert cohort[0]['kind'] == 'initial' and all(r['kind'] == 'reopen' for r in cohort[1:])
    print(mode, 'initial editor readiness ms:', cohort[0]['handler_to_editor_ready_ms'])
    for key in ('handler_to_editor_ready_ms', 'first_key_delivery_ms'):
        values = [float(r[key]) for r in cohort[1:]]
        assert values and all(math.isfinite(v) and 0 <= v < 10000 for v in values)
        print(mode, key, f'n={len(values)} median={statistics.median(values):.3f} p95={sorted(values)[math.ceil(.95*len(values))-1]:.3f} ms')
assert len([r for r in rows if r['mode'] == 'baseline']) == len([r for r in rows if r['mode'] == 'prepared'])
