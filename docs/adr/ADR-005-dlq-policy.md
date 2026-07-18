# ADR-005: Failed strikes publish to BEDD_DLQ_STREAM (default dead-letter)

## Status
Accepted

## Context
Bedd is a portable stream skill runtime: opaque routes, pluggable HTTP bus, native/WASM skills.

## Decision
Failed strikes publish to BEDD_DLQ_STREAM (default dead-letter).

## Consequences
- Hosts supply route files and bus URL; Bedd stays topic-agnostic
- Keeps the runtime small and operable
