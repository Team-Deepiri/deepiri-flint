const std = @import("std");

pub fn escapeString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    for (input) |c| {
        switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            else => try out.append(c),
        }
    }
    return try out.toOwnedSlice();
}

test "escape quotes" {
    const s = try escapeString(std.testing.allocator, "a\"b");
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("a\\\"b", s);
}
