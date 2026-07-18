# Changelog

## 0.5.0 — spark
- Rename Flint → **Bedd**
- Primitive core: opaque streams, `BEDD_BUS_URL`, configurable `BEDD_DLQ_STREAM`
- Drop host-specific topic catalogs and domain skills (LIS/Helox/AGI)
- Neutral defaults: `inbox` → `echo` → `outbox`
- Schema-only `bedd tinder validate`

## 0.4.1 — ember
- In-process mock bus (`bedd demo`) with timed HTTP assembly
- End-to-end integration test: read → strike → publish → ack
- Publish retry + circuit breaker; latency histograms on `/metrics`
- `bedd tinder validate`

## 0.4.0 — ember
- Real skill logic and `bedd eval`
- SIGTERM/SIGINT stop; SIGHUP reloads tinder
- Admin probes

## 0.3.0 — strike
- Admin HTTP, DLQ, Helm/k8s

## 0.2.0
- HTTP bus client, tinder routing, serve loop, wasm3 skills

## 0.1.0
- Initial scaffold
