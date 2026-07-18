const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const common = @import("../common.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "artifact_claim";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const doc_id = common.extractDocumentId(input_json) orelse "unknown";
    const artifact_type = jsonx.getStringField(input_json, "artifactType") orelse
        jsonx.getStringField(input_json, "artifact_type") orelse
        "document.extraction";
    const claim_id = try common.fingerprintOf(ctx.allocator, input_json);
    defer ctx.allocator.free(claim_id);

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("documentId", doc_id) catch return skill.SkillError.OutOfMemory;
    o.putString("artifactType", artifact_type) catch return skill.SkillError.OutOfMemory;
    o.putString("claimId", claim_id) catch return skill.SkillError.OutOfMemory;
    o.putString("status", "claimed") catch return skill.SkillError.OutOfMemory;
    o.putString("worker", "flint") catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putString("entry_id", ctx.entry_id) catch return skill.SkillError.OutOfMemory;
    o.putRaw("artifact", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{
        .payload_json = out,
        .event_type_override = ctx.allocator.dupe(u8, "flint.artifact.claimed") catch null,
    };
}
