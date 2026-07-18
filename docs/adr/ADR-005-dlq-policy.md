# ADR-005: Failed strikes publish to pipeline.dead-letter

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
Failed strikes publish to pipeline.dead-letter.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
