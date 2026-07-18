#!/usr/bin/env python3
"""Generate a full-mesh tinder JSON from ModelKit-ish topic list."""
import json, sys
topics = [
    ("document.artifacts", "artifact_claim", "inference-events"),
    ("document.vectorize", "vectorize_normalize", "inference-events"),
    ("document.structured", "structured_compact", "inference-events"),
    ("document.training", "training_enrich", "pipeline.helox-training.structured"),
    ("pipeline.pressure.events", "pressure_tag", "pipeline.metrics"),
    ("pipeline.splice.events", "splice_tag", "pipeline.metrics"),
    ("model-events", "model_reload_hook", "platform-events"),
    ("agi-decisions", "agi_decision_wrap", "platform-events"),
]
routes = [
    {
        "stream": s,
        "event_type": "*",
        "skill": skill,
        "publish_stream": pub,
        "publish_event_type": f"flint.{skill}",
    }
    for s, skill, pub in topics
]
json.dump({"routes": routes}, sys.stdout, indent=2)
print()
