# ADR-014: pressure_tag skill feeds pipeline.metrics

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
pressure_tag skill feeds pipeline.metrics.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
