const std = @import("std");
const skill = @import("../mod.zig");

pub const skill_name = "drop_fields";

/// Drop top-level JSON object keys listed in BEDD_DROP_FIELDS (comma-separated).
/// Default: token,password,secret,authorization,api_key,ssn,credit_card
pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    const keys = loadDropKeys(ctx.allocator) catch return skill.SkillError.OutOfMemory;
    defer freeKeys(ctx.allocator, keys);

    const cleaned = dropKeys(ctx.allocator, input_json, keys) catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = cleaned };
}

fn loadDropKeys(allocator: std.mem.Allocator) ![][]const u8 {
    const raw = std.posix.getenv("BEDD_DROP_FIELDS") orelse
        "token,password,secret,authorization,api_key,ssn,credit_card";
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (list.items) |k| allocator.free(k);
        list.deinit();
    }
    var it = std.mem.splitScalar(u8, raw, ',');
    while (it.next()) |part| {
        const t = std.mem.trim(u8, part, " \t");
        if (t.len == 0) continue;
        try list.append(try allocator.dupe(u8, t));
    }
    return try list.toOwnedSlice();
}

fn freeKeys(allocator: std.mem.Allocator, keys: [][]const u8) void {
    for (keys) |k| allocator.free(k);
    allocator.free(keys);
}

/// Best-effort: remove `"key":...` pairs at any depth (string scan).
fn dropKeys(allocator: std.mem.Allocator, input: []const u8, keys: []const []const u8) ![]u8 {
    var out = try allocator.dupe(u8, input);
    errdefer allocator.free(out);

    for (keys) |key| {
        var search_from: usize = 0;
        while (search_from < out.len) {
            const needle = try std.fmt.allocPrint(allocator, "\"{s}\"", .{key});
            defer allocator.free(needle);
            const idx = std.mem.indexOfPos(u8, out, search_from, needle) orelse break;

            // Find start of `"key"` and end of its value, then also a preceding/trailing comma.
            const key_start = idx;
            var j = idx + needle.len;
            while (j < out.len and (out[j] == ' ' or out[j] == '\t' or out[j] == '\n' or out[j] == '\r' or out[j] == ':')) : (j += 1) {}
            if (j >= out.len) {
                search_from = idx + 1;
                continue;
            }

            const val_end = skipJsonValue(out, j) orelse {
                search_from = idx + 1;
                continue;
            };

            // Include trailing comma if present
            var end = val_end;
            while (end < out.len and (out[end] == ' ' or out[end] == '\t')) : (end += 1) {}
            if (end < out.len and out[end] == ',') end += 1;

            // Or leading comma if no trailing
            var start = key_start;
            if (end == val_end or (end > 0 and out[end - 1] != ',')) {
                var back = key_start;
                while (back > 0 and (out[back - 1] == ' ' or out[back - 1] == '\t' or out[back - 1] == '\n')) : (back -= 1) {}
                if (back > 0 and out[back - 1] == ',') {
                    start = back - 1;
                }
            }

            var rebuilt = std.ArrayList(u8).init(allocator);
            defer rebuilt.deinit();
            try rebuilt.appendSlice(out[0..start]);
            try rebuilt.appendSlice(out[end..]);
            allocator.free(out);
            out = try rebuilt.toOwnedSlice();
            search_from = start;
        }
    }
    return out;
}

fn skipJsonValue(buf: []const u8, start: usize) ?usize {
    if (start >= buf.len) return null;
    const c = buf[start];
    if (c == '"') {
        var i = start + 1;
        while (i < buf.len) : (i += 1) {
            if (buf[i] == '\\') {
                i += 1;
                continue;
            }
            if (buf[i] == '"') return i + 1;
        }
        return null;
    }
    if (c == '{' or c == '[') {
        var depth: i32 = 0;
        var in_str = false;
        var escape = false;
        var i = start;
        while (i < buf.len) : (i += 1) {
            const ch = buf[i];
            if (escape) {
                escape = false;
                continue;
            }
            if (ch == '\\' and in_str) {
                escape = true;
                continue;
            }
            if (ch == '"') {
                in_str = !in_str;
                continue;
            }
            if (in_str) continue;
            if (ch == '{' or ch == '[') depth += 1;
            if (ch == '}' or ch == ']') {
                depth -= 1;
                if (depth == 0) return i + 1;
            }
        }
        return null;
    }
    // number / bool / null
    var i = start;
    while (i < buf.len) : (i += 1) {
        const ch = buf[i];
        if (ch == ',' or ch == '}' or ch == ']' or ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t') return i;
    }
    return buf.len;
}

test "drop_fields removes token" {
    const a = std.testing.allocator;
    const keys = [_][]const u8{"token"};
    const out = try dropKeys(a, "{\"token\":\"x\",\"ok\":1}", &keys);
    defer a.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "token") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ok\":1") != null);
}
