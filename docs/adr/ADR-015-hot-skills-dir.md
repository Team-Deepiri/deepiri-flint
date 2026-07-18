# ADR-015: WASM skills loaded lazily from BEDD_SKILLS_DIR

## Status
Accepted

## Context
Bedd is a portable stream skill runtime: opaque routes, pluggable HTTP bus, native/WASM skills.

## Decision
WASM skills loaded lazily from BEDD_SKILLS_DIR.

## Consequences
- Hosts supply route files and bus URL; Bedd stays topic-agnostic
- Keeps the runtime small and operable
