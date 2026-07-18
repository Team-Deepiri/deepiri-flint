const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const common = @import("../common.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "structured_compact";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const doc_id = common.extractDocumentId(input_json) orelse "unknown";
    const schema = jsonx.getStringField(input_json, "schemaId") orelse
        jsonx.getStringField(input_json, "schema_id") orelse
        "generic.document";

    // Compact: keep envelope small — drop raw text if present by not re-embedding full blob when huge.
    const compact_input = if (input_json.len > 32_000) input_json[0..32_000] else input_json;

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("documentId", doc_id) catch return skill.SkillError.OutOfMemory;
    o.putString("schemaId", schema) catch return skill.SkillError.OutOfMemory;
    o.putBool("truncated", input_json.len > 32_000) catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putRaw("structured", compact_input) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = out };
}
