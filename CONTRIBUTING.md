# Contributing

1. Use Zig 0.13+
2. `zig build test -Dcpu=baseline`
3. Prefer small commits with conventional messages (`feat:`, `fix:`, `docs:`)
4. Skills must not open Redis — use the bus client only via Bedd host
5. Update `docs/SKILL_ABI.md` if you change WASM imports/exports
