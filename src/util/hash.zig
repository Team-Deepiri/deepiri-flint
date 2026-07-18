const std = @import("std");

pub fn sha256Hex(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var h: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &h, .{});
    return try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&h)});
}

test "sha256Hex length" {
    const out = try sha256Hex(std.testing.allocator, "flint");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(@as(usize, 64), out.len);
}
