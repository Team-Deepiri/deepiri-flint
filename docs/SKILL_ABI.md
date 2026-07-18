# Skill ABI — bedd_skill_v1

Skills never talk to Redis or a product bus directly. Bedd owns the HTTP bus client.

WASM modules export `bedd_abi_version` and `bedd_on_event`, and may import host helpers from module `"bedd"`.

Native builtins in this repo: `echo`, `passthrough`, `redact`, `fingerprint`, `schema_gate`.
