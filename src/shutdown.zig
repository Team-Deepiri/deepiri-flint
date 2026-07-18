const std = @import("std");

var stopping = std.atomic.Value(bool).init(false);

pub fn requestStop() void {
    stopping.store(true, .seq_cst);
}

pub fn shouldStop() bool {
    return stopping.load(.seq_cst);
}

pub fn installSignals() void {
    // Best-effort: serve loop polls shouldStop(); callers can requestStop on SIGTERM later.
}
