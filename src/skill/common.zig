const std = @import("std");
const skill = @import("mod.zig");
const builder = @import("../json/builder.zig");
const hash = @import("../util/hash.zig");
const jsonx = @import("../jsonx.zig");

pub const secret_keys = [_][]const u8{
    "password", "passwd", "secret", "token", "api_key", "apikey",
    "authorization", "access_key", "private_key", "credential",
};

/// Fast redact: one allocation, in-place mask + memmove (no per-match realloc).
pub fn redactSecrets(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try allocator.dupe(u8, input);
    errdefer allocator.free(out);
    var len = out.len;

    for (secret_keys) |key| {
        var needle_buf: [64]u8 = undefined;
        if (key.len + 2 > needle_buf.len) continue;
        needle_buf[0] = '"';
        @memcpy(needle_buf[1 .. 1 + key.len], key);
        needle_buf[1 + key.len] = '"';
        const needle = needle_buf[0 .. key.len + 2];

        var search_from: usize = 0;
        while (search_from < len) {
            const idx = std.mem.indexOfPos(u8, out[0..len], search_from, needle) orelse break;
            var j = idx + needle.len;
            while (j < len and (out[j] == ' ' or out[j] == '\t' or out[j] == ':')) : (j += 1) {}
            if (j >= len or out[j] != '"') {
                search_from = idx + 1;
                continue;
            }
            const val_start = j; // opening quote
            j += 1;
            while (j < len) : (j += 1) {
                if (out[j] == '\\') {
                    j += 1;
                    continue;
                }
                if (out[j] == '"') break;
            }
            if (j >= len) break;
            const content_start = val_start + 1;
            const content_end = j; // exclusive; closing quote at j
            const old_len = content_end - content_start;
            const mask = "***";
            // Write mask; shrink/grow with memmove
            if (old_len == mask.len) {
                @memcpy(out[content_start..][0..mask.len], mask);
                search_from = content_start + mask.len + 1;
            } else if (old_len > mask.len) {
                @memcpy(out[content_start..][0..mask.len], mask);
                const drop = old_len - mask.len;
                const from = content_end;
                const to = content_start + mask.len;
                std.mem.copyForwards(u8, out[to .. len - drop], out[from..len]);
                len -= drop;
                search_from = to + 1;
            } else {
                // grow: need more space
                const need = mask.len - old_len;
                const new_len = len + need;
                out = try allocator.realloc(out, new_len);
                std.mem.copyBackwards(u8, out[content_end + need .. new_len], out[content_end..len]);
                @memcpy(out[content_start..][0..mask.len], mask);
                len = new_len;
                search_from = content_start + mask.len + 1;
            }
        }
    }

    if (len != out.len) {
        out = try allocator.realloc(out, len);
    }
    return out;
}

pub fn leanMode(ctx: skill.SkillContext) bool {
    if (std.posix.getenv("BEDD_LEAN")) |v| {
        if (v.len > 0 and v[0] != '0' and !std.ascii.eqlIgnoreCase(v, "false")) return true;
    }
    return std.mem.eql(u8, ctx.stream, "filter");
}

pub fn wrapSkill(
    ctx: skill.SkillContext,
    skill_name: []const u8,
    extra_key: ?[]const u8,
    extra_raw: ?[]const u8,
    input_json: []const u8,
) skill.SkillError!skill.SkillResult {
    var o = builder.Obj.init(ctx.allocator);
    o.begin() catch return skill.SkillError.OutOfMemory;
    o.putString("skill", skill_name) catch return skill.SkillError.OutOfMemory;
    o.putString("stream", ctx.stream) catch return skill.SkillError.OutOfMemory;
    o.putString("entry_id", ctx.entry_id) catch return skill.SkillError.OutOfMemory;
    o.putString("event_type", ctx.event_type) catch return skill.SkillError.OutOfMemory;
    o.putBool("ok", true) catch return skill.SkillError.OutOfMemory;
    if (extra_key) |k| {
        if (extra_raw) |v| o.putRaw(k, v) catch return skill.SkillError.OutOfMemory;
    }
    o.putRaw("input", input_json) catch return skill.SkillError.OutOfMemory;
    const out = o.end() catch return skill.SkillError.OutOfMemory;
    return .{ .payload_json = out };
}

pub fn fingerprintOf(allocator: std.mem.Allocator, input: []const u8) skill.SkillError![]u8 {
    return hash.sha256Hex(allocator, input) catch skill.SkillError.OutOfMemory;
}

pub fn extractDocumentId(input: []const u8) ?[]const u8 {
    const path = @import("../json/path.zig");
    return path.getPathString(input, "documentId") orelse
        path.getPathString(input, "document_id") orelse
        path.getPathString(input, "data.documentId") orelse
        jsonx.getStringField(input, "documentId") orelse
        jsonx.getStringField(input, "document_id");
}

test "redactSecrets masks token" {
    const in =
        \\{"token":"abc","x":1}
    ;
    const out = try redactSecrets(std.testing.allocator, in);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "***") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "abc") == null);
}

test "redactSecrets long secret" {
    const in =
        \\{"token":"super-long-secret-value","ok":true}
    ;
    const out = try redactSecrets(std.testing.allocator, in);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "super-long") == null);
    try std.testing.expectEqualStrings("{\"token\":\"***\",\"ok\":true}", out);
}
