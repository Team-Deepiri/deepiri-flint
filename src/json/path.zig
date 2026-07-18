const std = @import("std");
const jsonx = @import("../jsonx.zig");

/// Resolve a dotted path of string fields (shallow helper).
pub fn getPathString(json: []const u8, path: []const u8) ?[]const u8 {
    // Only supports single key for now; multi-segment later.
    if (std.mem.indexOfScalar(u8, path, '.')) |_| {
        return null;
    }
    return jsonx.getStringField(json, path);
}

test "getPathString" {
    const v = getPathString("{\"a\":\"b\"}", "a");
    try std.testing.expect(v != null);
}
