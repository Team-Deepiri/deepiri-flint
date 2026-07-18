# ADR-002: Tinder JSON is the skill routing source of truth

## Status
Accepted

## Context
Bedd is a portable stream skill runtime: opaque routes, pluggable HTTP bus, native/WASM skills.

## Decision
Tinder JSON is the skill routing source of truth.

## Consequences
- Hosts supply route files and bus URL; Bedd stays topic-agnostic
- Keeps the runtime small and operable
