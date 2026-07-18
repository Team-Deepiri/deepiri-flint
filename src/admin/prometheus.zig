const std = @import("std");
const ember = @import("../ember.zig");
const version = @import("../util/version.zig");

pub fn render(metrics: *const ember.Ember, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\# HELP bedd_info Bedd runtime info
        \\# TYPE bedd_info gauge
        \\bedd_info{{version="{s}",codename="{s}"}} 1
        \\# HELP bedd_strikes_ok Successful strikes
        \\# TYPE bedd_strikes_ok counter
        \\bedd_strikes_ok {d}
        \\# HELP bedd_strikes_err Failed strikes
        \\# TYPE bedd_strikes_err counter
        \\bedd_strikes_err {d}
        \\# HELP bedd_publishes_total Publish attempts
        \\# TYPE bedd_publishes_total counter
        \\bedd_publishes_total {d}
        \\# HELP bedd_acks_total Acked entries
        \\# TYPE bedd_acks_total counter
        \\bedd_acks_total {d}
        \\# HELP bedd_reads_total Read loops
        \\# TYPE bedd_reads_total counter
        \\bedd_reads_total {d}
        \\# HELP bedd_strike_latency_ms_sum Strike latency sum
        \\# TYPE bedd_strike_latency_ms_sum counter
        \\bedd_strike_latency_ms_sum {d}
        \\# HELP bedd_strike_latency_bucket Strike latency histogram buckets
        \\# TYPE bedd_strike_latency_bucket counter
        \\bedd_strike_latency_bucket{{le="1"}} {d}
        \\bedd_strike_latency_bucket{{le="5"}} {d}
        \\bedd_strike_latency_bucket{{le="25"}} {d}
        \\bedd_strike_latency_bucket{{le="100"}} {d}
        \\bedd_strike_latency_bucket{{le="500"}} {d}
        \\bedd_strike_latency_bucket{{le="+Inf"}} {d}
        \\
    , .{
        version.semver,
        version.codename,
        metrics.strikes_ok,
        metrics.strikes_err,
        metrics.publishes,
        metrics.acks,
        metrics.reads,
        metrics.latency_sum_ms,
        metrics.latency_buckets[0],
        metrics.latency_buckets[0] + metrics.latency_buckets[1],
        metrics.latency_buckets[0] + metrics.latency_buckets[1] + metrics.latency_buckets[2],
        metrics.latency_buckets[0] + metrics.latency_buckets[1] + metrics.latency_buckets[2] + metrics.latency_buckets[3],
        metrics.latency_buckets[0] + metrics.latency_buckets[1] + metrics.latency_buckets[2] + metrics.latency_buckets[3] + metrics.latency_buckets[4],
        metrics.latency_buckets[0] + metrics.latency_buckets[1] + metrics.latency_buckets[2] + metrics.latency_buckets[3] + metrics.latency_buckets[4] + metrics.latency_buckets[5],
    });
}

test "prometheus contains counters" {
    var m = ember.Ember{};
    m.strikes_ok = 3;
    const body = try render(&m, std.testing.allocator);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "bedd_strikes_ok 3") != null);
}
