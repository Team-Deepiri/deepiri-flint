# Changelog

## 0.8.1 — exchange
- Hot-path speedups: in-place redact, lean filter output, arena + buffered IO, ReleaseFast install
- Faster `drop_fields` single-pass; builtin lookup helper for filter

## 0.8.0 — exchange
- Skill exchange: direct / topic / headers / fanout bindings
- Skill chains (`redact,drop_fields`), recovery_skill, publisher confirms
- Prefetch QoS weighted by skill cost; `BEDD_LEAN` publish mode


## 0.7.0 — filter
- `bedd filter` — NDJSON stdin→stdout skill pipe (use inside workers without `serve`)
- Direct `redis://` bus transport (XADD / XREADGROUP / XACK) — skip HTTP sidecar hop
- Builtin `drop_fields` (`BEDD_DROP_FIELDS`)
- `bedd bench --mode skill|redis|mock` — honest skill floor + Redis Streams A/B
- Serve-loop arena allocator per read batch

## 0.6.0 — spark
- `bedd bench` — mock-bus e2e perf; Bun-style `install.sh` + dual gnu/musl image

## 0.5.0 — spark
- Rename Flint → **Bedd**; strip host-specific coupling

## 0.4.x — ember
- Mock bus, eval, admin, DLQ, retry

## 0.3.0 — strike
- Admin HTTP, DLQ, Helm/k8s

## 0.2.0
- HTTP bus client, tinder routing, serve loop, wasm3 skills

## 0.1.0
- Initial scaffold
