# ADR-007: XREADGROUP via bus consumer identity

## Status
Accepted

## Context
Bedd is a portable stream skill runtime: opaque routes, pluggable HTTP bus, native/WASM skills.

## Decision
XREADGROUP via bus consumer identity.

## Consequences
- Hosts supply route files and bus URL; Bedd stays topic-agnostic
- Keeps the runtime small and operable
