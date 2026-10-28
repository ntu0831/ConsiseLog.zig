const std = @import("std");

pub const helper = @import("helper.zig");
pub const config = @import("config.zig");
pub const Config = config.Config;
pub const Options = config.Options;

pub const InitError = api.InitError;
pub const init = api.init;
pub const deinit = api.deinit;
pub const setLevel = api.setLevel;
pub const disable = api.disable;
pub const Log = api.Log;

const api = @import("api.zig");

test {
    _ = @import("time.zig");
    _ = @import("pattern.zig");
    _ = @import("formatter.zig");
    _ = @import("localtime.zig");
}
