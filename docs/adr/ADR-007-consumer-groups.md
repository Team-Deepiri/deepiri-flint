# ADR-007: XREADGROUP via Sugar Glider consumer identity

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
XREADGROUP via Sugar Glider consumer identity.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
