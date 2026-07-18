const std = @import("std");
const config = @import("../config.zig");

pub fn renderJson(cfg: *const config.Config, allocator: std.mem.Allocator, bus_ok: bool) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\{{"status":"{s}","service":"flint","sender":"{s}","sidecar":"{s}","bus_ok":{}}}
    , .{ if (bus_ok) "ok" else "degraded", cfg.sender, cfg.sugar_glider_url, bus_ok });
}
