const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "model_reload_hook";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const model = jsonx.getStringField(input_json, "model") orelse
        jsonx.getStringField(input_json, "model_name") orelse
        jsonx.getStringField(input_json, "name") orelse
        "unknown";
    const action = jsonx.getStringField(input_json, "action") orelse
        jsonx.getStringField(input_json, "event") orelse
        "reload";

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("model", model) catch return skill.SkillError.OutOfMemory;
    o.putString("action", action) catch return skill.SkillError.OutOfMemory;
    o.putString("handled_by", "flint") catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putRaw("model_event", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{
        .payload_json = out,
        .event_type_override = ctx.allocator.dupe(u8, "flint.model.reload.seen") catch null,
    };
}
