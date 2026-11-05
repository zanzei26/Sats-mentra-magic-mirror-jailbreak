import json, sys, collections, bisect
# usage: trace-analyze2.py trace.jsonl  - who occupies the renderer main thread outside the animation-frame callbacks?
events = []
for line in open(sys.argv[1], encoding='utf-8'):
    events.extend(json.loads(line)['params']['value'])
names = {(e['pid'], e['tid']): e['args']['name'] for e in events if e.get('ph') == 'M' and e.get('name') == 'thread_name'}
pid, tid = [k for k, v in names.items() if v == 'CrRendererMain'][0]
ev = sorted([e for e in events if e.get('pid') == pid and e.get('tid') == tid and e.get('ph') == 'X'], key=lambda e: e['ts'])
t0 = ev[0]['ts']; t1 = max(e['ts'] + e['dur'] for e in ev); span = (t1 - t0) / 1e6
faf = [(e['ts'], e['ts'] + e['dur']) for e in ev if e['name'] == 'FireAnimationFrame']
fd = sorted((b - a) / 1000 for a, b in faf)
print(f"span {span:.1f} s; FireAnimationFrame n={len(faf)} p50 {fd[len(fd)//2]:.1f} p90 {fd[int(len(fd)*.9)]:.1f} p99 {fd[int(len(fd)*.99)]:.1f} max {fd[-1]:.1f} ms")
gaps = sorted((faf[i+1][0] - faf[i][0]) / 1000 for i in range(len(faf) - 1))
print(f"rAF start-to-start: p50 {gaps[len(gaps)//2]:.1f} p90 {gaps[int(len(gaps)*.9)]:.1f} p99 {gaps[int(len(gaps)*.99)]:.1f} max {gaps[-1]:.1f} ms; >34 ms: {sum(1 for g in gaps if g>34)} of {len(gaps)}")
# containers: FAF and EventDispatch intervals
cont = sorted(faf + [(e['ts'], e['ts'] + e['dur']) for e in ev if e['name'] == 'EventDispatch'])
starts = [c[0] for c in cont]
def inside(a, b):
    i = bisect.bisect_right(starts, a) - 1
    while i >= 0 and cont[i][0] <= a:
        if cont[i][1] >= b - 1: return True
        i -= 1
        if a - cont[i][0] > 2e6: break
    return False
top = collections.Counter(); cnt = collections.Counter(); big = []
for e in ev:
    if e['name'] not in ('FunctionCall', 'TimerFire', 'MajorGC', 'MinorGC', 'UpdateLayoutTree', 'PrePaint'): continue
    a, b = e['ts'], e['ts'] + e['dur']
    if e['name'] == 'FunctionCall' and inside(a, b): continue
    if e['name'] in ('UpdateLayoutTree', 'PrePaint') and inside(a, b): continue
    d = e.get('args', {}).get('data', {})
    key = e['name'] + ' ' + (d.get('functionName') or '') + ' ' + (d.get('url') or '').split('/')[-1].split('?')[0] + ':' + str(d.get('lineNumber', ''))
    top[key] += e['dur']; cnt[key] += 1
    if e['dur'] > 8000: big.append((e['dur'] / 1000, key))
print("--- main-thread work OUTSIDE rAF/event handlers (top-level), by total time")
for k, t in top.most_common(14):
    print(f"{t/1000:8.0f} ms  {100*t/1e6/span:5.1f} %  n={cnt[k]:4d}  {k}")
print("--- individual tasks > 8 ms outside rAF/events:", len(big))
for d, k in sorted(big, reverse=True)[:10]:
    print(f"{d:7.1f} ms  {k}")
