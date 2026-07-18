const std = @import("std");
const jsonx = @import("../jsonx.zig");

/// Resolve a dotted path of string fields by walking nested objects.
/// Example: `data.documentId` finds `"data":{..."documentId":"x"...}`
pub fn getPathString(json: []const u8, path: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, path, '.') == null) {
        return jsonx.getStringField(json, path);
    }

    var rest = json;
    var iter = std.mem.splitScalar(u8, path, '.');
    var parts = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer parts.deinit();
    while (iter.next()) |p| {
        parts.append(p) catch return null;
    }
    if (parts.items.len == 0) return null;

    var i: usize = 0;
    while (i + 1 < parts.items.len) : (i += 1) {
        const key = parts.items[i];
        const obj = findObjectField(rest, key) orelse return null;
        rest = obj;
    }
    return jsonx.getStringField(rest, parts.items[parts.items.len - 1]);
}

fn findObjectField(json: []const u8, key: []const u8) ?[]const u8 {
    var needle_buf: [128]u8 = undefined;
    if (key.len + 3 > needle_buf.len) return null;
    const needle = std.fmt.bufPrint(&needle_buf, "\"{s}\"", .{key}) catch return null;
    var i: usize = 0;
    while (i + needle.len < json.len) : (i += 1) {
        if (!std.mem.eql(u8, json[i..][0..needle.len], needle)) continue;
        var j = i + needle.len;
        while (j < json.len and (json[j] == ' ' or json[j] == '\t' or json[j] == '\n' or json[j] == '\r')) : (j += 1) {}
        if (j >= json.len or json[j] != ':') continue;
        j += 1;
        while (j < json.len and (json[j] == ' ' or json[j] == '\t' or json[j] == '\n' or json[j] == '\r')) : (j += 1) {}
        if (j >= json.len or json[j] != '{') return null;
        const start = j;
        var depth: i32 = 0;
        var in_str = false;
        var escape = false;
        while (j < json.len) : (j += 1) {
            const c = json[j];
            if (escape) {
                escape = false;
                continue;
            }
            if (c == '\\' and in_str) {
                escape = true;
                continue;
            }
            if (c == '"') {
                in_str = !in_str;
                continue;
            }
            if (in_str) continue;
            if (c == '{') depth += 1;
            if (c == '}') {
                depth -= 1;
                if (depth == 0) {
                    j += 1;
                    return json[start..j];
                }
            }
        }
        return null;
    }
    return null;
}

test "getPathString nested" {
    const json =
        \\{"data":{"documentId":"doc-1","x":1}}
    ;
    const v = getPathString(json, "data.documentId");
    try std.testing.expect(v != null);
    try std.testing.expectEqualStrings("doc-1", v.?);
}

test "getPathString flat" {
    const v = getPathString("{\"a\":\"b\"}", "a");
    try std.testing.expectEqualStrings("b", v.?);
}
