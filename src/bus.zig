const std = @import("std");
const config = @import("config.zig");
const bus_redis = @import("bus_redis.zig");

pub const BusError = error{
    HttpFailed,
    BadStatus,
    InvalidJson,
    SidecarUnhealthy,
    OutOfMemory,
    Unexpected,
    RedisFailed,
};

pub const PublishRequest = struct {
    stream: []const u8,
    event_type: []const u8,
    sender: []const u8,
    payload_json: []const u8,
    priority: []const u8 = "normal",
};

pub const ReadRequest = struct {
    stream: []const u8,
    consumer_group: []const u8,
    consumer_name: []const u8,
    count: i64 = 10,
    block_ms: i64 = 1000,
};

pub const StreamEvent = struct {
    stream: []const u8,
    entry_id: []const u8,
    /// Raw JSON object of Redis stream fields (as returned by HTTP bus).
    fields_json: []const u8,
    /// Best-effort event type extracted from fields.
    event_type: []const u8,
    /// Best-effort payload JSON (fields.payload or entire fields).
    payload_json: []const u8,

    pub fn deinit(self: StreamEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.stream);
        allocator.free(self.entry_id);
        allocator.free(self.fields_json);
        allocator.free(self.event_type);
        allocator.free(self.payload_json);
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    http: std.http.Client,
    timeout_ms: u64,
    redis: ?bus_redis.Conn = null,

    pub fn init(allocator: std.mem.Allocator, cfg: config.Config) Client {
        var c: Client = .{
            .allocator = allocator,
            .base_url = cfg.bus_url,
            .http = .{ .allocator = allocator },
            .timeout_ms = cfg.timeout_ms,
            .redis = null,
        };
        if (bus_redis.isRedisUrl(cfg.bus_url)) {
            c.redis = bus_redis.Conn.connect(allocator, cfg.bus_url) catch null;
        }
        return c;
    }

    pub fn deinit(self: *Client) void {
        if (self.redis) |*r| r.deinit();
        self.http.deinit();
    }

    pub fn health(self: *Client) !bool {
        if (self.redis) |*r| return r.ping();
        const url = try std.fmt.allocPrint(self.allocator, "{s}/healthz", .{self.base_url});
        defer self.allocator.free(url);
        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();
        const result = self.http.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_storage = .{ .dynamic = &body },
            .max_append_size = 64 * 1024,
        }) catch return false;
        return result.status == .ok;
    }

    pub fn ready(self: *Client) !bool {
        if (self.redis) |*r| return r.ping();
        const url = try std.fmt.allocPrint(self.allocator, "{s}/readyz", .{self.base_url});
        defer self.allocator.free(url);
        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();
        const result = self.http.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_storage = .{ .dynamic = &body },
            .max_append_size = 64 * 1024,
        }) catch return false;
        return result.status == .ok;
    }

    pub fn publish(self: *Client, req: PublishRequest) !PublishResult {
        if (self.redis) |*r| {
            return r.publish(req) catch return BusError.RedisFailed;
        }
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/publish", .{self.base_url});
        defer self.allocator.free(url);

        const body_req = try std.fmt.allocPrint(
            self.allocator,
            \\{{"stream":"{s}","event_type":"{s}","sender":"{s}","priority":"{s}","payload":{s}}}
        ,
            .{ req.stream, req.event_type, req.sender, req.priority, req.payload_json },
        );
        defer self.allocator.free(body_req);

        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();

        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body_req,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
            .response_storage = .{ .dynamic = &body },
            .max_append_size = 256 * 1024,
        });

        if (result.status == .service_unavailable) {
            if (std.mem.indexOf(u8, body.items, "\"queued\":true") != null or
                std.mem.indexOf(u8, body.items, "\"queued\": true") != null)
            {
                return .{ .entry_id = try self.allocator.dupe(u8, "queued"), .queued = true };
            }
        }

        if (@intFromEnum(result.status) < 200 or @intFromEnum(result.status) >= 300) {
            std.log.err("publish failed status={d} body={s}", .{ @intFromEnum(result.status), body.items });
            return BusError.BadStatus;
        }

        const entry = extractJsonString(body.items, "entry_id") orelse "unknown";
        return .{
            .entry_id = try self.allocator.dupe(u8, entry),
            .queued = false,
        };
    }

    pub fn read(self: *Client, req: ReadRequest) ![]StreamEvent {
        if (self.redis) |*r| {
            return r.read(req) catch return BusError.RedisFailed;
        }
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/read", .{self.base_url});
        defer self.allocator.free(url);

        const body_req = try std.fmt.allocPrint(
            self.allocator,
            \\{{"stream":"{s}","consumer_group":"{s}","consumer_name":"{s}","count":{d},"block_ms":{d}}}
        ,
            .{ req.stream, req.consumer_group, req.consumer_name, req.count, req.block_ms },
        );
        defer self.allocator.free(body_req);

        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();

        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body_req,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
            .response_storage = .{ .dynamic = &body },
            .max_append_size = 4 * 1024 * 1024,
        });

        if (@intFromEnum(result.status) < 200 or @intFromEnum(result.status) >= 300) {
            std.log.err("read failed status={d} body={s}", .{ @intFromEnum(result.status), body.items });
            return BusError.BadStatus;
        }

        return try parseReadEvents(self.allocator, body.items);
    }

    pub fn ack(self: *Client, stream: []const u8, consumer_group: []const u8, entry_ids: []const []const u8) !i64 {
        if (self.redis) |*r| {
            return r.ack(stream, consumer_group, entry_ids) catch return BusError.RedisFailed;
        }
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/ack", .{self.base_url});
        defer self.allocator.free(url);

        var ids = std.ArrayList(u8).init(self.allocator);
        defer ids.deinit();
        try ids.appendSlice("[");
        for (entry_ids, 0..) |id, i| {
            if (i > 0) try ids.appendSlice(",");
            try ids.writer().print("\"{s}\"", .{id});
        }
        try ids.appendSlice("]");

        const body_req = try std.fmt.allocPrint(
            self.allocator,
            \\{{"stream":"{s}","consumer_group":"{s}","entry_ids":{s}}}
        ,
            .{ stream, consumer_group, ids.items },
        );
        defer self.allocator.free(body_req);

        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();

        const result = try self.http.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body_req,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
            .response_storage = .{ .dynamic = &body },
            .max_append_size = 64 * 1024,
        });

        if (@intFromEnum(result.status) < 200 or @intFromEnum(result.status) >= 300) {
            return BusError.BadStatus;
        }

        if (extractJsonNumber(body.items, "acked")) |n| return n;
        return @intCast(entry_ids.len);
    }
};

pub const PublishResult = struct {
    entry_id: []u8,
    queued: bool,

    pub fn deinit(self: PublishResult, allocator: std.mem.Allocator) void {
        allocator.free(self.entry_id);
    }
};

pub fn encodePublishBody(allocator: std.mem.Allocator, req: PublishRequest) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\{{"stream":"{s}","event_type":"{s}","sender":"{s}","priority":"{s}","payload":{s}}}
    ,
        .{ req.stream, req.event_type, req.sender, req.priority, req.payload_json },
    );
}

pub fn doctor(allocator: std.mem.Allocator, cfg: config.Config) !void {
    const out = std.io.getStdOut().writer();
    try out.print("bedd doctor\n", .{});
    try out.print("  version:          {s}\n", .{config.version});
    try out.print("  bus_url: {s}\n", .{cfg.bus_url});
    const transport: []const u8 = if (bus_redis.isRedisUrl(cfg.bus_url)) "redis-direct" else "http";
    try out.print("  transport:        {s}\n", .{transport});
    try out.print("  sender:           {s}\n", .{cfg.sender});
    try out.print("  consumer_group:   {s}\n", .{cfg.consumer_group});
    try out.print("  consumer_name:    {s}\n", .{cfg.consumer_name});
    try out.print("  skills_dir:       {s}\n", .{cfg.skills_dir});
    try out.print("  dry_run:          {}\n", .{cfg.dry_run});

    var client = Client.init(allocator, cfg);
    defer client.deinit();

    const healthy = client.health() catch false;
    const is_ready = client.ready() catch false;
    try out.print("  healthz:          {s}\n", .{if (healthy) "ok" else "unreachable"});
    try out.print("  readyz:           {s}\n", .{if (is_ready) "ok" else "unreachable"});
    if (!healthy) {
        try out.writeAll("  status:            degraded (bus unreachable — serve will retry)\n");
    } else {
        try out.writeAll("  status:            ok\n");
    }
}

fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    const jsonx = @import("jsonx.zig");
    return jsonx.getStringField(json, key);
}

fn extractJsonNumber(json: []const u8, key: []const u8) ?i64 {
    var needle_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buf, "\"{s}\"", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, json, needle) orelse return null;
    var j = idx + needle.len;
    while (j < json.len and (json[j] == ' ' or json[j] == ':' or json[j] == '\t')) : (j += 1) {}
    const start = j;
    while (j < json.len and ((json[j] >= '0' and json[j] <= '9') or json[j] == '-')) : (j += 1) {}
    if (start == j) return null;
    return std.fmt.parseInt(i64, json[start..j], 10) catch null;
}

/// Minimal events array parser for HTTP bus read responses.
fn parseReadEvents(allocator: std.mem.Allocator, body: []const u8) ![]StreamEvent {
    var list = std.ArrayList(StreamEvent).init(allocator);
    errdefer {
        for (list.items) |e| e.deinit(allocator);
        list.deinit();
    }

    // Find each {"stream":...} object inside "events":[...]
    const events_key = std.mem.indexOf(u8, body, "\"events\"") orelse {
        return try list.toOwnedSlice();
    };
    var i = events_key;
    while (i < body.len and body[i] != '[') : (i += 1) {}
    if (i >= body.len) return try list.toOwnedSlice();
    i += 1;

    while (i < body.len) {
        while (i < body.len and body[i] != '{' and body[i] != ']') : (i += 1) {}
        if (i >= body.len or body[i] == ']') break;
        const obj_start = i;
        var depth: i32 = 0;
        var in_str = false;
        var escape = false;
        while (i < body.len) : (i += 1) {
            const c = body[i];
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
        const obj = body[obj_start..i];
        try list.append(try parseOneEvent(allocator, obj));
    }

    return try list.toOwnedSlice();
}

fn parseOneEvent(allocator: std.mem.Allocator, obj: []const u8) !StreamEvent {
    const stream = extractJsonString(obj, "stream") orelse "unknown";
    const entry = extractJsonString(obj, "entry_id") orelse
        extractJsonString(obj, "entry") orelse "0-0";

    // fields object
    var fields_json: []const u8 = "{}";
    if (std.mem.indexOf(u8, obj, "\"fields\"")) |fi| {
        var j = fi;
        while (j < obj.len and obj[j] != '{') : (j += 1) {}
        if (j < obj.len) {
            const start = j;
            var depth: i32 = 0;
            var in_str = false;
            var escape = false;
            while (j < obj.len) : (j += 1) {
                const c = obj[j];
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
                        break;
                    }
                }
            }
            fields_json = obj[start..j];
        }
    }

    const event_type = extractJsonString(fields_json, "event_type") orelse
        extractJsonString(fields_json, "event") orelse
        extractJsonString(fields_json, "action") orelse
        "unknown";

    // payload may be a nested object string or raw field
    var payload_json: []const u8 = fields_json;
    if (std.mem.indexOf(u8, fields_json, "\"payload\"")) |pi| {
        var j = pi;
        while (j < fields_json.len and fields_json[j] != '{' and fields_json[j] != '"') : (j += 1) {}
        if (j < fields_json.len and fields_json[j] == '{') {
            const start = j;
            var depth: i32 = 0;
            var in_str = false;
            var escape = false;
            while (j < fields_json.len) : (j += 1) {
                const c = fields_json[j];
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
                        break;
                    }
                }
            }
            payload_json = fields_json[start..j];
        } else if (extractJsonString(fields_json, "payload")) |p| {
            // payload stored as JSON string — use as-is if it looks like JSON
            if (p.len > 0 and (p[0] == '{' or p[0] == '[')) {
                payload_json = p;
            }
        }
    }

    return .{
        .stream = try allocator.dupe(u8, stream),
        .entry_id = try allocator.dupe(u8, entry),
        .fields_json = try allocator.dupe(u8, fields_json),
        .event_type = try allocator.dupe(u8, event_type),
        .payload_json = try allocator.dupe(u8, payload_json),
    };
}

test "encodePublishBody shapes bus json" {
    const body = try encodePublishBody(std.testing.allocator, .{
        .stream = "inbox",
        .event_type = "inbox.route",
        .sender = "bedd",
        .payload_json = "{\"ok\":true}",
    });
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "inbox") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"sender\":\"bedd\"") != null);
}

test "parseReadEvents extracts entries" {
    const sample =
        \\{"events":[{"stream":"inbox","entry_id":"1-0","fields":{"event_type":"inbox.route","payload":{"x":1}}}]}
    ;
    const events = try parseReadEvents(std.testing.allocator, sample);
    defer {
        for (events) |e| e.deinit(std.testing.allocator);
        std.testing.allocator.free(events);
    }
    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqualStrings("inbox", events[0].stream);
    try std.testing.expectEqualStrings("1-0", events[0].entry_id);
    try std.testing.expectEqualStrings("inbox.route", events[0].event_type);
}
