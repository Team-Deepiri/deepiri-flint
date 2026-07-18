const std = @import("std");

pub const Route = struct {
    stream: []const u8,
    event_type: []const u8, // "*" = any
    skill: []const u8,
    publish_stream: []const u8,
    publish_event_type: []const u8,
};

pub const Tinder = struct {
    allocator: std.mem.Allocator,
    routes: []Route,
    owned_blob: ?[]u8 = null,

    pub fn deinit(self: *Tinder) void {
        for (self.routes) |r| {
            self.allocator.free(r.stream);
            self.allocator.free(r.event_type);
            self.allocator.free(r.skill);
            self.allocator.free(r.publish_stream);
            self.allocator.free(r.publish_event_type);
        }
        self.allocator.free(self.routes);
        if (self.owned_blob) |b| self.allocator.free(b);
    }

    pub fn match(self: *const Tinder, stream: []const u8, event_type: []const u8) ?Route {
        for (self.routes) |r| {
            if (!std.mem.eql(u8, r.stream, stream)) continue;
            if (std.mem.eql(u8, r.event_type, "*") or std.mem.eql(u8, r.event_type, event_type)) {
                return r;
            }
        }
        return null;
    }

    pub fn uniqueStreams(self: *const Tinder, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer list.deinit();
        for (self.routes) |r| {
            var found = false;
            for (list.items) |s| {
                if (std.mem.eql(u8, s, r.stream)) {
                    found = true;
                    break;
                }
            }
            if (!found) try list.append(r.stream);
        }
        return try list.toOwnedSlice();
    }
};

/// Minimal default: inbox → echo → outbox. Hosts override via BEDD_TINDER.
pub fn defaultTinder(allocator: std.mem.Allocator) !Tinder {
    const routes = try allocator.alloc(Route, 1);
    routes[0] = .{
        .stream = try allocator.dupe(u8, "inbox"),
        .event_type = try allocator.dupe(u8, "*"),
        .skill = try allocator.dupe(u8, "echo"),
        .publish_stream = try allocator.dupe(u8, "outbox"),
        .publish_event_type = try allocator.dupe(u8, "bedd.strike.result"),
    };
    return .{ .allocator = allocator, .routes = routes };
}

pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Tinder {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const blob = try file.readToEndAlloc(allocator, 2 * 1024 * 1024);
    errdefer allocator.free(blob);
    var tinder = try parseTinderJson(allocator, blob);
    tinder.owned_blob = blob;
    return tinder;
}

pub fn loadOrDefault(allocator: std.mem.Allocator, path: ?[]const u8) !Tinder {
    if (path) |p| {
        return loadFromFile(allocator, p) catch |err| {
            std.log.warn("failed to load tinder {s}: {s}; using defaults", .{ p, @errorName(err) });
            return defaultTinder(allocator);
        };
    }
    return defaultTinder(allocator);
}

fn parseTinderJson(allocator: std.mem.Allocator, blob: []const u8) !Tinder {
    var routes = std.ArrayList(Route).init(allocator);
    errdefer {
        for (routes.items) |r| {
            allocator.free(r.stream);
            allocator.free(r.event_type);
            allocator.free(r.skill);
            allocator.free(r.publish_stream);
            allocator.free(r.publish_event_type);
        }
        routes.deinit();
    }

    const key = std.mem.indexOf(u8, blob, "\"routes\"") orelse return error.InvalidTinder;
    var i = key;
    while (i < blob.len and blob[i] != '[') : (i += 1) {}
    if (i >= blob.len) return error.InvalidTinder;
    i += 1;

    while (i < blob.len) {
        while (i < blob.len and blob[i] != '{' and blob[i] != ']') : (i += 1) {}
        if (i >= blob.len or blob[i] == ']') break;
        const start = i;
        var depth: i32 = 0;
        var in_str = false;
        var escape = false;
        while (i < blob.len) : (i += 1) {
            const c = blob[i];
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
                    i += 1;
                    break;
                }
            }
        }
        const obj = blob[start..i];
        const jsonx = @import("jsonx.zig");
        const stream = jsonx.getStringField(obj, "stream") orelse continue;
        const skill = jsonx.getStringField(obj, "skill") orelse continue;
        const event_type = jsonx.getStringField(obj, "event_type") orelse "*";
        const publish_stream = jsonx.getStringField(obj, "publish_stream") orelse "outbox";
        const publish_event_type = jsonx.getStringField(obj, "publish_event_type") orelse "bedd.strike.result";

        try routes.append(.{
            .stream = try allocator.dupe(u8, stream),
            .event_type = try allocator.dupe(u8, event_type),
            .skill = try allocator.dupe(u8, skill),
            .publish_stream = try allocator.dupe(u8, publish_stream),
            .publish_event_type = try allocator.dupe(u8, publish_event_type),
        });
    }

    if (routes.items.len == 0) return error.InvalidTinder;
    return .{
        .allocator = allocator,
        .routes = try routes.toOwnedSlice(),
    };
}

test "default tinder matches inbox" {
    var t = try defaultTinder(std.testing.allocator);
    defer t.deinit();
    const r = t.match("inbox", "anything");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("echo", r.?.skill);
}

test "parse tinder json" {
    const sample =
        \\{"routes":[{"stream":"inbox","event_type":"*","skill":"echo","publish_stream":"outbox","publish_event_type":"bedd.strike.result"}]}
    ;
    var t = try parseTinderJson(std.testing.allocator, sample);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 1), t.routes.len);
}
