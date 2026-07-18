# Integration

`bedd demo` runs an in-process mock bus (no external deps).

Against a live HTTP bus:

```bash
export BEDD_BUS_URL=http://127.0.0.1:8081
export BEDD_TINDER=tinder.example.json
./zig-out/bin/bedd serve
```

Publish an `inbox` event and watch `/metrics` on `BEDD_ADMIN_PORT`.
