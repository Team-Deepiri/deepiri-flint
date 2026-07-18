const skill = @import("../mod.zig");
const common = @import("../common.zig");
const builder = @import("../../json/builder.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "training_enrich";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const doc_id = common.extractDocumentId(input_json) orelse "unknown";
    const category = jsonx.getStringField(input_json, "category") orelse "document_extraction";
    const quality = jsonx.getStringField(input_json, "quality_score") orelse "0";

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("documentId", doc_id) catch return skill.SkillError.OutOfMemory;
    o.putString("category", category) catch return skill.SkillError.OutOfMemory;
    o.putString("quality_score", quality) catch return skill.SkillError.OutOfMemory;
    o.putString("helox_ready", "true") catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putString("entry_id", ctx.entry_id) catch return skill.SkillError.OutOfMemory;
    o.putRaw("training", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{
        .payload_json = out,
        .event_type_override = ctx.allocator.dupe(u8, "flint.training.enriched") catch null,
    };
}
