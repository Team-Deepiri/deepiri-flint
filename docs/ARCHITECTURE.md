# Architecture

Bedd is one binary:

1. **Bus client** — HTTP `healthz` / `readyz` / `v1/publish` / `v1/read` / `v1/ack`
2. **Tinder** — JSON routes: `(stream, event_type*) → skill → publish_stream`
3. **Skills** — builtins + `BEDD_SKILLS_DIR/*.wasm` (`bedd_skill_v1`)
4. **Serve** — read → match → strike → ack; DLQ on failure to `BEDD_DLQ_STREAM`
5. **Admin** — `:BEDD_ADMIN_PORT` health + Prometheus metrics

Streams and event types are opaque strings. No host topic catalog lives in core.
