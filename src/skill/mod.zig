const std = @import("std");
const wasm_host = @import("wasm_host.zig");
const extra = @import("builtins/mod.zig");

pub const SkillError = error{
    SkillFailed,
    SkillNotFound,
    OutOfMemory,
    WasmError,
};

pub const SkillResult = struct {
    payload_json: []u8,
    event_type_override: ?[]const u8 = null,

    pub fn deinit(self: SkillResult, allocator: std.mem.Allocator) void {
        allocator.free(self.payload_json);
        if (self.event_type_override) |e| allocator.free(e);
    }
};

pub const SkillContext = struct {
    allocator: std.mem.Allocator,
    stream: []const u8,
    entry_id: []const u8,
    event_type: []const u8,
};

pub const SkillFn = *const fn (ctx: SkillContext, input_json: []const u8) SkillError!SkillResult;

pub const NativeSkill = struct {
    name: []const u8,
    run: SkillFn,
};

fn echoSkill(ctx: SkillContext, input_json: []const u8) SkillError!SkillResult {
    const out = std.fmt.allocPrint(
        ctx.allocator,
        \\{{"echo":true,"event_type":"{s}","input":{s}}}
    ,
        .{ ctx.event_type, input_json },
    ) catch return SkillError.OutOfMemory;
    return .{ .payload_json = out };
}

fn passthroughSkill(ctx: SkillContext, input_json: []const u8) SkillError!SkillResult {
    const out = ctx.allocator.dupe(u8, input_json) catch return SkillError.OutOfMemory;
    return .{ .payload_json = out };
}

const builtins = [_]NativeSkill{
    .{ .name = "echo", .run = echoSkill },
    .{ .name = "passthrough", .run = passthroughSkill },
    .{ .name = "redact", .run = extra.redact.run },
    .{ .name = "fingerprint", .run = extra.fingerprint.run },
    .{ .name = "schema_gate", .run = extra.schema_gate.run },
    .{ .name = "drop_fields", .run = extra.drop_fields.run },
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    wasm_cache: std.StringHashMap(wasm_host.WasmSkill),

    pub fn init(allocator: std.mem.Allocator, skills_dir: []const u8) Registry {
        return .{
            .allocator = allocator,
            .skills_dir = skills_dir,
            .wasm_cache = std.StringHashMap(wasm_host.WasmSkill).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        var it = self.wasm_cache.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.wasm_cache.deinit();
    }

    pub fn listBuiltins(writer: anytype) !void {
        for (builtins) |s| {
            try writer.print("  - {s} (native)\n", .{s.name});
        }
    }

    /// O(1)-ish builtin resolve for filter hot path.
    pub fn lookupBuiltin(name: []const u8) ?SkillFn {
        for (builtins) |s| {
            if (std.mem.eql(u8, s.name, name)) return s.run;
        }
        return null;
    }

    pub fn run(self: *Registry, name: []const u8, ctx: SkillContext, input_json: []const u8) SkillError!SkillResult {
        if (lookupBuiltin(name)) |fn_ptr| {
            return fn_ptr(ctx, input_json);
        }

        if (self.wasm_cache.getPtr(name)) |skill| {
            return skill.run(ctx, input_json);
        }

        const path_a = std.fmt.allocPrint(self.allocator, "{s}/{s}.wasm", .{ self.skills_dir, name }) catch
            return SkillError.OutOfMemory;
        defer self.allocator.free(path_a);
        const path_b = std.fmt.allocPrint(self.allocator, "{s}/{s}_skill.wasm", .{ self.skills_dir, name }) catch
            return SkillError.OutOfMemory;
        defer self.allocator.free(path_b);

        const path = if (fileExists(path_a)) path_a else if (fileExists(path_b)) path_b else {
            return SkillError.SkillNotFound;
        };

        var skill = wasm_host.WasmSkill.load(self.allocator, path) catch return SkillError.WasmError;
        const key = self.allocator.dupe(u8, name) catch {
            skill.deinit();
            return SkillError.OutOfMemory;
        };
        self.wasm_cache.put(key, skill) catch {
            self.allocator.free(key);
            skill.deinit();
            return SkillError.OutOfMemory;
        };
        return self.wasm_cache.getPtr(name).?.run(ctx, input_json);
    }
};

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

test "echo skill wraps input" {
    var reg = Registry.init(std.testing.allocator, ".");
    defer reg.deinit();
    const ctx = SkillContext{
        .allocator = std.testing.allocator,
        .stream = "inbox",
        .entry_id = "1-0",
        .event_type = "demo.event",
    };
    const result = try reg.run("echo", ctx, "{\"a\":1}");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, result.payload_json, "\"echo\":true") != null);
}

test "wasm echo_skill loads when artifact present" {
    var reg = Registry.init(std.testing.allocator, "zig-out/skills");
    defer reg.deinit();
    if (!fileExists("zig-out/skills/echo_skill.wasm")) return;
    const ctx = SkillContext{
        .allocator = std.testing.allocator,
        .stream = "inbox",
        .entry_id = "1-0",
        .event_type = "demo.event",
    };
    const result = try reg.run("echo_skill", ctx, "{\"wasm\":1}");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, result.payload_json, "wasm") != null);
}
