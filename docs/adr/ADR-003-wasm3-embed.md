# ADR-003: Embed wasm3 for in-process WASM skills

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
Embed wasm3 for in-process WASM skills.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
