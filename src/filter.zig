const std = @import("std");
const skill = @import("skill/mod.zig");

/// NDJSON stdin → skill → stdout.
/// `--jobs N` (or `BEDD_FILTER_JOBS`) runs N workers over line chunks.
pub fn run(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    raw_payload: bool,
    jobs: u32,
) !void {
    if (jobs <= 1) {
        try runSerial(allocator, skills_dir, skill_name, raw_payload);
        return;
    }
    try runParallel(allocator, skills_dir, skill_name, raw_payload, jobs);
}

fn runSerial(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    raw_payload: bool,
) !void {
    var reg = skill.Registry.init(allocator, skills_dir);
    defer reg.deinit();
    const skill_fn = skill.Registry.lookupBuiltin(skill_name);

    const stdin = std.io.getStdIn().reader();
    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = stdout_buf.writer();
    const stderr = std.io.getStdErr().writer();

    var line_buf: [1024 * 1024]u8 = undefined;
    var ok: u64 = 0;
    var err_n: u64 = 0;
    var n: u64 = 0;

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

        const result = if (skill_fn) |fn_ptr| fn_ptr(ctx, trimmed) else reg.run(skill_name, ctx, trimmed);
        const payload = result catch {
            err_n += 1;
            continue;
        };
        ok += 1;
        const emit = if (raw_payload) payload.payload_json else unwrapClean(payload.payload_json) orelse payload.payload_json;
        try stdout.writeAll(emit);
        try stdout.writeByte('\n');
    }

    try stdout_buf.flush();
    try stderr.print("bedd filter skill={s} jobs=1 lines={d} ok={d} err={d}\n", .{ skill_name, n, ok, err_n });
    if (err_n > 0) std.process.exit(1);
}

const WorkerCtx = struct {
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    raw: bool,
    inputs: []const []const u8,
    outputs: []?[]u8,
    start: usize,
    end: usize,
    ok: *std.atomic.Value(u64),
    err: *std.atomic.Value(u64),
};

fn workerFn(wc: *WorkerCtx) void {
    var reg = skill.Registry.init(wc.allocator, wc.skills_dir);
    defer reg.deinit();
    const skill_fn = skill.Registry.lookupBuiltin(wc.skill_name);

    var i = wc.start;
    while (i < wc.end) : (i += 1) {
        var arena = std.heap.ArenaAllocator.init(wc.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const ctx = skill.SkillContext{
            .allocator = a,
            .stream = "filter",
            .entry_id = "f",
            .event_type = "bedd.filter",
        };
        const result = if (skill_fn) |fn_ptr|
            fn_ptr(ctx, wc.inputs[i])
        else
            reg.run(wc.skill_name, ctx, wc.inputs[i]);

        const payload = result catch {
            _ = wc.err.fetchAdd(1, .monotonic);
            wc.outputs[i] = null;
            continue;
        };
        const emit = if (wc.raw) payload.payload_json else unwrapClean(payload.payload_json) orelse payload.payload_json;
        // Copy out of arena into durable allocator for ordered write.
        wc.outputs[i] = wc.allocator.dupe(u8, emit) catch {
            _ = wc.err.fetchAdd(1, .monotonic);
            continue;
        };
        _ = wc.ok.fetchAdd(1, .monotonic);
    }
}

fn runParallel(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    raw_payload: bool,
    jobs: u32,
) !void {
    const stdin = std.io.getStdIn().reader();
    var lines = std.ArrayList([]u8).init(allocator);
    defer {
        for (lines.items) |l| allocator.free(l);
        lines.deinit();
    }

    var line_buf: [1024 * 1024]u8 = undefined;
    while (true) {
        const line = (try stdin.readUntilDelimiterOrEof(&line_buf, '\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        try lines.append(try allocator.dupe(u8, trimmed));
    }

    const n = lines.items.len;
    if (n == 0) {
        try std.io.getStdErr().writer().print("bedd filter skill={s} jobs={d} lines=0 ok=0 err=0\n", .{ skill_name, jobs });
        return;
    }

    const outputs = try allocator.alloc(?[]u8, n);
    @memset(outputs, null);
    defer {
        for (outputs) |o| if (o) |p| allocator.free(p);
        allocator.free(outputs);
    }

    var ok_c = std.atomic.Value(u64).init(0);
    var err_c = std.atomic.Value(u64).init(0);

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator, .n_jobs = jobs });
    defer pool.deinit();

    var wg: std.Thread.WaitGroup = .{};
    const worker_n: usize = @min(@as(usize, jobs), n);
    const chunk = (n + worker_n - 1) / worker_n;

    var contexts = try allocator.alloc(WorkerCtx, worker_n);
    defer allocator.free(contexts);

    var w: usize = 0;
    while (w < worker_n) : (w += 1) {
        const start = w * chunk;
        if (start >= n) break;
        const end = @min(start + chunk, n);
        contexts[w] = .{
            .allocator = allocator,
            .skills_dir = skills_dir,
            .skill_name = skill_name,
            .raw = raw_payload,
            .inputs = lines.items,
            .outputs = outputs,
            .start = start,
            .end = end,
            .ok = &ok_c,
            .err = &err_c,
        };
        pool.spawnWg(&wg, workerFn, .{&contexts[w]});
    }
    pool.waitAndWork(&wg);

    var stdout_buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = stdout_buf.writer();
    for (outputs) |o| {
        if (o) |p| {
            try stdout.writeAll(p);
            try stdout.writeByte('\n');
        }
    }
    try stdout_buf.flush();

    const ok = ok_c.load(.monotonic);
    const err_n = err_c.load(.monotonic);
    try std.io.getStdErr().writer().print("bedd filter skill={s} jobs={d} lines={d} ok={d} err={d}\n", .{ skill_name, jobs, n, ok, err_n });
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
