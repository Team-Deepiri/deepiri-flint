const std = @import("std");

/// In-process metrics + last-N strike traces + latency buckets.
pub const Ember = struct {
    strikes_ok: u64 = 0,
    strikes_err: u64 = 0,
    publishes: u64 = 0,
    acks: u64 = 0,
    reads: u64 = 0,
    latency_sum_ms: u64 = 0,
    /// Buckets: <=1, <=5, <=25, <=100, <=500, >500 ms
    latency_buckets: [6]u64 = [_]u64{0} ** 6,
    mutex: std.Thread.Mutex = .{},
    ring: [16]Trace = [_]Trace{.{}} ** 16,
    ring_i: usize = 0,

    pub const Trace = struct {
        stream: [96]u8 = [_]u8{0} ** 96,
        stream_len: usize = 0,
        skill: [48]u8 = [_]u8{0} ** 48,
        skill_len: usize = 0,
        ok: bool = false,
        ms: u64 = 0,
    };

    pub fn record(self: *Ember, stream: []const u8, skill_name: []const u8, ok: bool, ms: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (ok) self.strikes_ok += 1 else self.strikes_err += 1;
        self.latency_sum_ms += ms;
        const bucket: usize = if (ms <= 1) 0 else if (ms <= 5) 1 else if (ms <= 25) 2 else if (ms <= 100) 3 else if (ms <= 500) 4 else 5;
        self.latency_buckets[bucket] += 1;

        var t = Trace{ .ok = ok, .ms = ms };
        const sl = @min(stream.len, t.stream.len);
        @memcpy(t.stream[0..sl], stream[0..sl]);
        t.stream_len = sl;
        const kl = @min(skill_name.len, t.skill.len);
        @memcpy(t.skill[0..kl], skill_name[0..kl]);
        t.skill_len = kl;
        self.ring[self.ring_i % self.ring.len] = t;
        self.ring_i += 1;
    }

    pub fn avgLatencyMs(self: *const Ember) u64 {
        const n = self.strikes_ok + self.strikes_err;
        if (n == 0) return 0;
        return self.latency_sum_ms / n;
    }

    pub fn print(self: *Ember, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try writer.print(
            "ember strikes_ok={d} strikes_err={d} publishes={d} acks={d} reads={d} avg_ms={d}\n",
            .{
                self.strikes_ok,
                self.strikes_err,
                self.publishes,
                self.acks,
                self.reads,
                if (self.strikes_ok + self.strikes_err == 0) 0 else self.latency_sum_ms / (self.strikes_ok + self.strikes_err),
            },
        );
    }
};

test "ember records latency buckets" {
    var e = Ember{};
    e.record("inbox", "echo", true, 3);
    e.record("inbox", "echo", true, 80);
    try std.testing.expectEqual(@as(u64, 2), e.strikes_ok);
    try std.testing.expect(e.latency_buckets[1] == 1); // <=5
    try std.testing.expect(e.latency_buckets[3] == 1); // <=100
}
