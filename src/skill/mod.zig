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
    /// Owned JSON payload produced by the skill.
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

fn pressureTagSkill(ctx: SkillContext, input_json: []const u8) SkillError!SkillResult {
    const out = std.fmt.allocPrint(
        ctx.allocator,
        \\{{"tagged_by":"flint","source_stream":"{s}","pressure":{s}}}
    ,
        .{ ctx.stream, input_json },
    ) catch return SkillError.OutOfMemory;
    return .{ .payload_json = out };
}

fn documentFanoutSkill(ctx: SkillContext, input_json: []const u8) SkillError!SkillResult {
    const out = std.fmt.allocPrint(
        ctx.allocator,
        \\{{"kind":"document_fanout","document_route":true,"source_entry":"{s}","body":{s}}}
    ,
        .{ ctx.entry_id, input_json },
    ) catch return SkillError.OutOfMemory;
    return .{
        .payload_json = out,
        .event_type_override = ctx.allocator.dupe(u8, "flint.document.fanout") catch null,
    };
}

const builtins = [_]NativeSkill{
    .{ .name = "echo", .run = echoSkill },
    .{ .name = "passthrough", .run = passthroughSkill },
    .{ .name = "pressure_tag", .run = pressureTagSkill },
    .{ .name = "document_fanout", .run = documentFanoutSkill },
    .{ .name = "redact", .run = extra.redact.run },
    .{ .name = "fingerprint", .run = extra.fingerprint.run },
    .{ .name = "schema_gate", .run = extra.schema_gate.run },
    .{ .name = "training_enrich", .run = extra.training_enrich.run },
    .{ .name = "splice_tag", .run = extra.splice_tag.run },
    .{ .name = "invalidation_ack", .run = extra.invalidation_ack.run },
    .{ .name = "model_reload_hook", .run = extra.model_reload_hook.run },
    .{ .name = "inference_annotate", .run = extra.inference_annotate.run },
    .{ .name = "agi_decision_wrap", .run = extra.agi_decision_wrap.run },
    .{ .name = "metrics_sample", .run = extra.metrics_sample.run },
    .{ .name = "vectorize_normalize", .run = extra.vectorize_normalize.run },
    .{ .name = "structured_compact", .run = extra.structured_compact.run },
    .{ .name = "artifact_claim", .run = extra.artifact_claim.run },
    .{ .name = "helox_raw_tag", .run = extra.helox_raw_tag.run },
    .{ .name = "helox_structured_tag", .run = extra.helox_structured_tag.run },
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

    pub fn run(self: *Registry, name: []const u8, ctx: SkillContext, input_json: []const u8) SkillError!SkillResult {
        for (builtins) |s| {
            if (std.mem.eql(u8, s.name, name)) {
                return s.run(ctx, input_json);
            }
        }

        // Try WASM: skills_dir/<name>.wasm or skills_dir/<name>_skill.wasm
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
        .stream = "document.artifacts",
        .entry_id = "1-0",
        .event_type = "document.artifacts.route",
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
        .stream = "document.artifacts",
        .entry_id = "1-0",
        .event_type = "document.artifacts.route",
    };
    const result = try reg.run("echo_skill", ctx, "{\"wasm\":1}");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, result.payload_json, "wasm") != null);
}
