#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ZIG_PATH:-/tmp/zig-linux-x86_64-0.13.0}:$PATH"
cd "$ROOT"
zig build -Dcpu=baseline
./zig-out/bin/bedd version
./zig-out/bin/bedd doctor || true
./zig-out/bin/bedd skills
./zig-out/bin/bedd eval redact '{"token":"x"}' >/dev/null
./zig-out/bin/bedd eval fingerprint '{"a":1}' >/dev/null
./zig-out/bin/bedd strike inbox demo.event echo
BEDD_SKILLS_DIR=zig-out/skills ./zig-out/bin/bedd strike inbox x echo_skill
echo "smoke ok"
