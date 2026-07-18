const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const ember = @import("ember.zig");
const jsonx = @import("jsonx.zig");
const skill = @import("skill/mod.zig");
const tinder = @import("tinder.zig");
const publish_retry = @import("publish_retry.zig");

pub fn dryRun(
    allocator: std.mem.Allocator,
    cfg: config.Config,
    stream: []const u8,
    event_type: []const u8,
    skill_name: []const u8,
) !void {
    var reg = skill.Registry.init(allocator, cfg.skills_dir);
    defer reg.deinit();

    const input =
        \\{"bedd":"strike","status":"dry-run"}
    ;
    const ctx = skill.SkillContext{
        .allocator = allocator,
        .stream = stream,
        .entry_id = "dry-run",
        .event_type = event_type,
    };
    const result = try reg.run(skill_name, ctx, input);
    defer result.deinit(allocator);

    const wrapped = try jsonx.wrapStrikeResult(allocator, skill_name, stream, "dry-run", result.payload_json);
    defer allocator.free(wrapped);

    const body = try bus.encodePublishBody(allocator, .{
        .stream = "inference-events",
        .event_type = "bedd.strike.result",
        .sender = cfg.sender,
        .payload_json = wrapped,
    });
    defer allocator.free(body);

    const out = std.io.getStdOut().writer();
    try out.print("bedd strike (dry-run)\n", .{});
    try out.print("  stream:     {s}\n", .{stream});
    try out.print("  event_type: {s}\n", .{event_type});
    try out.print("  skill:      {s}\n", .{skill_name});
    try out.print("  sidecar:    {s}\n", .{cfg.bus_url});
    try out.print("  result:     {s}\n", .{result.payload_json});
    try out.print("  would POST {s}/v1/publish\n", .{cfg.bus_url});
    try out.print("  body:       {s}\n", .{body});
}

pub fn executeOne(
    allocator: std.mem.Allocator,
    cfg: *const config.Config,
    client: *bus.Client,
    registry: *skill.Registry,
    metrics: *ember.Ember,
    breaker: *publish_retry.CircuitBreaker,
    route: tinder.Route,
    event: bus.StreamEvent,
) !void {
    const started_ns = std.time.nanoTimestamp();
    const ctx = skill.SkillContext{
        .allocator = allocator,
        .stream = event.stream,
        .entry_id = event.entry_id,
        .event_type = event.event_type,
    };

    const result = registry.run(route.skill, ctx, event.payload_json) catch |err| {
        metrics.record(event.stream, route.skill, false, 0);
        std.log.err("skill {s} failed on {s}/{s}: {s}", .{
            route.skill,
            event.stream,
            event.entry_id,
            @errorName(err),
        });
        return err;
    };
    defer result.deinit(allocator);

    const wrapped = try jsonx.wrapStrikeResult(
        allocator,
        route.skill,
        event.stream,
        event.entry_id,
        result.payload_json,
    );
    defer allocator.free(wrapped);

    const pub_event = result.event_type_override orelse route.publish_event_type;

    if (cfg.dry_run) {
        std.log.info("dry-run publish stream={s} event={s} payload_len={d}", .{
            route.publish_stream,
            pub_event,
            wrapped.len,
        });
    } else {
        const pub_res = try publish_retry.publishWithRetry(client, .{
            .stream = route.publish_stream,
            .event_type = pub_event,
            .sender = cfg.sender,
            .payload_json = wrapped,
        }, breaker, 4);
        defer pub_res.deinit(allocator);
        metrics.publishes += 1;
        std.log.info("published entry_id={s} stream={s}", .{ pub_res.entry_id, route.publish_stream });
    }

    const elapsed = std.time.nanoTimestamp() - started_ns;
    const ms: u64 = if (elapsed > 0) @intCast(@divTrunc(elapsed, std.time.ns_per_ms)) else 0;
    metrics.record(event.stream, route.skill, true, ms);
}
