# ADR-006: BEDD_DRY_RUN skips publish and ack side effects

## Status
Accepted

## Context
Bedd is a portable stream skill runtime: opaque routes, pluggable HTTP bus, native/WASM skills.

## Decision
BEDD_DRY_RUN skips publish and ack side effects.

## Consequences
- Hosts supply route files and bus URL; Bedd stays topic-agnostic
- Keeps the runtime small and operable
