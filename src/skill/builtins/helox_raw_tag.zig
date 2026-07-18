const skill = @import("../mod.zig");
const builder = @import("../../json/builder.zig");
const jsonx = @import("../../jsonx.zig");

pub const skill_name = "helox_raw_tag";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const sample_id = jsonx.getStringField(input_json, "sampleId") orelse
        jsonx.getStringField(input_json, "sample_id") orelse
        ctx.entry_id;

    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("sampleId", sample_id) catch return skill.SkillError.OutOfMemory;
    o.putString("stage", "raw") catch return skill.SkillError.OutOfMemory;
    o.putString("tagged_by", "flint") catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putRaw("sample", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = out };
}
