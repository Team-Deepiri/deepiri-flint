const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "metrics_sample";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const name = jsonx.getStringField(input_json, "name") orelse
        jsonx.getStringField(input_json, "metric") orelse
        "unnamed";
    const value = jsonx.getStringField(input_json, "value") orelse "0";

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("metric", name) catch return skill.SkillError.OutOfMemory;
    o.putString("value", value) catch return skill.SkillError.OutOfMemory;
    o.putString("sampled_by", "flint") catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putRaw("sample", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = out };
}
