const std = @import("std");
const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "schema_gate";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const schema = jsonx.getStringField(input_json, "schemaVersion") orelse
        jsonx.getStringField(input_json, "schema_version") orelse
        "unknown";
    const passed = !std.mem.eql(u8, schema, "unknown");

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("schemaVersion", schema) catch return skill.SkillError.OutOfMemory;
    o.putBool("gate_passed", passed) catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putString("entry_id", ctx.entry_id) catch return skill.SkillError.OutOfMemory;
    o.putRaw("input", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{
        .payload_json = out,
        .event_type_override = if (passed)
            ctx.allocator.dupe(u8, "flint.schema.passed") catch null
        else
            ctx.allocator.dupe(u8, "flint.schema.rejected") catch null,
    };
}
