# On-call

| Symptom | Check |
|---------|--------|
| strikes_err rising | DLQ stream (`BEDD_DLQ_STREAM`), skill logs |
| bus unreachable | `BEDD_BUS_URL` `/readyz` |
| wasm load fail | `BEDD_SKILLS_DIR`, ABI `bedd_skill_v1` |
| route miss | `bedd tinder validate`, SIGHUP reload |
