const std = @import("std");
const posix = std.posix;

/// In-process fake HTTP bus HTTP API for integration tests / local demos.
/// Supports /healthz, /readyz, /v1/publish, /v1/read, /v1/ack.
pub const MockSidecar = struct {
    allocator: std.mem.Allocator,
    port: u16,
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    mutex: std.Thread.Mutex = .{},
    /// stream -> list of pending JSON field objects (as owned strings)
    streams: std.StringHashMap(std.ArrayList([]u8)),
    next_id: u64 = 1,
    published: u64 = 0,
    acked: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, port: u16) MockSidecar {
        return .{
            .allocator = allocator,
            .port = port,
            .streams = std.StringHashMap(std.ArrayList([]u8)).init(allocator),
        };
    }

    pub fn deinit(self: *MockSidecar) void {
        self.stop.store(true, .seq_cst);
        self.kick();
        if (self.thread) |t| t.join();
        var it = self.streams.iterator();
        while (it.next()) |e| {
            for (e.value_ptr.items) |msg| self.allocator.free(msg);
            e.value_ptr.deinit();
            self.allocator.free(e.key_ptr.*);
        }
        self.streams.deinit();
    }

    pub fn start(self: *MockSidecar) !void {
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        // Wait until the listener is accepting (avoid race with first client).
        var i: u32 = 0;
        while (i < 50) : (i += 1) {
            const addr = std.net.Address.parseIp4("127.0.0.1", self.port) catch break;
            if (std.net.tcpConnectToAddress(addr)) |s| {
                s.close();
                break;
            } else |_| {
                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }
    }

    fn kick(self: *MockSidecar) void {
        const addr = std.net.Address.parseIp4("127.0.0.1", self.port) catch return;
        if (std.net.tcpConnectToAddress(addr)) |s| s.close() else |_| {}
    }

    /// Seed a stream with a payload for consumers to read.
    pub fn seed(self: *MockSidecar, stream: []const u8, event_type: []const u8, payload_json: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const gop = try self.streams.getOrPut(stream);
        if (!gop.found_existing) {
            gop.key_ptr.* = try self.allocator.dupe(u8, stream);
            gop.value_ptr.* = std.ArrayList([]u8).init(self.allocator);
        }
        const fields = try std.fmt.allocPrint(
            self.allocator,
            \\{{"event_type":"{s}","payload":{s}}}
        ,
            .{ event_type, payload_json },
        );
        try gop.value_ptr.append(fields);
    }

    fn run(self: *MockSidecar) void {
        const address = std.net.Address.parseIp4("127.0.0.1", self.port) catch return;
        var server = address.listen(.{ .reuse_address = true }) catch return;
        defer server.deinit();
        // Accept timeout so stop+kick can unwind promptly.
        setRecvTimeout(server.stream.handle, 200) catch {};
        while (!self.stop.load(.seq_cst)) {
            const conn = server.accept() catch {
                continue;
            };
            if (self.stop.load(.seq_cst)) {
                conn.stream.close();
                break;
            }
            self.handle(conn) catch {};
        }
    }

    fn handle(self: *MockSidecar, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();
        setRecvTimeout(conn.stream.handle, 500) catch {};

        var buf: [64 * 1024]u8 = undefined;
        const total = try readHttpRequest(conn.stream, &buf);
        if (total == 0) return;
        const req = buf[0..total];

        if (std.mem.indexOf(u8, req, "GET /healthz") != null) {
            try respond(conn.stream, 200, "{\"healthy\":true,\"service\":\"mock-sugar-glider\"}");
            return;
        }
        if (std.mem.indexOf(u8, req, "GET /readyz") != null) {
            try respond(conn.stream, 200, "{\"ready\":true,\"redis_status\":\"ok\"}");
            return;
        }
        if (std.mem.indexOf(u8, req, "POST /v1/publish") != null) {
            self.mutex.lock();
            self.published += 1;
            const id = self.next_id;
            self.next_id += 1;
            self.mutex.unlock();
            var id_buf: [64]u8 = undefined;
            const id_json = try std.fmt.bufPrint(&id_buf, "{{\"entry_id\":\"{d}-0\"}}", .{id});
            try respond(conn.stream, 200, id_json);
            return;
        }
        if (std.mem.indexOf(u8, req, "POST /v1/read") != null) {
            const body = bodyOf(req) orelse "";
            const stream = extractString(body, "stream") orelse extractString(req, "stream") orelse {
                try respond(conn.stream, 400, "{\"error\":\"stream required\"}");
                return;
            };
            self.mutex.lock();
            defer self.mutex.unlock();
            var out = std.ArrayList(u8).init(self.allocator);
            defer out.deinit();
            try out.appendSlice("{\"events\":[");
            if (self.streams.getPtr(stream)) |list| {
                var first = true;
                var delivered: usize = 0;
                while (list.items.len > 0 and delivered < 10) : (delivered += 1) {
                    const fields = list.orderedRemove(0);
                    defer self.allocator.free(fields);
                    const eid = self.next_id;
                    self.next_id += 1;
                    if (!first) try out.append(',');
                    first = false;
                    try out.writer().print(
                        \\{{"stream":"{s}","entry_id":"{d}-0","fields":{s}}}
                    ,
                        .{ stream, eid, fields },
                    );
                }
            }
            try out.appendSlice("]}");
            try respond(conn.stream, 200, out.items);
            return;
        }
        if (std.mem.indexOf(u8, req, "POST /v1/ack") != null) {
            self.mutex.lock();
            self.acked += 1;
            self.mutex.unlock();
            try respond(conn.stream, 200, "{\"acked\":1}");
            return;
        }
        try respond(conn.stream, 404, "{\"error\":\"not found\"}");
    }
};

fn setRecvTimeout(fd: posix.socket_t, ms: u32) !void {
    const tv = posix.timeval{
        .tv_sec = @intCast(ms / 1000),
        .tv_usec = @intCast((ms % 1000) * 1000),
    };
    try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&tv));
}

/// Assemble one HTTP/1.x request without blocking forever on keep-alive peers.
fn readHttpRequest(stream: std.net.Stream, buf: []u8) !usize {
    var total: usize = 0;
    var idle_timeouts: u8 = 0;
    while (total < buf.len and idle_timeouts < 3) {
        const n = stream.read(buf[total..]) catch |err| switch (err) {
            error.WouldBlock, error.ConnectionTimedOut => {
                idle_timeouts += 1;
                if (headerEnd(buf[0..total])) |_| break;
                continue;
            },
            else => return err,
        };
        if (n == 0) break;
        total += n;
        idle_timeouts = 0;

        if (headerEnd(buf[0..total])) |hend| {
            const body_have = total - hend;
            if (contentLength(buf[0..total])) |cl| {
                if (body_have >= cl) break;
                // Keep reading until Content-Length is satisfied (or timeout above).
            } else {
                // No Content-Length: if we already have a body, or method is bodyless, stop.
                if (body_have > 0 or isBodyless(buf[0..total])) break;
            }
        }
    }
    return total;
}

fn isBodyless(req: []const u8) bool {
    return std.mem.startsWith(u8, req, "GET ") or
        std.mem.startsWith(u8, req, "HEAD ") or
        std.mem.startsWith(u8, req, "DELETE ");
}

fn headerEnd(req: []const u8) ?usize {
    if (std.mem.indexOf(u8, req, "\r\n\r\n")) |i| return i + 4;
    if (std.mem.indexOf(u8, req, "\n\n")) |i| return i + 2;
    return null;
}

fn contentLength(req: []const u8) ?usize {
    // Case-insensitive header scan.
    var i: usize = 0;
    while (i + 15 < req.len) : (i += 1) {
        if (!std.ascii.eqlIgnoreCase(req[i..][0..15], "content-length:")) continue;
        var j = i + 15;
        while (j < req.len and req[j] == ' ') : (j += 1) {}
        const start = j;
        while (j < req.len and req[j] >= '0' and req[j] <= '9') : (j += 1) {}
        if (start == j) return null;
        return std.fmt.parseInt(usize, req[start..j], 10) catch null;
    }
    return null;
}

fn bodyOf(req: []const u8) ?[]const u8 {
    const end = headerEnd(req) orelse return null;
    const body = req[end..];
    return if (body.len == 0) null else body;
}

fn extractString(json: []const u8, key: []const u8) ?[]const u8 {
    const jsonx = @import("jsonx.zig");
    return jsonx.getStringField(json, key);
}

fn respond(stream: std.net.Stream, status: u16, body: []const u8) !void {
    const reason: []const u8 = if (status == 200) "OK" else "Error";
    try stream.writer().print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
        .{ status, reason, body.len, body },
    );
}

test "mock sidecar publish health" {
    var mock = MockSidecar.init(std.testing.allocator, 19108);
    try mock.start();
    defer mock.deinit();

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();
    var body = std.ArrayList(u8).init(std.testing.allocator);
    defer body.deinit();
    const res = try client.fetch(.{
        .location = .{ .url = "http://127.0.0.1:19108/healthz" },
        .method = .GET,
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 4096,
    });
    try std.testing.expect(res.status == .ok);
    try std.testing.expect(std.mem.indexOf(u8, body.items, "healthy") != null);
}

test "mock sidecar read returns seeded event" {
    var mock = MockSidecar.init(std.testing.allocator, 19109);
    try mock.start();
    defer mock.deinit();
    try mock.seed("inbox", "inbox.route", "{\"x\":1}");

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();
    var body = std.ArrayList(u8).init(std.testing.allocator);
    defer body.deinit();
    const payload =
        \\{"stream":"inbox","consumer_group":"g","consumer_name":"c","count":10,"block_ms":100}
    ;
    const res = try client.fetch(.{
        .location = .{ .url = "http://127.0.0.1:19109/v1/read" },
        .method = .POST,
        .payload = payload,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 64 * 1024,
    });
    try std.testing.expect(res.status == .ok);
    try std.testing.expect(std.mem.indexOf(u8, body.items, "inbox") != null);
    try std.testing.expect(std.mem.indexOf(u8, body.items, "\"x\":1") != null);
}
