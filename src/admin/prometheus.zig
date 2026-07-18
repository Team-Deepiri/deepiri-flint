const std = @import("std");
const ember = @import("../ember.zig");
const version = @import("../util/version.zig");

pub fn render(metrics: *const ember.Ember, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\# HELP flint_info Flint runtime info
        \\# TYPE flint_info gauge
        \\flint_info{{version="{s}",codename="{s}"}} 1
        \\# HELP flint_strikes_ok Successful strikes
        \\# TYPE flint_strikes_ok counter
        \\flint_strikes_ok {d}
        \\# HELP flint_strikes_err Failed strikes
        \\# TYPE flint_strikes_err counter
        \\flint_strikes_err {d}
        \\# HELP flint_publishes_total Publish attempts
        \\# TYPE flint_publishes_total counter
        \\flint_publishes_total {d}
        \\# HELP flint_acks_total Acked entries
        \\# TYPE flint_acks_total counter
        \\flint_acks_total {d}
        \\# HELP flint_reads_total Read loops
        \\# TYPE flint_reads_total counter
        \\flint_reads_total {d}
        \\
    , .{
        version.semver,
        version.codename,
        metrics.strikes_ok,
        metrics.strikes_err,
        metrics.publishes,
        metrics.acks,
        metrics.reads,
    });
}

test "prometheus contains counters" {
    var m = ember.Ember{};
    m.strikes_ok = 3;
    const body = try render(&m, std.testing.allocator);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "flint_strikes_ok 3") != null);
}
