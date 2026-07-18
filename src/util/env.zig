const std = @import("std");

pub fn get(key: []const u8) ?[]const u8 {
    return std.posix.getenv(key);
}

pub fn getOr(key: []const u8, fallback: []const u8) []const u8 {
    return get(key) orelse fallback;
}

pub fn getBool(key: []const u8, fallback: bool) bool {
    const v = get(key) orelse return fallback;
    if (std.ascii.eqlIgnoreCase(v, "1") or std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(v, "0") or std.ascii.eqlIgnoreCase(v, "false") or std.ascii.eqlIgnoreCase(v, "no")) return false;
    return fallback;
}

pub fn getU64(key: []const u8, fallback: u64) u64 {
    const v = get(key) orelse return fallback;
    return std.fmt.parseInt(u64, v, 10) catch fallback;
}
