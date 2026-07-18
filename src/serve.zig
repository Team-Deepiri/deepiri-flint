const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const ember_mod = @import("ember.zig");
const skill = @import("skill/mod.zig");
const strike = @import("strike.zig");
const tinder_mod = @import("tinder.zig");
const shutdown = @import("shutdown.zig");
const admin = @import("admin/server.zig");
const bus_dlq = @import("bus_dlq.zig");
const util_log = @import("util/log.zig");
const retry = @import("retry.zig");
const publish_retry = @import("publish_retry.zig");
const fsutil = @import("util/fsutil.zig");

pub fn run(allocator: std.mem.Allocator, cfg: *config.Config) !void {
    shutdown.installSignals();
    util_log.setLevelFromEnv();

    var tinder = try tinder_mod.loadOrDefault(allocator, cfg.tinder_path);
    defer tinder.deinit();

    var registry = skill.Registry.init(allocator, cfg.skills_dir);
    defer registry.deinit();

    var metrics = ember_mod.Ember{};
    var breaker = publish_retry.CircuitBreaker{};
    var client = bus.Client.init(allocator, cfg.*);
    defer client.deinit();

    var admin_server = admin.Server{
        .allocator = allocator,
        .cfg = cfg,
        .metrics = &metrics,
        .bus_client = &client,
        .port = cfg.admin_port,
    };
    admin_server.start() catch |err| {
        std.log.warn("admin server failed to start: {s}", .{@errorName(err)});
    };
    defer admin_server.shutdown();

    var streams = try tinder.uniqueStreams(allocator);
    defer allocator.free(streams);

    var last_mtime: i128 = 0;
    if (cfg.tinder_path) |path| {
        last_mtime = fileMtime(path);
    }

    const out = std.io.getStdOut().writer();
    try out.print("bedd serve\n", .{});
    try out.print("  version: {s}\n", .{config.version});
    try out.print("  sidecar: {s}\n", .{cfg.bus_url});
    try out.print("  group:   {s}\n", .{cfg.consumer_group});
    try out.print("  name:    {s}\n", .{cfg.consumer_name});
    try out.print("  admin:   :{d}\n", .{cfg.admin_port});
    try out.print("  dry_run: {}\n", .{cfg.dry_run});
    try printStreams(out, streams);
    try out.writeAll("  skills:\n");
    try skill.Registry.listBuiltins(out);

    var consecutive_failures: u32 = 0;
    while (!shutdown.shouldStop()) {
        // SIGHUP or tinder file mtime change → reload
        var should_reload = shutdown.takeReload();
        if (cfg.tinder_path) |path| {
            const mt = fileMtime(path);
            if (mt != 0 and mt != last_mtime) {
                last_mtime = mt;
                should_reload = true;
            }
        }
        if (should_reload) {
            std.log.info("reloading tinder", .{});
            if (cfg.tinder_path) |path| {
                const next = tinder_mod.loadFromFile(allocator, path) catch |err| {
                    std.log.err("tinder reload failed: {s}", .{@errorName(err)});
                    continue;
                };
                tinder.deinit();
                tinder = next;
                allocator.free(streams);
                streams = try tinder.uniqueStreams(allocator);
                try printStreams(out, streams);
            }
        }

        var progressed = false;
        for (streams) |stream| {
            if (shutdown.shouldStop()) break;

            const events = client.read(.{
                .stream = stream,
                .consumer_group = cfg.consumer_group,
                .consumer_name = cfg.consumer_name,
                .count = cfg.read_count,
                .block_ms = cfg.block_ms,
            }) catch |err| {
                consecutive_failures += 1;
                std.log.warn("read {s} failed: {s} (failures={d})", .{
                    stream,
                    @errorName(err),
                    consecutive_failures,
                });
                retry.sleepAttempt(@min(consecutive_failures, 8));
                continue;
            };
            defer {
                for (events) |e| e.deinit(allocator);
                allocator.free(events);
            }

            consecutive_failures = 0;
            metrics.reads += 1;

            if (events.len == 0) continue;
            progressed = true;

            var ack_ids = std.ArrayList([]const u8).init(allocator);
            defer ack_ids.deinit();

            for (events) |event| {
                if (shutdown.shouldStop()) break;

                const route = tinder.match(event.stream, event.event_type) orelse {
                    std.log.warn("no route for {s} event={s}; acking", .{ event.stream, event.event_type });
                    try ack_ids.append(event.entry_id);
                    continue;
                };

                strike.executeOne(allocator, cfg, &client, &registry, &metrics, &breaker, route, event) catch |err| {
                    std.log.err("strike failed skill={s} stream={s} entry={s}: {s}", .{
                        route.skill,
                        event.stream,
                        event.entry_id,
                        @errorName(err),
                    });
                    if (!cfg.dry_run) {
                        bus_dlq.publishDeadLetter(
                            &client,
                            cfg.sender,
                            cfg.dlq_stream,
                            event.stream,
                            event.entry_id,
                            @errorName(err),
                            event.payload_json,
                        ) catch {};
                    }
                    continue;
                };
                try ack_ids.append(event.entry_id);
            }

            if (ack_ids.items.len > 0 and !cfg.dry_run) {
                const n = client.ack(stream, cfg.consumer_group, ack_ids.items) catch |err| {
                    std.log.err("ack failed: {s}", .{@errorName(err)});
                    continue;
                };
                metrics.acks += @intCast(n);
            } else if (ack_ids.items.len > 0 and cfg.dry_run) {
                metrics.acks += @intCast(ack_ids.items.len);
            }
        }

        if (!progressed) {
            std.time.sleep(50 * std.time.ns_per_ms);
        }

        if (metrics.reads > 0 and metrics.reads % 50 == 0) {
            try metrics.print(std.io.getStdErr().writer());
        }
    }

    std.log.info("bedd serve shutting down cleanly", .{});
    try metrics.print(out);
    _ = fsutil;
}

fn fileMtime(path: []const u8) i128 {
    const file = std.fs.cwd().openFile(path, .{}) catch return 0;
    defer file.close();
    const st = file.stat() catch return 0;
    return st.mtime;
}

fn printStreams(out: anytype, streams: []const []const u8) !void {
    try out.print("  streams: {d}\n", .{streams.len});
    for (streams) |s| try out.print("    - {s}\n", .{s});
}
