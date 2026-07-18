# ADR-001: Bedd as a portable stream skill runtime

## Context
Hosts need a single-binary worker that can consume stream events, run skills, and publish results without embedding host-specific topic catalogs in the core.

## Decision
Bedd owns: HTTP bus client shape, route table (tinder), skill ABI (native + wasm3), serve loop, admin metrics, configurable DLQ stream name.
Hosts own: bus implementation, stream names, domain skills (as WASM or separate packages), route files.

## Consequences
Core stays product-agnostic. Integration is config + skills, not forks of Bedd's topic layer.
