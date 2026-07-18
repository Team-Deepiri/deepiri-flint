//! Test root — re-exports modules under test.
pub const bus = @import("bus.zig");
pub const config = @import("config.zig");
pub const tinder = @import("tinder.zig");
pub const ember = @import("ember.zig");
pub const strike = @import("strike.zig");
pub const skill = @import("skill/mod.zig");
pub const jsonx = @import("jsonx.zig");
pub const topics = @import("topics.zig");
pub const topics_desc = @import("topics_desc.zig");
pub const backoff = @import("util/backoff.zig");
pub const timeutil = @import("util/timeutil.zig");
pub const hash = @import("util/hash.zig");
pub const json_builder = @import("json/builder.zig");
pub const json_escape = @import("json/escape.zig");
pub const prometheus = @import("admin/prometheus.zig");
pub const shutdown = @import("shutdown.zig");


test {
    _ = bus;
    _ = config;
    _ = tinder;
    _ = ember;
    _ = strike;
    _ = skill;
    _ = jsonx;
    _ = topics;
    _ = topics_desc;
    _ = backoff;
    _ = timeutil;
    _ = hash;
    _ = json_builder;
    _ = json_escape;
    _ = prometheus;
    _ = shutdown;
}
