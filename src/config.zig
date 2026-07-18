const version_mod = @import("util/version.zig");
const std = @import("std");

pub const version = version_mod.semver;

pub const Config = struct {
    allocator: std.mem.Allocator,
    bus_url: []u8,
    sender: []u8,
    consumer_group: []u8,
    consumer_name: []u8,
    tinder_path: ?[]u8,
    skills_dir: []u8,
    dlq_stream: []u8,
    confirm_stream: []u8,
    timeout_ms: u64,
    block_ms: i64,
    read_count: i64,
    prefetch: i64,
    dry_run: bool,
    lean: bool,
    confirms: bool,
    admin_port: u16,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.bus_url);
        self.allocator.free(self.sender);
        self.allocator.free(self.consumer_group);
        self.allocator.free(self.consumer_name);
        if (self.tinder_path) |p| self.allocator.free(p);
        self.allocator.free(self.skills_dir);
        self.allocator.free(self.dlq_stream);
        self.allocator.free(self.confirm_stream);
    }
};

fn envOr(allocator: std.mem.Allocator, keys: []const []const u8, fallback: []const u8) ![]u8 {
    for (keys) |key| {
        if (std.posix.getenv(key)) |v| {
            if (v.len > 0) return try allocator.dupe(u8, v);
        }
    }
    return try allocator.dupe(u8, fallback);
}

fn stripSlash(allocator: std.mem.Allocator, url: []u8) ![]u8 {
    if (url.len > 0 and url[url.len - 1] == '/') {
        const trimmed = try allocator.dupe(u8, url[0 .. url.len - 1]);
        allocator.free(url);
        return trimmed;
    }
    return url;
}

pub fn loadFromEnv(allocator: std.mem.Allocator) !Config {
    var url = try envOr(allocator, &.{"BEDD_BUS_URL"}, "http://127.0.0.1:8081");
    url = try stripSlash(allocator, url);

    const sender = try envOr(allocator, &.{"BEDD_SENDER"}, "bedd");
    const consumer_group = try envOr(allocator, &.{"BEDD_CONSUMER_GROUP"}, "bedd-workers");
    const consumer_name = try envOr(allocator, &.{"BEDD_CONSUMER_NAME"}, "bedd-1");
    const skills_dir = try envOr(allocator, &.{"BEDD_SKILLS_DIR"}, "zig-out/skills");
    const dlq_stream = try envOr(allocator, &.{"BEDD_DLQ_STREAM"}, "dead-letter");
    const confirm_stream = try envOr(allocator, &.{"BEDD_CONFIRM_STREAM"}, "bedd.confirms");

    var tinder_path: ?[]u8 = null;
    if (std.posix.getenv("BEDD_TINDER")) |v| {
        if (v.len > 0) tinder_path = try allocator.dupe(u8, v);
    } else if (std.posix.getenv("BEDD_TINDER_PATH")) |v| {
        if (v.len > 0) tinder_path = try allocator.dupe(u8, v);
    }

    const timeout_ms = parseU64(std.posix.getenv("BEDD_TIMEOUT_MS"), 5000);
    const block_ms: i64 = @intCast(parseU64(std.posix.getenv("BEDD_BLOCK_MS"), 2000));
    const read_count: i64 = @intCast(parseU64(std.posix.getenv("BEDD_READ_COUNT"), 32));
    const prefetch: i64 = @intCast(parseU64(std.posix.getenv("BEDD_PREFETCH"), @intCast(read_count)));
    const dry_run = parseBool(std.posix.getenv("BEDD_DRY_RUN"), false);
    // Lean by default on redis:// (skip wrap envelope on the hot path).
    const lean_default = std.mem.startsWith(u8, url, "redis://") or std.mem.startsWith(u8, url, "rediss://");
    const lean = parseBool(std.posix.getenv("BEDD_LEAN"), lean_default);
    const confirms = parseBool(std.posix.getenv("BEDD_CONFIRMS"), !lean_default);
    const admin_port: u16 = @intCast(parseU64(std.posix.getenv("BEDD_ADMIN_PORT"), 9108));

    return .{
        .allocator = allocator,
        .bus_url = url,
        .sender = sender,
        .consumer_group = consumer_group,
        .consumer_name = consumer_name,
        .tinder_path = tinder_path,
        .skills_dir = skills_dir,
        .dlq_stream = dlq_stream,
        .confirm_stream = confirm_stream,
        .timeout_ms = timeout_ms,
        .block_ms = block_ms,
        .read_count = read_count,
        .prefetch = prefetch,
        .dry_run = dry_run,
        .lean = lean,
        .confirms = confirms,
        .admin_port = admin_port,
    };
}

fn parseU64(raw: ?[]const u8, fallback: u64) u64 {
    const v = raw orelse return fallback;
    return std.fmt.parseInt(u64, v, 10) catch fallback;
}

fn parseBool(raw: ?[]const u8, fallback: bool) bool {
    const v = raw orelse return fallback;
    if (std.ascii.eqlIgnoreCase(v, "1") or std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes"))
        return true;
    if (std.ascii.eqlIgnoreCase(v, "0") or std.ascii.eqlIgnoreCase(v, "false") or std.ascii.eqlIgnoreCase(v, "no"))
        return false;
    return fallback;
}

test "stripSlash removes trailing slash" {
    const a = std.testing.allocator;
    var url = try a.dupe(u8, "http://localhost:8081/");
    url = try stripSlash(a, url);
    defer a.free(url);
    try std.testing.expectEqualStrings("http://localhost:8081", url);
}
