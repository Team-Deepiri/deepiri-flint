const std = @import("std");

/// Extract a top-level string field from a flat-ish JSON object without a full parser.
/// Handles `"key":"value"` and `"key": "value"` with basic escaping of `\"` inside strings.
pub fn getStringField(json: []const u8, key: []const u8) ?[]const u8 {
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
        if (j >= json.len or json[j] != '"') return null;
        j += 1;
        const start = j;
        while (j < json.len) : (j += 1) {
            if (json[j] == '\\') {
                j += 1;
                continue;
            }
            if (json[j] == '"') {
                return json[start..j];
            }
        }
        return null;
    }
    return null;
}

/// Build a JSON object wrapping a payload under `data` with bedd metadata.
pub fn wrapStrikeResult(
    allocator: std.mem.Allocator,
    skill_name: []const u8,
    source_stream: []const u8,
    source_entry: []const u8,
    payload_json: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\{{"schemaVersion":"bedd.strike.v1","skill":"{s}","source":{{"stream":"{s}","entry_id":"{s}"}},"data":{s}}}
    ,
        .{ skill_name, source_stream, source_entry, payload_json },
    );
}

test "getStringField finds event" {
    const json =
        \\{"event":"inbox.route","data":{}}
    ;
    const v = getStringField(json, "event") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("inbox.route", v);
}
