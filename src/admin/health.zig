const std = @import("std");
const config = @import("../config.zig");

pub fn renderJson(cfg: *const config.Config, allocator: std.mem.Allocator, bus_ok: bool) ![]u8 {
    const status: []const u8 = if (bus_ok) "ok" else "degraded";
    return std.fmt.allocPrint(allocator,
        \\{{"status":"{s}","service":"bedd","sender":"{s}","sidecar":"{s}","bus_ok":{},"consumer_group":"{s}","consumer_name":"{s}"}}
    , .{ status, cfg.sender, cfg.bus_url, bus_ok, cfg.consumer_group, cfg.consumer_name });
}
