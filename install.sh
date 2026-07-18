#!/usr/bin/env bash
# Install Bedd like Bun: put `bedd` on PATH. Not a service installer.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Team-Deepiri/deepiri-bedd/main/install.sh | bash
#   BEDD_VERSION=0.6.0 ./install.sh
set -euo pipefail

BEDD_VERSION="${BEDD_VERSION:-0.8.1}"
BEDD_INSTALL="${BEDD_INSTALL:-$HOME/.bedd}"
BIN_DIR="${BEDD_INSTALL}/bin"
REPO="${BEDD_REPO:-Team-Deepiri/deepiri-bedd}"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

mkdir -p "$BIN_DIR"

if command -v bedd >/dev/null 2>&1 && [[ "${BEDD_FORCE:-}" != "1" ]]; then
  echo "bedd already on PATH: $(command -v bedd) ($(bedd version 2>/dev/null || true))"
  echo "set BEDD_FORCE=1 to reinstall into $BIN_DIR"
  exit 0
fi

# Prefer building from a local checkout when present (dev).
# ReleaseFast for runtime throughput (filter / serve hot paths).
OPTIMIZE="${BEDD_OPTIMIZE:-ReleaseFast}"
if [[ -f "./build.zig" ]] && command -v zig >/dev/null 2>&1; then
  echo "building bedd from local tree (${OPTIMIZE})…"
  zig build -Doptimize="${OPTIMIZE}" -Dcpu=baseline
  install -m 755 ./zig-out/bin/bedd "$BIN_DIR/bedd"
else
  echo "fetching release asset bedd-${OS}-${ARCH} v${BEDD_VERSION}…"
  TMP="$(mktemp -d)"
  URL="https://github.com/${REPO}/releases/download/v${BEDD_VERSION}/bedd-${OS}-${ARCH}"
  if curl -fsSL "$URL" -o "$TMP/bedd"; then
    install -m 755 "$TMP/bedd" "$BIN_DIR/bedd"
  else
    echo "no release binary at $URL — clone and build:" >&2
    echo "  git clone https://github.com/${REPO}.git && cd deepiri-bedd && zig build -Doptimize=ReleaseSafe" >&2
    exit 1
  fi
  rm -rf "$TMP"
fi

echo "installed: $BIN_DIR/bedd"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "add to your shell rc:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
"$BIN_DIR/bedd" version || true
