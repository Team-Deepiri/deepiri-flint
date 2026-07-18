const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const serve = @import("serve.zig");
const skill = @import("skill/mod.zig");
const strike = @import("strike.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    const command = args.next() orelse "help";

    if (eql(command, "help") or eql(command, "--help") or eql(command, "-h")) {
        try printHelp();
        return;
    }
    if (eql(command, "version")) {
        try std.io.getStdOut().writer().print("deepiri-flint {s}\n", .{config.version});
        return;
    }
    if (eql(command, "skills")) {
        try std.io.getStdOut().writer().writeAll("built-in skills:\n");
        try skill.Registry.listBuiltins(std.io.getStdOut().writer());
        try std.io.getStdOut().writer().writeAll("wasm skills: load *.wasm from FLINT_SKILLS_DIR (flint_skill_v1)\n");
        return;
    }

    var cfg = try config.loadFromEnv(allocator);
    defer cfg.deinit();

    if (eql(command, "doctor")) {
        try bus.doctor(allocator, cfg);
        return;
    }
    if (eql(command, "strike")) {
        const stream = args.next() orelse "document.artifacts";
        const event_type = args.next() orelse "document.artifacts.route";
        const skill_name = args.next() orelse "echo";
        try strike.dryRun(allocator, cfg, stream, event_type, skill_name);
        return;
    }
    if (eql(command, "serve")) {
        try serve.run(allocator, &cfg);
        return;
    }

    try std.io.getStdErr().writer().print("flint: unknown command '{s}'\n", .{command});
    try printHelp();
    std.process.exit(1);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn printHelp() !void {
    try std.io.getStdOut().writer().writeAll(
        \\deepiri-flint — stream-native AI worker runtime (Zig)
        \\
        \\Usage:
        \\  flint help
        \\  flint version
        \\  flint doctor
        \\  flint skills
        \\  flint strike [stream] [event_type] [skill]
        \\  flint serve
        \\
        \\Env:
        \\  FLINT_SUGAR_GLIDER_URL   Sugar Glider base URL (default http://127.0.0.1:8081)
        \\  FLINT_SENDER             publish sender (default flint)
        \\  FLINT_CONSUMER_GROUP     XREADGROUP group (default flint-workers)
        \\  FLINT_CONSUMER_NAME      consumer name (default flint-1)
        \\  FLINT_TINDER             path to tinder JSON route file
        \\  FLINT_SKILLS_DIR         WASM skill directory (default zig-out/skills)
        \\  FLINT_DRY_RUN            if true/1, skip publish/ack side effects
        \\  FLINT_BLOCK_MS           XREADGROUP block (default 2000)
        \\  FLINT_READ_COUNT         max entries per read (default 10)
        \\  FLINT_ADMIN_PORT         health/metrics port (default 9108)
        \\  FLINT_LOG_LEVEL          debug|info|warn|error
        \\
    );
}
