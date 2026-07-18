# ADR-006: FLINT_DRY_RUN skips publish and ack side effects

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
FLINT_DRY_RUN skips publish and ack side effects.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
