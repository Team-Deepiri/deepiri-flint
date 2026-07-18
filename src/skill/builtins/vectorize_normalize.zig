const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const common = @import("../common.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "vectorize_normalize";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const doc_id = common.extractDocumentId(input_json) orelse "unknown";
    const model = jsonx.getStringField(input_json, "embeddingModel") orelse
        jsonx.getStringField(input_json, "embedding_model") orelse
        "default";

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("documentId", doc_id) catch return skill.SkillError.OutOfMemory;
    o.putString("embeddingModel", model) catch return skill.SkillError.OutOfMemory;
    o.putString("normalized", "true") catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putRaw("vectorize", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{
        .payload_json = out,
        .event_type_override = ctx.allocator.dupe(u8, "flint.vectorize.normalized") catch null,
    };
}
