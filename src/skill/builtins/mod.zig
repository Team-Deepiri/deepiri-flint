pub const redact = @import("redact.zig");
pub const fingerprint = @import("fingerprint.zig");
pub const schema_gate = @import("schema_gate.zig");
pub const training_enrich = @import("training_enrich.zig");
pub const splice_tag = @import("splice_tag.zig");
pub const invalidation_ack = @import("invalidation_ack.zig");
pub const model_reload_hook = @import("model_reload_hook.zig");
pub const inference_annotate = @import("inference_annotate.zig");
pub const agi_decision_wrap = @import("agi_decision_wrap.zig");
pub const metrics_sample = @import("metrics_sample.zig");
pub const vectorize_normalize = @import("vectorize_normalize.zig");
pub const structured_compact = @import("structured_compact.zig");
pub const artifact_claim = @import("artifact_claim.zig");
pub const helox_raw_tag = @import("helox_raw_tag.zig");
pub const helox_structured_tag = @import("helox_structured_tag.zig");

pub const all_names = [_][]const u8{
    redact.skill_name,
    fingerprint.skill_name,
    schema_gate.skill_name,
    training_enrich.skill_name,
    splice_tag.skill_name,
    invalidation_ack.skill_name,
    model_reload_hook.skill_name,
    inference_annotate.skill_name,
    agi_decision_wrap.skill_name,
    metrics_sample.skill_name,
    vectorize_normalize.skill_name,
    structured_compact.skill_name,
    artifact_claim.skill_name,
    helox_raw_tag.skill_name,
    helox_structured_tag.skill_name,
};
