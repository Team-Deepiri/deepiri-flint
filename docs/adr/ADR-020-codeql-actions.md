# ADR-020: CodeQL scans Actions YAML until Zig support

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
CodeQL scans Actions YAML until Zig support.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
