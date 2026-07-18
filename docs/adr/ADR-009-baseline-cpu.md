# ADR-009: CI builds with -Dcpu=baseline for WSL portability

## Status
Accepted

## Context
Bedd is a portable stream skill runtime: opaque routes, pluggable HTTP bus, native/WASM skills.

## Decision
CI builds with -Dcpu=baseline for WSL portability.

## Consequences
- Hosts supply route files and bus URL; Bedd stays topic-agnostic
- Keeps the runtime small and operable
