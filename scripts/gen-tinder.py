#!/usr/bin/env python3
"""Generate a minimal tinder JSON (opaque stream names)."""
import json

ROUTES = [
    ("inbox", "echo", "outbox"),
    ("inbox", "redact", "outbox"),
    ("inbox", "fingerprint", "outbox"),
]

def main():
    routes = [
        {
            "stream": stream,
            "event_type": "*",
            "skill": skill,
            "publish_stream": pub,
            "publish_event_type": f"bedd.{skill}.result",
        }
        for stream, skill, pub in ROUTES
    ]
    print(json.dumps({"routes": routes}, indent=2))

if __name__ == "__main__":
    main()
