const std = @import("std");

pub const Level = enum { debug, info, warn, err };

var current: Level = .info;

pub fn setLevel(level: Level) void {
    current = level;
}

pub fn setLevelFromEnv() void {
    const raw = std.posix.getenv("FLINT_LOG_LEVEL") orelse return;
    if (std.ascii.eqlIgnoreCase(raw, "debug")) current = .debug;
    if (std.ascii.eqlIgnoreCase(raw, "info")) current = .info;
    if (std.ascii.eqlIgnoreCase(raw, "warn")) current = .warn;
    if (std.ascii.eqlIgnoreCase(raw, "error") or std.ascii.eqlIgnoreCase(raw, "err")) current = .err;
}

fn enabled(level: Level) bool {
    return @intFromEnum(level) >= @intFromEnum(current);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.debug)) return;
    std.log.debug(fmt, args);
}
pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.info)) return;
    std.log.info(fmt, args);
}
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.warn)) return;
    std.log.warn(fmt, args);
}
pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.err)) return;
    std.log.err(fmt, args);
}
