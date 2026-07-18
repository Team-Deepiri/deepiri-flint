const std = @import("std");
const bus = @import("bus.zig");

pub fn publishDeadLetter(
    client: *bus.Client,
    sender: []const u8,
    dlq_stream: []const u8,
    source_stream: []const u8,
    entry_id: []const u8,
    error_name: []const u8,
    payload_json: []const u8,
) !void {
    const wrapped = try std.fmt.allocPrint(
        client.allocator,
        \\{{"schemaVersion":"bedd.dlq.v1","source_stream":"{s}","entry_id":"{s}","error":"{s}","payload":{s}}}
    ,
        .{ source_stream, entry_id, error_name, payload_json },
    );
    defer client.allocator.free(wrapped);
    const res = try client.publish(.{
        .stream = dlq_stream,
        .event_type = "bedd.dlq",
        .sender = sender,
        .payload_json = wrapped,
    });
    defer res.deinit(client.allocator);
}
