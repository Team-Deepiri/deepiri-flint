# deepiri-bedd

**Bedd** is a Bun-style **runtime/CLI** for stream skills (Zig) — not a platform microservice.

Install it into a worker image (or on PATH), then `bedd serve` / `bedd eval` / `bedd bench`. Hosts supply `BEDD_BUS_URL` + tinder routes + skills. See [docs/INSTALL.md](docs/INSTALL.md) and [docs/VALUE.md](docs/VALUE.md).

HTTP bus in → route table → native/WASM skill → bus out → ack.

## Install

```bash
./install.sh
# or Zig 0.13:
zig build -Doptimize=ReleaseSafe -Dcpu=baseline
export PATH="$PWD/zig-out/bin:$PATH"
```

Docker into **your** service (like `COPY --from=oven/bun`):

```dockerfile
FROM ghcr.io/team-deepiri/bedd:0.6 AS bedd
FROM your-base
COPY --from=bedd /usr/local/bin/bedd /usr/local/bin/bedd
```

Do **not** run Bedd as a separate compose service next to Sugar Glider.

## Quick start

```bash
./zig-out/bin/bedd version
./zig-out/bin/bedd doctor
./zig-out/bin/bedd skills
./zig-out/bin/bedd strike inbox demo.event echo
./zig-out/bin/bedd filter redact   # NDJSON pipe
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

Builtins: `echo`, `passthrough`, `redact`, `fingerprint`, `schema_gate`, `drop_fields`. Everything else is WASM or host-supplied.

## Env

| Var | Default |
|-----|---------|
| `BEDD_BUS_URL` | `http://127.0.0.1:8081` or `redis://127.0.0.1:6379/0` |
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
