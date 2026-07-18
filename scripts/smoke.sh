#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${ZIG_PATH:-/tmp/zig-linux-x86_64-0.13.0}:$PATH"
cd "$ROOT"
zig build -Dcpu=baseline
./zig-out/bin/flint version
./zig-out/bin/flint doctor || true
./zig-out/bin/flint skills
./zig-out/bin/flint eval redact '{"token":"x"}' >/dev/null
./zig-out/bin/flint eval fingerprint '{"a":1}' >/dev/null
./zig-out/bin/flint strike document.artifacts document.artifacts.route echo
FLINT_SKILLS_DIR=zig-out/skills ./zig-out/bin/flint strike document.artifacts x echo_skill
echo "smoke ok"
