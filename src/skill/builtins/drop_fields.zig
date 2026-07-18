const std = @import("std");
const skill = @import("../mod.zig");

pub const skill_name = "drop_fields";

const default_keys = [_][]const u8{
    "token", "password", "secret", "authorization", "api_key", "ssn", "credit_card",
};

pub fn run(ctx: skill.SkillContext, input_json: []const u8) skill.SkillError!skill.SkillResult {
    var owned: ?[][]const u8 = null;
    defer if (owned) |k| freeKeys(ctx.allocator, k);

    const keys: []const []const u8 = blk: {
        if (std.posix.getenv("BEDD_DROP_FIELDS")) |raw| {
            if (raw.len > 0) {
                owned = loadDropKeys(ctx.allocator, raw) catch return skill.SkillError.OutOfMemory;
                break :blk owned.?;
            }
        }
        break :blk &default_keys;
    };

    const cleaned = dropKeysFast(ctx.allocator, input_json, keys) catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = cleaned };
}

fn loadDropKeys(allocator: std.mem.Allocator, raw: []const u8) ![][]const u8 {
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

fn isDropKey(keys: []const []const u8, name: []const u8) bool {
    for (keys) |k| {
        if (std.mem.eql(u8, k, name)) return true;
    }
    return false;
}

/// Single-pass drop of `"key": value` pairs (any depth, best-effort).
fn dropKeysFast(allocator: std.mem.Allocator, input: []const u8, keys: []const []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, input.len);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '"') {
            // Possible key
            const key_start = i;
            i += 1;
            const name_start = i;
            while (i < input.len) : (i += 1) {
                if (input[i] == '\\') {
                    i += 1;
                    continue;
                }
                if (input[i] == '"') break;
            }
            if (i >= input.len) {
                try out.appendSlice(input[key_start..]);
                break;
            }
            const name = input[name_start..i];
            i += 1; // closing quote of key

            var j = i;
            while (j < input.len and (input[j] == ' ' or input[j] == '\t' or input[j] == '\n' or input[j] == '\r')) : (j += 1) {}
            if (j < input.len and input[j] == ':' and isDropKey(keys, name)) {
                j += 1;
                while (j < input.len and (input[j] == ' ' or input[j] == '\t')) : (j += 1) {}
                const val_end = skipJsonValue(input, j) orelse input.len;
                // Skip trailing comma
                var end = val_end;
                while (end < input.len and (input[end] == ' ' or input[end] == '\t')) : (end += 1) {}
                if (end < input.len and input[end] == ',') end += 1;

                // Also drop a leading comma already written
                if (out.items.len > 0 and out.items[out.items.len - 1] == ',') {
                    _ = out.pop();
                } else if (end == val_end or (end > 0 and input[end - 1] != ',')) {
                    // leading comma case handled above; if next char after skip was not comma,
                    // we may have left a double-comma — cleaned below
                }
                i = end;
                // Avoid ",}" / ",]"
                continue;
            }

            try out.appendSlice(input[key_start..i]);
            continue;
        }
        try out.append(input[i]);
        i += 1;
    }

    // Clean ",}" and ",]"
    var cleaned = try out.toOwnedSlice();
    cleaned = try scrubTrailingCommas(allocator, cleaned);
    return cleaned;
}

fn scrubTrailingCommas(allocator: std.mem.Allocator, input: []u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, input.len);
    defer allocator.free(input);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == ',' and i + 1 < input.len and (input[i + 1] == '}' or input[i + 1] == ']')) {
            i += 1;
            continue;
        }
        try out.append(input[i]);
        i += 1;
    }
    return try out.toOwnedSlice();
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
    const out = try dropKeysFast(a, "{\"token\":\"x\",\"ok\":1}", &keys);
    defer a.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "token") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"ok\":1") != null);
}
