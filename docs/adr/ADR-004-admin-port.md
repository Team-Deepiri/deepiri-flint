# ADR-004: Expose /healthz and /metrics on BEDD_ADMIN_PORT

## Status
Accepted

## Context
Bedd is a portable stream skill runtime: opaque routes, pluggable HTTP bus, native/WASM skills.

## Decision
Expose /healthz and /metrics on BEDD_ADMIN_PORT.

## Consequences
- Hosts supply route files and bus URL; Bedd stays topic-agnostic
- Keeps the runtime small and operable
