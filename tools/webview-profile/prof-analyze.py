import json, sys, collections
# usage: prof-analyze.py profile.json [top_n]
# Self time per function from a CDP Profiler.stop result ({"id":N,"result":{"profile":{...}}}).
path = sys.argv[1]
top = int(sys.argv[2]) if len(sys.argv) > 2 else 35
raw = json.load(open(path, encoding='utf-8-sig'))
p = raw['result']['profile']
nodes = {n['id']: n for n in p['nodes']}
samples, deltas = p['samples'], p['timeDeltas']
total = sum(deltas)
self_t = collections.Counter()
by_url = collections.Counter()
for sid, dt in zip(samples, deltas):
    n = nodes[sid]
    cf = n['callFrame']
    name = cf['functionName'] or '(anon)'
    url = cf['url'].split('/')[-1].split('?')[0] or '-'
    key = (name, url, cf['lineNumber'] + 1, cf['columnNumber'] + 1)
    self_t[key] += dt
    by_url[url] += dt
print(f"samples {len(samples)}, wall {total/1e6:.1f} s")
idle = sum(t for k, t in self_t.items() if k[0] == '(idle)')
print(f"(idle) {100*idle/total:.1f} %  (program) {100*sum(t for k,t in self_t.items() if k[0]=='(program)')/total:.1f} %  (gc) {100*sum(t for k,t in self_t.items() if k[0]=='(garbage collector)')/total:.1f} %")
print("--- self time by script")
for u, t in by_url.most_common(8):
    print(f"{100*t/total:5.1f} %  {u}")
if len(sys.argv) > 3 and sys.argv[3] == 'incl':
    parent = {}
    for n in p['nodes']:
        for c in n.get('children', []):
            parent[c] = n['id']
    incl = collections.Counter()
    for sid, dt in zip(samples, deltas):
        seen = set()
        cur = sid
        while cur is not None:
            cf = nodes[cur]['callFrame']
            key = (cf['functionName'] or '(anon)', cf['url'].split('/')[-1].split('?')[0] or '-', cf['lineNumber'] + 1, cf['columnNumber'] + 1)
            if key not in seen:
                seen.add(key)
                incl[key] += dt
            cur = parent.get(cur)
    print("--- top INCLUSIVE time functions (stack-inclusive, may overlap)")
    k = 0
    for (name, url, line, col), t in incl.most_common():
        if name in ('(root)', '(idle)', '(program)'):
            continue
        print(f"{100*t/total:5.1f} %  {t/1000:8.0f} ms  {name}  {url}:{line}:{col}")
        k += 1
        if k >= 45:
            break
    sys.exit(0)
print("--- top self-time functions (excluding idle)")
shown = 0
for (name, url, line, col), t in self_t.most_common():
    if name == '(idle)':
        continue
    print(f"{100*t/total:5.1f} %  {t/1000:8.0f} ms  {name}  {url}:{line}:{col}")
    shown += 1
    if shown >= top:
        break
