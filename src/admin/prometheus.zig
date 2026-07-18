const std = @import("std");
const ember = @import("../ember.zig");

pub fn render(metrics: *const ember.Ember, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator,
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
    , .{ metrics.strikes_ok, metrics.strikes_err, metrics.publishes, metrics.acks, metrics.reads });
}
