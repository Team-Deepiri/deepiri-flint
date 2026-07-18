const topics = @import("topics.zig");

pub const Desc = struct { name: []const u8, purpose: []const u8 };

pub const catalog = [_]Desc{
    .{ .name = topics.DOCUMENT_ARTIFACTS, .purpose = "LIS artifact materialization" },
    .{ .name = topics.DOCUMENT_VECTORIZE, .purpose = "embedding / chunk fanout" },
    .{ .name = topics.DOCUMENT_TRAINING, .purpose = "training pair emission" },
    .{ .name = topics.DOCUMENT_STRUCTURED, .purpose = "structured extraction" },
    .{ .name = topics.INFERENCE_EVENTS, .purpose = "inference plane" },
    .{ .name = topics.PIPELINE_DEAD_LETTER, .purpose = "failed strike DLQ" },
    .{ .name = topics.PIPELINE_METRICS, .purpose = "pipeline metrics" },
    .{ .name = topics.MODEL_EVENTS, .purpose = "model lifecycle" },
};
