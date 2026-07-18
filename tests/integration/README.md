# Integration tests

Require a live Sugar Glider:

```bash
FLINT_SUGAR_GLIDER_URL=http://127.0.0.1:8081 FLINT_DRY_RUN=0 ./zig-out/bin/flint serve
```

Publish a `document.artifacts` event and watch `/metrics`.
