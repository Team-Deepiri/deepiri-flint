const std = @import("std");
const skill = @import("skill/mod.zig");

/// NDJSON stdin → skill → stdout (hot path: arena + buffered IO).
pub fn run(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    raw_payload: bool,
) !void {
    var reg = skill.Registry.init(allocator, skills_dir);
    defer reg.deinit();

    const stdin = std.io.getStdIn().reader();
    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = stdout_buf.writer();
    const stderr = std.io.getStdErr().writer();

    var line_buf: [1024 * 1024]u8 = undefined;
    var ok: u64 = 0;
    var err_n: u64 = 0;
    var n: u64 = 0;

    // Resolve builtin once (avoid per-line name scan when possible).
    const skill_fn = skill.Registry.lookupBuiltin(skill_name);

    while (true) {
        const line = (try stdin.readUntilDelimiterOrEof(&line_buf, '\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        n += 1;

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var entry_buf: [32]u8 = undefined;
        const entry_id = std.fmt.bufPrint(&entry_buf, "f-{d}", .{n}) catch "f";

        const ctx = skill.SkillContext{
            .allocator = a,
            .stream = "filter",
            .entry_id = entry_id,
            .event_type = "bedd.filter",
        };

        const result = if (skill_fn) |fn_ptr|
            fn_ptr(ctx, trimmed)
        else
            reg.run(skill_name, ctx, trimmed);

        const payload = result catch |e| {
            err_n += 1;
            try stderr.print("{{\"ok\":false,\"n\":{d},\"error\":\"{s}\"}}\n", .{ n, @errorName(e) });
            continue;
        };
        // arena owns payload — do not free via result.deinit
        ok += 1;

        const emit = if (raw_payload)
            payload.payload_json
        else
            unwrapClean(payload.payload_json) orelse payload.payload_json;

        try stdout.writeAll(emit);
        try stdout.writeByte('\n');
    }

    try stdout_buf.flush();
    try stderr.print("bedd filter skill={s} lines={d} ok={d} err={d}\n", .{ skill_name, n, ok, err_n });
    if (err_n > 0) std.process.exit(1);
}

fn unwrapClean(payload: []const u8) ?[]const u8 {
    for ([_][]const u8{ "\"redacted\"", "\"payload\"" }) |key| {
        const idx = std.mem.indexOf(u8, payload, key) orelse continue;
        var j = idx + key.len;
        while (j < payload.len and (payload[j] == ' ' or payload[j] == ':' or payload[j] == '\t')) : (j += 1) {}
        if (j >= payload.len or payload[j] != '{') continue;
        const start = j;
        var depth: i32 = 0;
        var in_str = false;
        var escape = false;
        while (j < payload.len) : (j += 1) {
            const c = payload[j];
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
                if (depth == 0) return payload[start .. j + 1];
            }
        }
    }
    return null;
}
