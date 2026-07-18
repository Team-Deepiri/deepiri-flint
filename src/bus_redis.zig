const std = @import("std");
const bus = @import("bus.zig");

/// Minimal Redis Streams client (RESP2) for `BEDD_BUS_URL=redis://host:port[/db]`.
/// Skips the HTTP sidecar hop — the main real-world latency win for `bedd serve`.

pub const RedisError = error{
    ConnectFailed,
    Protocol,
    IoFailed,
    BadReply,
    OutOfMemory,
    InvalidUrl,
};

pub const Conn = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    reader_buf: std.ArrayList(u8),
    host: []const u8,
    port: u16,
    db: u8,

    pub fn connect(allocator: std.mem.Allocator, url: []const u8) RedisError!Conn {
        const parsed = try parseRedisUrl(url);
        var list = std.net.getAddressList(allocator, parsed.host, parsed.port) catch return RedisError.ConnectFailed;
        defer list.deinit();
        if (list.addrs.len == 0) return RedisError.ConnectFailed;

        const stream = std.net.tcpConnectToAddress(list.addrs[0]) catch return RedisError.ConnectFailed;
        var conn: Conn = .{
            .allocator = allocator,
            .stream = stream,
            .reader_buf = std.ArrayList(u8).init(allocator),
            .host = try allocator.dupe(u8, parsed.host),
            .port = parsed.port,
            .db = parsed.db,
        };
        errdefer conn.deinit();

        if (parsed.db != 0) {
            var db_buf: [8]u8 = undefined;
            const db_s = std.fmt.bufPrint(&db_buf, "{d}", .{parsed.db}) catch return RedisError.Protocol;
            const sel = try conn.cmdSimple(&.{ "SELECT", db_s });
            conn.allocator.free(sel);
        }

        const pong = try conn.cmdSimple(&.{"PING"});
        defer conn.allocator.free(pong);
        return conn;
    }

    pub fn deinit(self: *Conn) void {
        self.stream.close();
        self.reader_buf.deinit();
        self.allocator.free(self.host);
    }

    pub fn ping(self: *Conn) bool {
        const r = self.cmdSimple(&.{"PING"}) catch return false;
        defer self.allocator.free(r);
        return std.mem.eql(u8, r, "PONG") or std.mem.indexOf(u8, r, "PONG") != null;
    }

    pub fn publish(self: *Conn, req: bus.PublishRequest) RedisError!bus.PublishResult {
        const id = try self.cmdSimple(&.{
            "XADD",
            req.stream,
            "*",
            "event_type",
            req.event_type,
            "sender",
            req.sender,
            "priority",
            req.priority,
            "payload",
            req.payload_json,
        });
        return .{ .entry_id = id, .queued = false };
    }

    pub fn ensureGroup(self: *Conn, stream_name: []const u8, group: []const u8) void {
        // Ignore BUSYGROUP / other create races.
        if (self.cmdSimple(&.{ "XGROUP", "CREATE", stream_name, group, "$", "MKSTREAM" })) |r| {
            self.allocator.free(r);
        } else |_| {}
    }

    pub fn read(self: *Conn, req: bus.ReadRequest) RedisError![]bus.StreamEvent {
        self.ensureGroup(req.stream, req.consumer_group);

        var count_buf: [16]u8 = undefined;
        const count_s = std.fmt.bufPrint(&count_buf, "{d}", .{req.count}) catch return RedisError.Protocol;
        var block_buf: [16]u8 = undefined;
        const block_s = std.fmt.bufPrint(&block_buf, "{d}", .{req.block_ms}) catch return RedisError.Protocol;

        const raw = try self.cmdRaw(&.{
            "XREADGROUP",
            "GROUP",
            req.consumer_group,
            req.consumer_name,
            "COUNT",
            count_s,
            "BLOCK",
            block_s,
            "STREAMS",
            req.stream,
            ">",
        });
        defer self.allocator.free(raw);
        return try parseXReadReply(self.allocator, raw, req.stream);
    }

    pub fn ack(self: *Conn, stream_name: []const u8, group: []const u8, ids: []const []const u8) RedisError!i64 {
        if (ids.len == 0) return 0;
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        try args.appendSlice(&.{ "XACK", stream_name, group });
        for (ids) |id| try args.append(id);
        const r = try self.cmdSimple(args.items);
        defer self.allocator.free(r);
        return std.fmt.parseInt(i64, r, 10) catch @intCast(ids.len);
    }

    fn cmdSimple(self: *Conn, parts: []const []const u8) RedisError![]u8 {
        const raw = try self.cmdRaw(parts);
        if (raw.len == 0) {
            self.allocator.free(raw);
            return RedisError.BadReply;
        }
        if (raw[0] == '-') {
            self.allocator.free(raw);
            return RedisError.BadReply;
        }
        if (raw[0] == '+') {
            const end = std.mem.indexOf(u8, raw, "\r\n") orelse raw.len;
            const out = try self.allocator.dupe(u8, raw[1..end]);
            self.allocator.free(raw);
            return out;
        }
        if (raw[0] == ':') {
            const end = std.mem.indexOf(u8, raw, "\r\n") orelse raw.len;
            const out = try self.allocator.dupe(u8, raw[1..end]);
            self.allocator.free(raw);
            return out;
        }
        if (raw[0] == '$') {
            const nl = std.mem.indexOf(u8, raw, "\r\n") orelse {
                self.allocator.free(raw);
                return RedisError.Protocol;
            };
            const n = std.fmt.parseInt(i64, raw[1..nl], 10) catch {
                self.allocator.free(raw);
                return RedisError.Protocol;
            };
            if (n < 0) {
                self.allocator.free(raw);
                return try self.allocator.dupe(u8, "");
            }
            const start = nl + 2;
            const end = start + @as(usize, @intCast(n));
            if (end > raw.len) {
                self.allocator.free(raw);
                return RedisError.Protocol;
            }
            const out = try self.allocator.dupe(u8, raw[start..end]);
            self.allocator.free(raw);
            return out;
        }
        // Array / multi — caller owns (e.g. XREADGROUP).
        return raw;
    }

    fn cmdRaw(self: *Conn, parts: []const []const u8) RedisError![]u8 {
        var req = std.ArrayList(u8).init(self.allocator);
        defer req.deinit();
        try req.writer().print("*{d}\r\n", .{parts.len});
        for (parts) |p| {
            try req.writer().print("${d}\r\n{s}\r\n", .{ p.len, p });
        }
        self.stream.writeAll(req.items) catch return RedisError.IoFailed;
        return try self.readReply();
    }

    fn readReply(self: *Conn) RedisError![]u8 {
        self.reader_buf.clearRetainingCapacity();
        var tmp: [4096]u8 = undefined;
        while (true) {
            const n = self.stream.read(&tmp) catch return RedisError.IoFailed;
            if (n == 0) return RedisError.IoFailed;
            try self.reader_buf.appendSlice(tmp[0..n]);
            if (respComplete(self.reader_buf.items)) break;
            if (self.reader_buf.items.len > 8 * 1024 * 1024) return RedisError.Protocol;
        }
        return try self.allocator.dupe(u8, self.reader_buf.items);
    }
};

const ParsedUrl = struct { host: []const u8, port: u16, db: u8 };

pub fn parseRedisUrl(url: []const u8) RedisError!ParsedUrl {
    const prefix = "redis://";
    if (!std.mem.startsWith(u8, url, prefix) and !std.mem.startsWith(u8, url, "rediss://"))
        return RedisError.InvalidUrl;
    var rest = if (std.mem.startsWith(u8, url, "rediss://")) url["rediss://".len..] else url[prefix.len..];
    if (std.mem.indexOf(u8, rest, "@")) |at| rest = rest[at + 1 ..];

    var host = rest;
    var port: u16 = 6379;
    var db: u8 = 0;

    if (std.mem.indexOf(u8, rest, "/")) |slash| {
        host = rest[0..slash];
        const db_s = rest[slash + 1 ..];
        if (db_s.len > 0) db = std.fmt.parseInt(u8, db_s, 10) catch 0;
    }
    if (std.mem.lastIndexOfScalar(u8, host, ':')) |colon| {
        port = std.fmt.parseInt(u16, host[colon + 1 ..], 10) catch 6379;
        host = host[0..colon];
    }
    if (host.len == 0) host = "127.0.0.1";
    return .{ .host = host, .port = port, .db = db };
}

pub fn isRedisUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "redis://") or std.mem.startsWith(u8, url, "rediss://");
}

fn respComplete(buf: []const u8) bool {
    if (buf.len == 0) return false;
    var i: usize = 0;
    return consumeResp(buf, &i);
}

fn consumeResp(buf: []const u8, i: *usize) bool {
    if (i.* >= buf.len) return false;
    const t = buf[i.*];
    i.* += 1;
    switch (t) {
        '+', '-', ':' => {
            while (i.* + 1 < buf.len) {
                if (buf[i.*] == '\r' and buf[i.* + 1] == '\n') {
                    i.* += 2;
                    return true;
                }
                i.* += 1;
            }
            return false;
        },
        '$' => {
            const nl = indexCrLf(buf, i.*) orelse return false;
            const n = std.fmt.parseInt(i64, buf[i.*..nl], 10) catch return false;
            i.* = nl + 2;
            if (n < 0) return true;
            const need = @as(usize, @intCast(n)) + 2;
            if (i.* + need > buf.len) return false;
            i.* += need;
            return true;
        },
        '*' => {
            const nl = indexCrLf(buf, i.*) orelse return false;
            const n = std.fmt.parseInt(i64, buf[i.*..nl], 10) catch return false;
            i.* = nl + 2;
            if (n < 0) return true;
            var k: i64 = 0;
            while (k < n) : (k += 1) {
                if (!consumeResp(buf, i)) return false;
            }
            return true;
        },
        else => return false,
    }
}

fn indexCrLf(buf: []const u8, start: usize) ?usize {
    var i = start;
    while (i + 1 < buf.len) : (i += 1) {
        if (buf[i] == '\r' and buf[i + 1] == '\n') return i;
    }
    return null;
}

fn parseXReadReply(allocator: std.mem.Allocator, raw: []const u8, default_stream: []const u8) RedisError![]bus.StreamEvent {
    if (std.mem.startsWith(u8, raw, "*-1") or std.mem.eql(u8, std.mem.trim(u8, raw, " \r\n"), "$-1")) {
        return try allocator.alloc(bus.StreamEvent, 0);
    }

    var list = std.ArrayList(bus.StreamEvent).init(allocator);
    errdefer {
        for (list.items) |e| e.deinit(allocator);
        list.deinit();
    }

    var bulks = std.ArrayList([]const u8).init(allocator);
    defer bulks.deinit();
    try collectBulks(raw, &bulks);
    if (bulks.items.len < 2) return try list.toOwnedSlice();

    var i: usize = 0;
    while (i < bulks.items.len) {
        const stream_name = blk: {
            if (i < bulks.items.len and !looksLikeEntryId(bulks.items[i])) {
                const s = bulks.items[i];
                i += 1;
                break :blk s;
            }
            break :blk default_stream;
        };
        if (i >= bulks.items.len) break;
        const entry_id = bulks.items[i];
        i += 1;

        var event_type: []const u8 = "unknown";
        var payload: []const u8 = "{}";
        var fields = std.ArrayList(u8).init(allocator);
        defer fields.deinit();
        try fields.append('{');
        var first = true;

        while (i + 1 < bulks.items.len) {
            if (looksLikeEntryId(bulks.items[i]) and !looksLikeEntryId(bulks.items[i + 1])) break;
            // New stream name (not an id) ends this message's fields when odd leftover
            if (!looksLikeEntryId(bulks.items[i]) and i > 0 and looksLikeStreamBoundary(bulks.items, i)) break;

            const key = bulks.items[i];
            const val = bulks.items[i + 1];
            i += 2;
            if (std.mem.eql(u8, key, "event_type") or std.mem.eql(u8, key, "event")) event_type = val;
            if (std.mem.eql(u8, key, "payload")) payload = val;
            if (!first) try fields.append(',');
            first = false;
            try fields.writer().print("\"{s}\":", .{key});
            if (val.len > 0 and (val[0] == '{' or val[0] == '[')) {
                try fields.appendSlice(val);
            } else {
                try fields.writer().print("\"{s}\"", .{val});
            }
            if (i < bulks.items.len and looksLikeEntryId(bulks.items[i])) break;
        }
        try fields.append('}');

        const payload_owned = if (payload.len > 0 and (payload[0] == '{' or payload[0] == '['))
            try allocator.dupe(u8, payload)
        else
            try allocator.dupe(u8, fields.items);

        try list.append(.{
            .stream = try allocator.dupe(u8, stream_name),
            .entry_id = try allocator.dupe(u8, entry_id),
            .fields_json = try fields.toOwnedSlice(),
            .event_type = try allocator.dupe(u8, event_type),
            .payload_json = payload_owned,
        });
    }

    return try list.toOwnedSlice();
}

fn looksLikeStreamBoundary(bulks: []const []const u8, i: usize) bool {
    _ = bulks;
    _ = i;
    return false;
}

fn looksLikeEntryId(s: []const u8) bool {
    const dash = std.mem.indexOfScalar(u8, s, '-') orelse return false;
    if (dash == 0 or dash + 1 >= s.len) return false;
    for (s[0..dash]) |c| if (c < '0' or c > '9') return false;
    for (s[dash + 1 ..]) |c| if (c < '0' or c > '9') return false;
    return true;
}

fn collectBulks(raw: []const u8, out: *std.ArrayList([]const u8)) RedisError!void {
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '$') {
            const nl = indexCrLf(raw, i + 1) orelse return RedisError.Protocol;
            const n = std.fmt.parseInt(i64, raw[i + 1 .. nl], 10) catch return RedisError.Protocol;
            i = nl + 2;
            if (n < 0) continue;
            const end = i + @as(usize, @intCast(n));
            if (end > raw.len) return RedisError.Protocol;
            try out.append(raw[i..end]);
            i = end + 2;
            continue;
        }
        i += 1;
    }
}

test "parseRedisUrl" {
    const p = try parseRedisUrl("redis://127.0.0.1:6379/0");
    try std.testing.expectEqualStrings("127.0.0.1", p.host);
    try std.testing.expectEqual(@as(u16, 6379), p.port);
}

test "respComplete simple" {
    try std.testing.expect(respComplete("+PONG\r\n"));
    try std.testing.expect(respComplete("$4\r\nPONG\r\n"));
    try std.testing.expect(!respComplete("$4\r\nPO"));
}
