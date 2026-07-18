const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const bus_mock = @import("bus_mock.zig");
const skill = @import("skill/mod.zig");
const strike = @import("strike.zig");
const ember = @import("ember.zig");
const tinder = @import("tinder.zig");
const publish_retry = @import("publish_retry.zig");

test "end-to-end strike against mock bus" {
    var mock = bus_mock.MockSidecar.init(std.testing.allocator, 19118);
    try mock.start();
    defer mock.deinit();
    std.time.sleep(50 * std.time.ns_per_ms);

    try mock.seed(
        "inbox",
        "demo.event",
        \\{"id":"doc-e2e","token":"secret"}
    ,
    );

    var cfg = try config.loadFromEnv(std.testing.allocator);
    defer cfg.deinit();
    std.testing.allocator.free(cfg.bus_url);
    cfg.bus_url = try std.testing.allocator.dupe(u8, "http://127.0.0.1:19118");
    cfg.dry_run = false;

    var client = bus.Client.init(std.testing.allocator, cfg);
    defer client.deinit();

    try std.testing.expect(try client.health());

    const events = try client.read(.{
        .stream = "inbox",
        .consumer_group = "bedd-test",
        .consumer_name = "t1",
        .count = 10,
        .block_ms = 100,
    });
    defer {
        for (events) |e| e.deinit(std.testing.allocator);
        std.testing.allocator.free(events);
    }
    try std.testing.expect(events.len >= 1);

    var reg = skill.Registry.init(std.testing.allocator, ".");
    defer reg.deinit();
    var metrics = ember.Ember{};
    var breaker = publish_retry.CircuitBreaker{};

    const route = tinder.Route{
        .stream = "inbox",
        .event_type = "*",
        .skill = "redact",
        .publish_stream = "outbox",
        .publish_event_type = "bedd.strike.result",
    };

    try strike.executeOne(
        std.testing.allocator,
        &cfg,
        &client,
        &reg,
        &metrics,
        &breaker,
        route,
        events[0],
    );
    try std.testing.expectEqual(@as(u64, 1), metrics.strikes_ok);
    try std.testing.expectEqual(@as(u64, 1), metrics.publishes);

    _ = try client.ack("inbox", "bedd-test", &.{events[0].entry_id});
    try std.testing.expect(mock.acked >= 1);
}
