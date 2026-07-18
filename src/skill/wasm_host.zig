const std = @import("std");
const c = @cImport({
    @cInclude("wasm3.h");
});
const skill_mod = @import("mod.zig");

/// Host-side WASM skill using wasm3.
/// ABI bedd_skill_v1:
///   export bedd_abi_version() -> i32 (=1)
///   export bedd_on_event(in_ptr:i32, in_len:i32) -> i32  (0=ok)
///   imports module "bedd":
///     host_alloc(size:i32) -> i32
///     host_set_result(ptr:i32, len:i32)
pub const WasmSkill = struct {
    allocator: std.mem.Allocator,
    wasm_bytes: []u8,
    env: c.IM3Environment,
    runtime: c.IM3Runtime,
    module: c.IM3Module,
    result_buf: std.ArrayList(u8),
    bump: i32 = 8192,

    pub fn deinit(self: *WasmSkill) void {
        // Module ownership transfers to runtime on successful load.
        if (self.runtime != null) c.m3_FreeRuntime(self.runtime);
        if (self.env != null) c.m3_FreeEnvironment(self.env);
        self.allocator.free(self.wasm_bytes);
        self.result_buf.deinit();
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !WasmSkill {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const bytes = try file.readToEndAlloc(allocator, 8 * 1024 * 1024);
        errdefer allocator.free(bytes);

        const env = c.m3_NewEnvironment();
        if (env == null) return error.WasmError;
        errdefer c.m3_FreeEnvironment(env);

        const runtime = c.m3_NewRuntime(env, 256 * 1024, null);
        if (runtime == null) return error.WasmError;
        errdefer c.m3_FreeRuntime(runtime);

        var module: c.IM3Module = null;
        const parse_res = c.m3_ParseModule(env, &module, bytes.ptr, @intCast(bytes.len));
        if (parse_res != null) {
            std.log.err("wasm parse: {s}", .{parse_res});
            return error.WasmError;
        }

        const load_res = c.m3_LoadModule(runtime, module);
        if (load_res != null) {
            std.log.err("wasm load: {s}", .{load_res});
            c.m3_FreeModule(module);
            return error.WasmError;
        }

        var skill = WasmSkill{
            .allocator = allocator,
            .wasm_bytes = bytes,
            .env = env,
            .runtime = runtime,
            .module = module,
            .result_buf = std.ArrayList(u8).init(allocator),
        };

        try skill.linkHost();
        return skill;
    }

    fn linkHost(self: *WasmSkill) !void {
        const la = c.m3_LinkRawFunctionEx(self.module, "bedd", "host_alloc", "i(i)", &hostAlloc, self);
        // Optional import — many skills only need host_set_result.
        _ = la;

        const lr = c.m3_LinkRawFunctionEx(self.module, "bedd", "host_set_result", "v(ii)", &hostSetResult, self);
        if (lr != null) std.log.warn("link host_set_result: {s}", .{lr});
    }

    pub fn run(self: *WasmSkill, ctx: skill_mod.SkillContext, input_json: []const u8) skill_mod.SkillError!skill_mod.SkillResult {
        _ = ctx;
        self.result_buf.clearRetainingCapacity();
        self.bump = 8192;
        active_skill = self;
        defer active_skill = null;

        const memory = c.m3_GetMemory(self.runtime, null, 0);
        if (memory == null) return skill_mod.SkillError.WasmError;

        const mem_len = c.m3_GetMemorySize(self.runtime);
        const in_ptr: i32 = 1024;
        if (@as(u32, @intCast(in_ptr)) + input_json.len > mem_len) {
            return skill_mod.SkillError.WasmError;
        }
        const mem_slice = @as([*]allowzero u8, @ptrCast(memory))[0..mem_len];
        @memcpy(@as([*]u8, @ptrCast(mem_slice.ptr))[@intCast(in_ptr) .. @as(usize, @intCast(in_ptr)) + input_json.len], input_json);

        var fn_on: c.IM3Function = null;
        const find = c.m3_FindFunction(&fn_on, self.runtime, "bedd_on_event");
        if (find != null or fn_on == null) {
            if (find) |msg| {
                std.log.err("bedd_on_event missing: {s}", .{msg});
            } else {
                std.log.err("bedd_on_event missing: null fn", .{});
            }
            return skill_mod.SkillError.WasmError;
        }

        const call = c.m3_CallV(fn_on, in_ptr, @as(i32, @intCast(input_json.len)));
        if (call != null) {
            std.log.err("bedd_on_event failed: {s}", .{call});
            return skill_mod.SkillError.WasmError;
        }

        var status: i32 = -1;
        const got = c.m3_GetResultsV(fn_on, &status);
        if (got != null) return skill_mod.SkillError.WasmError;
        if (status != 0) return skill_mod.SkillError.SkillFailed;

        if (self.result_buf.items.len == 0) {
            const dup = self.allocator.dupe(u8, input_json) catch return skill_mod.SkillError.OutOfMemory;
            return .{ .payload_json = dup };
        }

        const out = self.allocator.dupe(u8, self.result_buf.items) catch return skill_mod.SkillError.OutOfMemory;
        return .{ .payload_json = out };
    }
};

var active_skill: ?*WasmSkill = null;

fn hostAlloc(runtime: c.IM3Runtime, ctx: c.IM3ImportContext, sp: [*c]u64, _mem: ?*anyopaque) callconv(.C) ?*const anyopaque {
    _ = runtime;
    _ = ctx;
    _ = _mem;
    // signature i(i): ret at sp[0], arg at sp[1]
    const size: i32 = @truncate(@as(i64, @bitCast(sp[1])));
    const skill = active_skill orelse {
        sp[0] = 0;
        return null;
    };
    const ptr = skill.bump;
    skill.bump += size + 16;
    if (@as(u32, @intCast(skill.bump)) > c.m3_GetMemorySize(skill.runtime)) {
        sp[0] = 0;
        return null;
    }
    sp[0] = @bitCast(@as(i64, ptr));
    return null;
}

fn hostSetResult(runtime: c.IM3Runtime, ctx: c.IM3ImportContext, sp: [*c]u64, _mem: ?*anyopaque) callconv(.C) ?*const anyopaque {
    _ = ctx;
    _ = _mem;
    const skill = active_skill orelse return @as(?*const anyopaque, @ptrCast(@as([*:0]const u8, "no active skill")));
    const ptr: i32 = @truncate(@as(i64, @bitCast(sp[0])));
    const len: i32 = @truncate(@as(i64, @bitCast(sp[1])));
    if (len < 0) return @as(?*const anyopaque, @ptrCast(@as([*:0]const u8, "negative len")));

    const memory = c.m3_GetMemory(runtime, null, 0) orelse
        return @as(?*const anyopaque, @ptrCast(@as([*:0]const u8, "no memory")));
    const mem_slice = @as([*]u8, @ptrCast(memory))[0..c.m3_GetMemorySize(runtime)];
    const start: usize = @intCast(ptr);
    const end = start + @as(usize, @intCast(len));
    if (end > mem_slice.len) return @as(?*const anyopaque, @ptrCast(@as([*:0]const u8, "oob")));

    skill.result_buf.clearRetainingCapacity();
    skill.result_buf.appendSlice(mem_slice[start..end]) catch
        return @as(?*const anyopaque, @ptrCast(@as([*:0]const u8, "oom")));
    return null;
}
