const std = @import("std");
const skill = @import("skill/mod.zig");
const jsonx = @import("jsonx.zig");

/// Run a skill against a JSON payload without touching the bus.
pub fn evalSkill(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    input_json: []const u8,
    stream: []const u8,
    event_type: []const u8,
) ![]u8 {
    var reg = skill.Registry.init(allocator, skills_dir);
    defer reg.deinit();

    const ctx = skill.SkillContext{
        .allocator = allocator,
        .stream = stream,
        .entry_id = "eval",
        .event_type = event_type,
    };
    const result = try reg.run(skill_name, ctx, input_json);
    defer result.deinit(allocator);

    return try jsonx.wrapStrikeResult(allocator, skill_name, stream, "eval", result.payload_json);
}

pub fn evalFromArgs(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    input_arg: []const u8,
) !void {
    var input_owned: ?[]u8 = null;
    defer if (input_owned) |p| allocator.free(p);

    const input_json: []const u8 = blk: {
        if (std.mem.startsWith(u8, input_arg, "@")) {
            const path = input_arg[1..];
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            input_owned = try file.readToEndAlloc(allocator, 4 * 1024 * 1024);
            break :blk input_owned.?;
        }
        break :blk input_arg;
    };

    const out = try evalSkill(
        allocator,
        skills_dir,
        skill_name,
        input_json,
        "eval",
        "bedd.eval",
    );
    defer allocator.free(out);
    try std.io.getStdOut().writer().print("{s}\n", .{out});
}

test "evalSkill echo" {
    const out = try evalSkill(
        std.testing.allocator,
        ".",
        "echo",
        "{\"hello\":true}",
        "eval",
        "bedd.eval",
    );
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"echo\":true") != null);
}
