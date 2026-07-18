const std = @import("std");
const bus = @import("bus.zig");
const bus_mock = @import("bus_mock.zig");
const config = @import("config.zig");
const skill = @import("skill/mod.zig");
const strike = @import("strike.zig");
const ember = @import("ember.zig");
const tinder = @import("tinder.zig");
const publish_retry = @import("publish_retry.zig");

pub const BenchReport = struct {
    iterations: u64,
    skills: []const []const u8,
    ok: u64,
    err: u64,
    latency_ms: []u64,
    total_wall_ms: u64,
    publishes: u64,
    acks: u64,

    pub fn deinit(self: *BenchReport, allocator: std.mem.Allocator) void {
        allocator.free(self.latency_ms);
    }

    pub fn percentile(self: *const BenchReport, allocator: std.mem.Allocator, pct: f64) !u64 {
        if (self.latency_ms.len == 0) return 0;
        const sorted = try allocator.dupe(u64, self.latency_ms);
        defer allocator.free(sorted);
        std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
        const idx = @min(sorted.len - 1, @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(sorted.len - 1)) * pct))));
        return sorted[idx];
    }

    pub fn meanMs(self: *const BenchReport) f64 {
        if (self.latency_ms.len == 0) return 0;
        var sum: u64 = 0;
        for (self.latency_ms) |v| sum += v;
        return @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(self.latency_ms.len));
    }

    pub fn throughputPerSec(self: *const BenchReport) f64 {
        if (self.total_wall_ms == 0) return 0;
        return (@as(f64, @floatFromInt(self.ok)) * 1000.0) / @as(f64, @floatFromInt(self.total_wall_ms));
    }
};

/// End-to-end bench against in-process mock bus: seed → read → strike → publish → ack.
pub fn runMockBench(
    allocator: std.mem.Allocator,
    iterations: u32,
    skill_names: []const []const u8,
) !BenchReport {
    var mock = bus_mock.MockSidecar.init(allocator, 19138);
    try mock.start();
    defer mock.deinit();
    std.time.sleep(40 * std.time.ns_per_ms);

    var cfg = try config.loadFromEnv(allocator);
    defer cfg.deinit();
    allocator.free(cfg.bus_url);
    cfg.bus_url = try allocator.dupe(u8, "http://127.0.0.1:19138");
    cfg.dry_run = false;

    var client = bus.Client.init(allocator, cfg);
    defer client.deinit();

    var reg = skill.Registry.init(allocator, cfg.skills_dir);
    defer reg.deinit();
    var metrics = ember.Ember{};
    var breaker = publish_retry.CircuitBreaker{};
    var latencies = try allocator.alloc(u64, iterations);
    @memset(latencies, 0);

    var ok: u64 = 0;
    var err: u64 = 0;
    const wall_start = std.time.milliTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const skill_name = skill_names[i % skill_names.len];
        const payload = try std.fmt.allocPrint(
            allocator,
            \\{{"id":"bench-{d}","token":"secret-{d}","n":{d}}}
        ,
            .{ i, i, i },
        );
        defer allocator.free(payload);

        try mock.seed("inbox", "bench.event", payload);

        const t0 = std.time.milliTimestamp();
        const events = client.read(.{
            .stream = "inbox",
            .consumer_group = "bedd-bench",
            .consumer_name = "bench-1",
            .count = 1,
            .block_ms = 200,
        }) catch {
            err += 1;
            continue;
        };
        defer {
            for (events) |e| e.deinit(allocator);
            allocator.free(events);
        }
        if (events.len == 0) {
            err += 1;
            continue;
        }

        const route = tinder.Route{
            .stream = "inbox",
            .event_type = "*",
            .skill = skill_name,
            .publish_stream = "outbox",
            .publish_event_type = "bedd.bench.result",
            .exchange_kind = .direct,
            .headers = "",
            .recovery_skill = "",
            .confirm = true,
        };

        strike.executeOne(allocator, &cfg, &client, &reg, &metrics, &breaker, route, events[0]) catch {
            err += 1;
            continue;
        };
        _ = client.ack("inbox", "bedd-bench", &.{events[0].entry_id}) catch {};
        const t1 = std.time.milliTimestamp();
        latencies[i] = @intCast(@max(@as(i64, 0), t1 - t0));
        ok += 1;
    }

    const wall_end = std.time.milliTimestamp();
    return .{
        .iterations = iterations,
        .skills = skill_names,
        .ok = ok,
        .err = err,
        .latency_ms = latencies,
        .total_wall_ms = @intCast(@max(@as(i64, 0), wall_end - wall_start)),
        .publishes = metrics.publishes,
        .acks = mock.acked,
    };
}

pub fn printReport(allocator: std.mem.Allocator, report: *BenchReport, json: bool) !void {
    const p50 = try report.percentile(allocator, 0.50);
    const p95 = try report.percentile(allocator, 0.95);
    const p99 = try report.percentile(allocator, 0.99);
    const mean = report.meanMs();
    const tput = report.throughputPerSec();
    const err_rate = if (report.iterations == 0) 0.0 else (@as(f64, @floatFromInt(report.err)) * 100.0) / @as(f64, @floatFromInt(report.iterations));

    const out = std.io.getStdOut().writer();
    if (json) {
        try out.print(
            \\{{"tool":"bedd","mode":"mock-bench","iterations":{d},"ok":{d},"err":{d},"error_rate_pct":{d:.3},"wall_ms":{d},"throughput_per_s":{d:.3},"latency_ms":{{"mean":{d:.3},"p50":{d},"p95":{d},"p99":{d}}},"publishes":{d},"acks":{d}}}
            \\
        ,
            .{
                report.iterations,
                report.ok,
                report.err,
                err_rate,
                report.total_wall_ms,
                tput,
                mean,
                p50,
                p95,
                p99,
                report.publishes,
                report.acks,
            },
        );
    } else {
        try out.writeAll("bedd bench (mock bus)\n");
        try out.print("  iterations:   {d}\n", .{report.iterations});
        try out.print("  ok / err:     {d} / {d} ({d:.2}% err)\n", .{ report.ok, report.err, err_rate });
        try out.print("  wall_ms:      {d}\n", .{report.total_wall_ms});
        try out.print("  throughput:   {d:.2}/s\n", .{tput});
        try out.print("  latency_ms:   mean={d:.2} p50={d} p95={d} p99={d}\n", .{ mean, p50, p95, p99 });
        try out.print("  publishes:    {d}\n", .{report.publishes});
        try out.print("  acks:         {d}\n", .{report.acks});
    }
}

test "bench runs at least one iteration" {
    const skills = [_][]const u8{"echo"};
    var report = try runMockBench(std.testing.allocator, 2, &skills);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok >= 1);
}

/// Skill-only microbench (no bus). Honest floor for filter/eval path.
pub fn runSkillBench(
    allocator: std.mem.Allocator,
    iterations: u32,
    skill_names: []const []const u8,
) !BenchReport {
    var reg = skill.Registry.init(allocator, "zig-out/skills");
    defer reg.deinit();

    var latencies = try allocator.alloc(u64, iterations);
    @memset(latencies, 0);
    var ok: u64 = 0;
    var err: u64 = 0;
    const wall_start = std.time.milliTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const skill_name = skill_names[i % skill_names.len];
        const payload = try std.fmt.allocPrint(
            allocator,
            \\{{"id":"bench-{d}","token":"secret-{d}","n":{d}}}
        ,
            .{ i, i, i },
        );
        defer allocator.free(payload);

        const ctx = skill.SkillContext{
            .allocator = allocator,
            .stream = "bench",
            .entry_id = "skill-bench",
            .event_type = "bench.event",
        };
        const t0 = std.time.milliTimestamp();
        const result = reg.run(skill_name, ctx, payload) catch {
            err += 1;
            continue;
        };
        result.deinit(allocator);
        latencies[i] = @intCast(std.time.milliTimestamp() - t0);
        ok += 1;
    }

    const wall = @as(u64, @intCast(std.time.milliTimestamp() - wall_start));
    return .{
        .iterations = iterations,
        .skills = skill_names,
        .ok = ok,
        .err = err,
        .latency_ms = latencies,
        .total_wall_ms = if (wall == 0) 1 else wall,
        .publishes = 0,
        .acks = 0,
    };
}

/// Direct Redis Streams bench — pipeline seed + batch read/ack/publish.
pub fn runRedisBench(
    allocator: std.mem.Allocator,
    iterations: u32,
    skill_names: []const []const u8,
    redis_url: []const u8,
) !BenchReport {
    var cfg = try config.loadFromEnv(allocator);
    defer cfg.deinit();
    allocator.free(cfg.bus_url);
    cfg.bus_url = try allocator.dupe(u8, redis_url);
    cfg.dry_run = false;
    cfg.lean = true;
    cfg.confirms = false;

    var client = bus.Client.init(allocator, cfg);
    defer client.deinit();
    if (client.redis == null) return error.Unexpected;

    const stream_buf = try std.fmt.allocPrint(allocator, "bedd-bench-inbox-{d}", .{std.time.milliTimestamp()});
    defer allocator.free(stream_buf);
    const stream = stream_buf;
    const group = "bedd-redis-bench";
    var cname_buf: [64]u8 = undefined;
    const cname = try std.fmt.bufPrint(&cname_buf, "bench-1", .{});

    if (client.redis) |*r| {
        r.ensureGroup(stream, group);
    }

    var reg = skill.Registry.init(allocator, cfg.skills_dir);
    defer reg.deinit();
    var latencies = try allocator.alloc(u64, iterations);
    @memset(latencies, 0);

    // Build payloads + pipeline XADD all in one RTT burst
    var payloads = try allocator.alloc([]u8, iterations);
    defer {
        for (payloads) |p| allocator.free(p);
        allocator.free(payloads);
    }
    var reqs = try allocator.alloc(bus.PublishRequest, iterations);
    defer allocator.free(reqs);

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        payloads[i] = try std.fmt.allocPrint(
            allocator,
            \\{{"id":"rbench-{d}","token":"secret-{d}","n":{d}}}
        ,
            .{ i, i, i },
        );
        reqs[i] = .{
            .stream = stream,
            .event_type = "bench.event",
            .sender = "bedd-bench",
            .payload_json = payloads[i],
        };
    }

    const wall_start = std.time.milliTimestamp();
    const seeded = try client.publishBatch(reqs);
    defer {
        for (seeded) |s| s.deinit(allocator);
        allocator.free(seeded);
    }

    const events = client.read(.{
        .stream = stream,
        .consumer_group = group,
        .consumer_name = cname,
        .count = @intCast(iterations),
        .block_ms = 2000,
    }) catch {
        return .{
            .iterations = iterations,
            .skills = skill_names,
            .ok = 0,
            .err = iterations,
            .latency_ms = latencies,
            .total_wall_ms = 1,
            .publishes = 0,
            .acks = 0,
        };
    };
    defer {
        for (events) |e| e.deinit(allocator);
        allocator.free(events);
    }

    var ok: u64 = 0;
    var err: u64 = 0;
    var ack_ids = std.ArrayList([]const u8).init(allocator);
    defer ack_ids.deinit();

    var out_reqs = std.ArrayList(bus.PublishRequest).init(allocator);
    defer {
        for (out_reqs.items) |r| allocator.free(r.payload_json);
        out_reqs.deinit();
    }

    for (events, 0..) |event, idx| {
        const t0 = std.time.milliTimestamp();
        const skill_name = skill_names[idx % skill_names.len];
        const route = tinder.Route{
            .stream = stream,
            .event_type = "bench.event",
            .skill = skill_name,
            .publish_stream = "bedd-bench-outbox",
            .publish_event_type = "bedd.bench.result",
            .exchange_kind = .direct,
            .headers = "",
            .recovery_skill = "",
            .confirm = false,
        };
        // Inline lean skill (avoid per-event confirm/wrap overhead in strike path)
        const ctx = skill.SkillContext{
            .allocator = allocator,
            .stream = event.stream,
            .entry_id = event.entry_id,
            .event_type = event.event_type,
        };
        const result = reg.run(skill_name, ctx, event.payload_json) catch {
            err += 1;
            continue;
        };
        defer result.deinit(allocator);

        const payload_copy = try allocator.dupe(u8, result.payload_json);
        try out_reqs.append(.{
            .stream = route.publish_stream,
            .event_type = route.publish_event_type,
            .sender = cfg.sender,
            .payload_json = payload_copy,
        });
        try ack_ids.append(event.entry_id);
        if (idx < latencies.len) latencies[idx] = @intCast(std.time.milliTimestamp() - t0);
        ok += 1;
    }

    if (out_reqs.items.len > 0) {
        const pubs = try client.publishBatch(out_reqs.items);
        for (pubs) |p| p.deinit(allocator);
        allocator.free(pubs);
    }
    if (ack_ids.items.len > 0) {
        _ = client.ack(stream, group, ack_ids.items) catch {};
    }

    const wall = @as(u64, @intCast(std.time.milliTimestamp() - wall_start));
    return .{
        .iterations = iterations,
        .skills = skill_names,
        .ok = ok,
        .err = err,
        .latency_ms = latencies,
        .total_wall_ms = if (wall == 0) 1 else wall,
        .publishes = ok,
        .acks = ok,
    };
}

