const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const serve = @import("serve.zig");
const skill = @import("skill/mod.zig");
const strike = @import("strike.zig");
const eval = @import("eval.zig");
const shutdown = @import("shutdown.zig");
const tinder_validate = @import("tinder_validate.zig");
const bus_mock = @import("bus_mock.zig");

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
        try std.io.getStdOut().writer().print("deepiri-bedd {s}\n", .{config.version});
        return;
    }
    if (eql(command, "skills")) {
        try std.io.getStdOut().writer().writeAll("built-in skills:\n");
        try skill.Registry.listBuiltins(std.io.getStdOut().writer());
        try std.io.getStdOut().writer().writeAll("wasm skills: load *.wasm from BEDD_SKILLS_DIR (bedd_skill_v1)\n");
        return;
    }

    var cfg = try config.loadFromEnv(allocator);
    defer cfg.deinit();

    if (eql(command, "doctor")) {
        try bus.doctor(allocator, cfg);
        return;
    }
    if (eql(command, "strike")) {
        const stream = args.next() orelse "inbox";
        const event_type = args.next() orelse "demo.event";
        const skill_name = args.next() orelse "echo";
        try strike.dryRun(allocator, cfg, stream, event_type, skill_name);
        return;
    }
    if (eql(command, "eval")) {
        const skill_name = args.next() orelse {
            try std.io.getStdErr().writer().writeAll("usage: bedd eval <skill> '<json>'|@file.json\n");
            std.process.exit(2);
        };
        const input = args.next() orelse "{}";
        try eval.evalFromArgs(allocator, cfg.skills_dir, skill_name, input);
        return;
    }
    if (eql(command, "tinder")) {
        const sub = args.next() orelse "validate";
        if (!eql(sub, "validate")) {
            try std.io.getStdErr().writer().writeAll("usage: bedd tinder validate [path]\n");
            std.process.exit(2);
        }
        const path = args.next() orelse cfg.tinder_path orelse "tinder.example.json";
        const code = try tinder_validate.printValidation(allocator, path);
        std.process.exit(code);
    }
    if (eql(command, "demo")) {
        try runDemo(allocator, &cfg);
        return;
    }
    if (eql(command, "serve")) {
        try serve.run(allocator, &cfg);
        return;
    }
    if (eql(command, "stop-check")) {
        shutdown.installSignals();
        try std.io.getStdOut().writer().writeAll("signals installed\n");
        return;
    }

    try std.io.getStdErr().writer().print("bedd: unknown command '{s}'\n", .{command});
    try printHelp();
    std.process.exit(1);
}

fn runDemo(allocator: std.mem.Allocator, cfg: *config.Config) !void {
    const out = std.io.getStdOut().writer();
    try out.writeAll("bedd demo — mock bus + redact strike\n");

    var mock = bus_mock.MockSidecar.init(allocator, 19128);
    try mock.start();
    defer mock.deinit();

    try mock.seed(
        "inbox",
        "demo.event",
        \\{"id":"demo-1","token":"should-redact"}
    ,
    );

    allocator.free(cfg.bus_url);
    cfg.bus_url = try allocator.dupe(u8, "http://127.0.0.1:19128");
    cfg.dry_run = false;

    var client = bus.Client.init(allocator, cfg.*);
    defer client.deinit();
    try out.print("  mock health: {}\n", .{try client.health()});

    const events = try client.read(.{
        .stream = "inbox",
        .consumer_group = "bedd-demo",
        .consumer_name = "demo-1",
        .count = 5,
        .block_ms = 200,
    });
    defer {
        for (events) |e| e.deinit(allocator);
        allocator.free(events);
    }
    try out.print("  read events: {d}\n", .{events.len});
    if (events.len == 0) {
        try out.writeAll("  no events — demo failed\n");
        std.process.exit(1);
    }

    try eval.evalFromArgs(allocator, cfg.skills_dir, "redact", events[0].payload_json);
    try eval.evalFromArgs(allocator, cfg.skills_dir, "fingerprint", events[0].payload_json);

    const pub_res = try client.publish(.{
        .stream = "outbox",
        .event_type = "bedd.demo.result",
        .sender = cfg.sender,
        .payload_json = "{\"demo\":true}",
    });
    defer pub_res.deinit(allocator);
    try out.print("  published: {s}\n", .{pub_res.entry_id});

    _ = try client.ack("inbox", "bedd-demo", &.{events[0].entry_id});
    try out.print("  mock published={d} acked={d}\n", .{ mock.published, mock.acked });
    try out.writeAll("demo ok\n");
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn printHelp() !void {
    try std.io.getStdOut().writer().writeAll(
        \\deepiri-bedd — portable stream skill runtime (Zig)
        \\
        \\Usage:
        \\  bedd help
        \\  bedd version
        \\  bedd doctor
        \\  bedd skills
        \\  bedd eval <skill> '<json>'|@file.json
        \\  bedd tinder validate [path]
        \\  bedd strike [stream] [event_type] [skill]
        \\  bedd demo
        \\  bedd serve
        \\
        \\Env:
        \\  BEDD_BUS_URL            HTTP bus base URL (default http://127.0.0.1:8081)
        \\  BEDD_SENDER             publish sender (default bedd)
        \\  BEDD_CONSUMER_GROUP     consumer group (default bedd-workers)
        \\  BEDD_CONSUMER_NAME      consumer name (default bedd-1)
        \\  BEDD_TINDER             path to route JSON file
        \\  BEDD_SKILLS_DIR         WASM skill directory (default zig-out/skills)
        \\  BEDD_DLQ_STREAM         dead-letter stream (default dead-letter)
        \\  BEDD_DRY_RUN            if true/1, skip publish/ack side effects
        \\  BEDD_BLOCK_MS           read block ms (default 2000)
        \\  BEDD_READ_COUNT         max entries per read (default 10)
        \\  BEDD_ADMIN_PORT         health/metrics port (default 9108)
        \\  BEDD_LOG_LEVEL          debug|info|warn|error
        \\
        \\Signals (serve):
        \\  SIGTERM / SIGINT  graceful stop
        \\  SIGHUP            reload tinder routes
        \\  (also reloads when tinder file mtime changes)
        \\
    );
}
