const skill = @import("../mod.zig");
const common = @import("../common.zig");

pub const skill_name = "redact";

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const redacted = common.redactSecrets(ctx.allocator, input_json) catch return skill.SkillError.OutOfMemory;
    defer ctx.allocator.free(redacted);
    return common.wrapSkill(ctx, skill_name, "redacted", redacted, input_json);
}
