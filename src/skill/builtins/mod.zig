pub const redact = @import("redact.zig");
pub const fingerprint = @import("fingerprint.zig");
pub const schema_gate = @import("schema_gate.zig");
pub const drop_fields = @import("drop_fields.zig");

pub const all_names = [_][]const u8{
    redact.skill_name,
    fingerprint.skill_name,
    schema_gate.skill_name,
    drop_fields.skill_name,
};
