const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const jsonx = @import("../../jsonx.zig");
const common = @import("../common.zig");

pub const skill_name = "agi_decision_wrap";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const decision = jsonx.getStringField(input_json, "decision") orelse
        jsonx.getStringField(input_json, "action") orelse
        "unknown";
    const fp = try common.fingerprintOf(ctx.allocator, input_json);
    defer ctx.allocator.free(fp);

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("decision", decision) catch return skill.SkillError.OutOfMemory;
    o.putString("audit_fingerprint", fp) catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putString("entry_id", ctx.entry_id) catch return skill.SkillError.OutOfMemory;
    o.putRaw("agi", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = out };
}
