import re,collections,sys
agg=collections.defaultdict(collections.Counter); name=None
for line in sys.stdin:
    m=re.match(r'^[0-9a-f]+-[0-9a-f]+ (\S+) \S+ \S+ \S+\s*(.*)$', line)
    if m:
        path=m.group(2).strip(); name=path.split('/')[-1] if path.startswith('/') else (path or '[anonymous memory]'); continue
    m=re.match(r'^(\w+):\s+(\d+) kB', line)
    if m: agg[name][m.group(1)]+=int(m.group(2))
tot=collections.Counter()
for c in agg.values(): tot.update(c)
top=sorted(agg.items(), key=lambda kv:-kv[1]['Private_Dirty'])[:4]
print(f"   cannot be dropped {tot['Private_Dirty']/1024:.0f} MiB = " + ", ".join(f"{n} {c['Private_Dirty']/1024:.0f}" for n,c in top) + f" | file-backed {(tot['Rss']-tot['Private_Dirty'])/1024:.0f} MiB")
