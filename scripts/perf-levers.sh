#!/usr/bin/env bash
# Perf levers report: filter serial/parallel, skill micro, redis pipeline.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${BEDD_BIN:-$ROOT/zig-out/bin/bedd}"
OUT="${1:-$ROOT/bench-out/levers}"
N="${PERF_N:-5000}"
REDIS_URL="${BEDD_BUS_URL:-redis://127.0.0.1:6379/0}"
mkdir -p "$OUT"

if [[ ! -x "$BIN" ]]; then
  echo "missing $BIN — zig build -Doptimize=ReleaseFast -Dcpu=baseline" >&2
  exit 1
fi

python3 - <<PY
import json
from pathlib import Path
n=int("$N")
p=Path("/tmp/bedd-levers-in.ndjson")
p.write_text("\n".join(json.dumps({"id":i,"token":f"secret-{i}","n":i}) for i in range(n))+"\n")
print("wrote", p, "n=", n)
PY

run_filter() {
  local jobs="$1" name="$2"
  local t0 t1 ms thr
  t0=$(date +%s%N)
  "$BIN" filter redact --jobs "$jobs" </tmp/bedd-levers-in.ndjson >/tmp/bedd-levers-out.ndjson 2>"$OUT/${name}.err"
  t1=$(date +%s%N)
  ms=$(( (t1 - t0) / 1000000 ))
  [[ "$ms" -lt 1 ]] && ms=1
  thr=$(python3 -c "print(round($N/($ms/1000),1))")
  echo "{\"mode\":\"filter_jobs_${jobs}\",\"n\":$N,\"wall_ms\":$ms,\"thr_per_s\":$thr}" | tee "$OUT/${name}.json"
}

echo "== skill micro =="
"$BIN" bench --mode skill --iterations 2000 --skills redact,drop_fields --json | tee "$OUT/skill.json"

echo "== filter jobs=1 =="
run_filter 1 filter_j1
echo "== filter jobs=4 =="
run_filter 4 filter_j4
CPUS=$(nproc 2>/dev/null || echo 8)
echo "== filter jobs=$CPUS =="
run_filter "$CPUS" filter_jmax

echo "== python baseline =="
python3 - <<PY | tee "$OUT/python.json"
import json, time
n=$N
t0=time.perf_counter()
keys={"token"}
for line in open("/tmp/bedd-levers-in.ndjson"):
    o=json.loads(line)
    for k in list(o):
        if k in keys: o[k]="***"
ms=(time.perf_counter()-t0)*1000
print(json.dumps({"mode":"python_inline","n":n,"wall_ms":round(ms,2),"thr_per_s":round(n/(ms/1000),1)}))
PY

echo "== redis pipeline batch =="
if redis-cli ping >/dev/null 2>&1; then
  "$BIN" bench --mode redis --redis "$REDIS_URL" --iterations 200 --skills redact --json | tee "$OUT/redis.json"
else
  echo '{"mode":"redis","skipped":true}' | tee "$OUT/redis.json"
fi

python3 - <<'PY' "$OUT"
import json, sys, pathlib
out = pathlib.Path(sys.argv[1])
rows = []
for p in sorted(out.glob("*.json")):
    try:
        rows.append((p.stem, json.loads(p.read_text())))
    except Exception:
        pass
md = ["## Bedd perf levers", "", "| run | n | wall_ms | thr/s |", "|-----|---|---------|-------|"]
for name, r in rows:
    if r.get("skipped"): 
        md.append(f"| `{name}` | — | — | skipped |")
        continue
    md.append(f"| `{name}` | {r.get('n', r.get('iterations','?'))} | {r.get('wall_ms','?')} | {r.get('thr_per_s', r.get('throughput_per_s','?'))} |")
py = next((r for n,r in rows if n=="python"), {})
j1 = next((r for n,r in rows if n=="filter_j1"), {})
jmax = next((r for n,r in rows if "filter_j" in n and n!="filter_j1"), {})
# pick highest filter thr
filters = [(n,r) for n,r in rows if n.startswith("filter")]
best = max(filters, key=lambda x: float(x[1].get("thr_per_s",0))) if filters else None
ratio = None
if py and best and py.get("thr_per_s"):
    ratio = round(best[1]["thr_per_s"]/py["thr_per_s"], 2)
md += ["", f"**Best filter:** `{best[0] if best else '?'}` @ {best[1].get('thr_per_s') if best else '?'} /s",
       f"**vs Python:** {ratio}× (1.0 = parity)" if ratio is not None else "",
       "",
       "Levers: Redis pipeline batch + TCP_NODELAY, `filter --jobs N`, lean redis defaults, higher prefetch."]
(out/"REPORT.md").write_text("\n".join([x for x in md if x is not None])+"\n")
print((out/"REPORT.md").read_text())
PY
