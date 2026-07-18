//! Freestanding WASM echo skill (bedd_skill_v1).
//! Echoes the input JSON buffer via host_set_result.

extern "bedd" fn host_alloc(size: i32) i32;
extern "bedd" fn host_set_result(ptr: i32, len: i32) void;

export fn bedd_abi_version() i32 {
    return 1;
}

/// Echo skill: report the inbound JSON as the result (no linear-memory surgery).
export fn bedd_on_event(in_ptr: i32, in_len: i32) i32 {
    _ = host_alloc; // keep import linked for ABI completeness
    if (in_len < 0) return 1;
    host_set_result(in_ptr, in_len);
    return 0;
}
