const std = @import("std");
const backoff = @import("util/backoff.zig");

pub fn sleepAttempt(attempt: u32) void {
    const ms = backoff.exponential(attempt, 50, 5000);
    std.time.sleep(ms * std.time.ns_per_ms);
}
