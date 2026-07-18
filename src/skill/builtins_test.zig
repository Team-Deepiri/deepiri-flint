const std = @import("std");
const eval = @import("../eval.zig");
const skill = @import("../skill/mod.zig");
const common = @import("../skill/common.zig");

test "all builtins run without error" {
    const names = [_][]const u8{
        "echo",               "passthrough",         "pressure_tag",
        "document_fanout",    "redact",              "fingerprint",
        "schema_gate",        "training_enrich",     "splice_tag",
        "invalidation_ack",   "model_reload_hook",   "inference_annotate",
        "agi_decision_wrap",  "metrics_sample",      "vectorize_normalize",
        "structured_compact", "artifact_claim",      "helox_raw_tag",
        "helox_structured_tag",
    };
    const input =
        \\{"documentId":"d1","schemaVersion":"v1","token":"secret","category":"x","quality_score":"0.9"}
    ;
    for (names) |name| {
        const out = try eval.evalSkill(std.testing.allocator, ".", name, input, "t", "e");
        defer std.testing.allocator.free(out);
        try std.testing.expect(out.len > 10);
    }
}

test "redact removes secret token value" {
    const redacted = try common.redactSecrets(std.testing.allocator, "{\"token\":\"abc\"}");
    defer std.testing.allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "abc") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "***") != null);
}
