const std = @import("std");
const config = @import("../config.zig");
const ember = @import("../ember.zig");
const prometheus = @import("prometheus.zig");
const health = @import("health.zig");
const bus = @import("../bus.zig");
const skill = @import("../skill/mod.zig");
const version = @import("../util/version.zig");

/// Tiny admin HTTP server (health + metrics + skills) for k8s probes.
pub const Server = struct {
    allocator: std.mem.Allocator,
    cfg: *const config.Config,
    metrics: *ember.Ember,
    bus_client: ?*bus.Client = null,
    port: u16,
    thread: ?std.Thread = null,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn start(self: *Server) !void {
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    pub fn shutdown(self: *Server) void {
        self.stop.store(true, .seq_cst);
        // Unblock accept with a self-connect
        if (std.net.tcpConnectToAddress(std.net.Address.parseIp4("127.0.0.1", self.port) catch return)) |stream| {
            stream.close();
        } else |_| {}
        if (self.thread) |t| t.join();
    }

    fn run(self: *Server) void {
        const address = std.net.Address.parseIp4("0.0.0.0", self.port) catch return;
        var server = address.listen(.{ .reuse_address = true }) catch |err| {
            std.log.err("admin listen failed on {d}: {s}", .{ self.port, @errorName(err) });
            return;
        };
        defer server.deinit();
        std.log.info("admin listening on :{d}", .{self.port});

        while (!self.stop.load(.seq_cst)) {
            const conn = server.accept() catch {
                std.time.sleep(20 * std.time.ns_per_ms);
                continue;
            };
            if (self.stop.load(.seq_cst)) {
                conn.stream.close();
                break;
            }
            handleConn(self, conn) catch {};
        }
    }

    fn busOk(self: *Server) bool {
        const client = self.bus_client orelse return false;
        return client.health() catch false;
    }

    fn handleConn(self: *Server, conn: std.net.Server.Connection) !void {
        defer conn.stream.close();
        var buf: [2048]u8 = undefined;
        const n = try conn.stream.read(&buf);
        if (n == 0) return;
        const req = buf[0..n];

        if (std.mem.indexOf(u8, req, "GET /healthz") != null or std.mem.indexOf(u8, req, "GET /health ") != null) {
            const ok = self.busOk() or self.bus_client == null;
            const body = try health.renderJson(self.cfg, self.allocator, ok);
            defer self.allocator.free(body);
            try writeResponse(conn.stream, if (ok) 200 else 503, "application/json", body);
            return;
        }
        if (std.mem.indexOf(u8, req, "GET /readyz") != null or std.mem.indexOf(u8, req, "GET /ready ") != null) {
            const ok = self.busOk();
            const body = try std.fmt.allocPrint(
                self.allocator,
                \\{{"ready":{},"bus_ok":{},"version":"{s}"}}
            ,
                .{ ok, ok, version.semver },
            );
            defer self.allocator.free(body);
            try writeResponse(conn.stream, if (ok) 200 else 503, "application/json", body);
            return;
        }
        if (std.mem.indexOf(u8, req, "GET /metrics") != null) {
            const body = try prometheus.render(self.metrics, self.allocator);
            defer self.allocator.free(body);
            try writeResponse(conn.stream, 200, "text/plain; version=0.0.4", body);
            return;
        }
        if (std.mem.indexOf(u8, req, "GET /skills") != null) {
            var list = std.ArrayList(u8).init(self.allocator);
            defer list.deinit();
            try list.appendSlice("{\"skills\":[");
            var first = true;
            // Collect via temporary buffer from listBuiltins text
            var tmp = std.ArrayList(u8).init(self.allocator);
            defer tmp.deinit();
            try skill.Registry.listBuiltins(tmp.writer());
            // Parse lines "  - name (native)"
            var lines = std.mem.splitScalar(u8, tmp.items, '\n');
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t-");
                if (trimmed.len == 0) continue;
                const name_end = std.mem.indexOf(u8, trimmed, " ") orelse trimmed.len;
                const name = trimmed[0..name_end];
                if (!first) try list.append(',');
                first = false;
                try list.writer().print("\"{s}\"", .{name});
            }
            try list.appendSlice("]}");
            try writeResponse(conn.stream, 200, "application/json", list.items);
            return;
        }
        if (std.mem.indexOf(u8, req, "GET /version") != null) {
            const body = try std.fmt.allocPrint(
                self.allocator,
                \\{{"version":"{s}","codename":"{s}","abi":"{s}"}}
            ,
                .{ version.semver, version.codename, version.abi },
            );
            defer self.allocator.free(body);
            try writeResponse(conn.stream, 200, "application/json", body);
            return;
        }
        try writeResponse(conn.stream, 404, "text/plain", "not found");
    }

    fn writeResponse(stream: std.net.Stream, status: u16, ctype: []const u8, body: []const u8) !void {
        const reason: []const u8 = switch (status) {
            200 => "OK",
            503 => "Service Unavailable",
            else => "Error",
        };
        try stream.writer().print(
            "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ status, reason, ctype, body.len, body },
        );
    }
};
