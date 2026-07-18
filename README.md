# deepiri-bedd

**Bedd** is a portable stream skill runtime (Zig): HTTP bus in → route table → native/WASM skill → bus out → ack.

It does not hardcode any host product's topics or services. Point `BEDD_BUS_URL` at any bus that speaks the Bedd HTTP shape (`/healthz`, `/readyz`, `/v1/publish`, `/v1/read`, `/v1/ack`), load a route file, drop skills under `BEDD_SKILLS_DIR`.

## Build

```bash
# Zig 0.13.0; use -Dcpu=baseline on WSL if needed
zig build -Doptimize=ReleaseSafe -Dcpu=baseline
zig build test -Dcpu=baseline
```

## Quick start

```bash
./zig-out/bin/bedd version
./zig-out/bin/bedd doctor
./zig-out/bin/bedd skills
./zig-out/bin/bedd strike inbox demo.event echo
./zig-out/bin/bedd eval redact '{"token":"secret"}'
./zig-out/bin/bedd demo
./zig-out/bin/bedd tinder validate tinder.example.json

export BEDD_BUS_URL=http://127.0.0.1:8081
export BEDD_TINDER=./tinder.example.json
export BEDD_DRY_RUN=1
./zig-out/bin/bedd serve
```

## Shape

```
HTTP bus ──► bedd serve ──► tinder routes ──► skill ──► publish ──► ack
                 │
                 └── admin :9108  /healthz /metrics
```

| Concept | Meaning |
|---------|---------|
| **Bus** | Anything exposing Bedd's small HTTP API |
| **Tinder** | JSON route table: stream + event → skill → publish stream |
| **Skill** | Native builtin or WASM (`bedd_skill_v1`) |
| **Strike** | One consume → skill → publish cycle |

Builtins: `echo`, `passthrough`, `redact`, `fingerprint`, `schema_gate`. Everything else is WASM or host-supplied.

## Env

| Var | Default |
|-----|---------|
| `BEDD_BUS_URL` | `http://127.0.0.1:8081` |
| `BEDD_SENDER` | `bedd` |
| `BEDD_CONSUMER_GROUP` | `bedd-workers` |
| `BEDD_CONSUMER_NAME` | `bedd-1` |
| `BEDD_SKILLS_DIR` | `zig-out/skills` |
| `BEDD_TINDER` | (built-in inbox→outbox) |
| `BEDD_DLQ_STREAM` | `dead-letter` |
| `BEDD_DRY_RUN` | `false` |
| `BEDD_ADMIN_PORT` | `9108` |

## License

See `LICENSE`.
