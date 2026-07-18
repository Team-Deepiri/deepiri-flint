#!/usr/bin/env bash
set -euo pipefail
BIN="${1:-./zig-out/bin/bedd}"
N="${N:-1000}"
start=$(date +%s%N)
for i in $(seq 1 "$N"); do
  "$BIN" strike inbox demo.event echo >/dev/null
done
end=$(date +%s%N)
echo "strikes=$N ns=$((end-start))"
