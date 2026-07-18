const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "invalidation_ack";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const artifact = jsonx.getStringField(input_json, "artifactId") orelse
        jsonx.getStringField(input_json, "artifact_id") orelse
        "unknown";

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("artifactId", artifact) catch return skill.SkillError.OutOfMemory;
    o.putString("status", "acked") catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putString("entry_id", ctx.entry_id) catch return skill.SkillError.OutOfMemory;
    o.putRaw("invalidation", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = out };
}
