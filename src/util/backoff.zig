const std = @import("std");

pub fn exponential(attempt: u32, base_ms: u64, cap_ms: u64) u64 {
    const shift: u6 = @intCast(@min(attempt, 16));
    const raw = base_ms * (@as(u64, 1) << shift);
    return @min(raw, cap_ms);
}

test "backoff caps" {
    try std.testing.expectEqual(@as(u64, 100), exponential(0, 100, 5000));
    try std.testing.expectEqual(@as(u64, 5000), exponential(20, 100, 5000));
}
