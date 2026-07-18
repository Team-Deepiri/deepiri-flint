const std = @import("std");
const skill = @import("mod.zig");
const builder = @import("../json/builder.zig");
const hash = @import("../util/hash.zig");
const jsonx = @import("../jsonx.zig");

pub const secret_keys = [_][]const u8{
    "password", "passwd", "secret", "token", "api_key", "apikey",
    "authorization", "access_key", "private_key", "credential",
};

/// Redact known secret-ish string values in a JSON blob (best-effort scan).
pub fn redactSecrets(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try allocator.dupe(u8, input);
    errdefer allocator.free(out);

    for (secret_keys) |key| {
        var search_from: usize = 0;
        while (search_from < out.len) {
            const needle = try std.fmt.allocPrint(allocator, "\"{s}\"", .{key});
            defer allocator.free(needle);
            const idx = std.mem.indexOfPos(u8, out, search_from, needle) orelse break;
            // Find following string value and replace with "***"
            var j = idx + needle.len;
            while (j < out.len and (out[j] == ' ' or out[j] == '\t' or out[j] == ':')) : (j += 1) {}
            if (j >= out.len or out[j] != '"') {
                search_from = idx + 1;
                continue;
            }
            const val_start = j;
            j += 1;
            while (j < out.len) : (j += 1) {
                if (out[j] == '\\') {
                    j += 1;
                    continue;
                }
                if (out[j] == '"') break;
            }
            if (j >= out.len) break;
            const val_end = j + 1; // inclusive end quote+1
            // Rebuild with ***
            var rebuilt = std.ArrayList(u8).init(allocator);
            defer rebuilt.deinit();
            try rebuilt.appendSlice(out[0 .. val_start + 1]);
            try rebuilt.appendSlice("***");
            try rebuilt.appendSlice(out[val_end - 1 ..]);
            allocator.free(out);
            out = try rebuilt.toOwnedSlice();
            search_from = val_start + 4;
        }
    }
    return out;
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
