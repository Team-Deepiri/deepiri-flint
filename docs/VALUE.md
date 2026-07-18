# When Bedd helps (and when it does not)

## Helps
- **Filter path:** redact / drop_fields / fingerprint / schema_gate on JSON in a worker via `bedd filter` or `bedd eval` (no extra consumer group).
- **Direct Redis serve:** `BEDD_BUS_URL=redis://…` when you want a dedicated skill consumer without an HTTP bus hop.
- **Portable skills:** same binary + WASM ABI across Alpine/Debian workers.

## Does not help
- Embedding the binary in every Dockerfile **without invoking it** (dead weight).
- Running as a Compose sidecar on every stream hop (extra latency + ops).
- Replacing Sugar Glider / Cyrex / LIS domain logic — Bedd is a skill tool, not the bus.

## Verdict method
Compare the same workload:
1. **without** Bedd: Node/Python does redact/drop inline
2. **with** Bedd filter: pipe NDJSON through `bedd filter`
3. optional: Redis `bedd serve` vs HTTP bus `bedd serve`

Prefer Bedd when filter latency and consistency beat the host language for that skill — or when you want one binary across many workers. Prefer without when skills are trivial one-liners already in-process and Bedd would only be PATH clutter.
