const std = @import("std");
const config = @import("../config.zig");
const ember = @import("../ember.zig");
const prometheus = @import("prometheus.zig");
const health = @import("health.zig");

/// Tiny admin HTTP server (health + metrics) for k8s probes.
pub const Server = struct {
    allocator: std.mem.Allocator,
    cfg: *const config.Config,
    metrics: *ember.Ember,
    port: u16,
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn start(self: *Server) !void {
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    pub fn shutdown(self: *Server) void {
        self.stop.store(true, .seq_cst);
        if (self.thread) |t| t.join();
    }

    fn run(self: *Server) void {
        const address = std.net.Address.parseIp4("0.0.0.0", self.port) catch return;
        var server = address.listen(.{ .reuse_address = true }) catch return;
        defer server.deinit();
        while (!self.stop.load(.seq_cst)) {
            const conn = server.accept() catch {
                std.time.sleep(20 * std.time.ns_per_ms);
                continue;
            };
            handleConn(self, conn) catch {};
        }
    }

    fn handleConn(self: *Server, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();
        var buf: [1024]u8 = undefined;
        const n = try conn.stream.read(&buf);
        const req = buf[0..n];
        if (std.mem.indexOf(u8, req, "GET /health") != null or std.mem.indexOf(u8, req, "GET /healthz") != null) {
            const body = try health.renderJson(self.cfg, self.allocator, true);
            defer self.allocator.free(body);
            try writeResponse(conn.stream, 200, "application/json", body);
            return;
        }
        if (std.mem.indexOf(u8, req, "GET /metrics") != null) {
            const body = try prometheus.render(self.metrics, self.allocator);
            defer self.allocator.free(body);
            try writeResponse(conn.stream, 200, "text/plain; version=0.0.4", body);
            return;
        }
        try writeResponse(conn.stream, 404, "text/plain", "not found");
    }

    fn writeResponse(stream: std.net.Stream, status: u16, ctype: []const u8, body: []const u8) !void {
        const reason: []const u8 = if (status == 200) "OK" else "Error";
        try stream.writer().print(
            "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ status, reason, ctype, body.len, body },
        );
    }
};
