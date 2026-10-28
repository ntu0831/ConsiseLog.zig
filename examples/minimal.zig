const std = @import("std");
const consiselog = @import("consiselog");

const Log = consiselog.Log(.example);

pub fn main(init: std.process.Init) !void {
    try consiselog.init(init.io, init.gpa, .default);
    defer consiselog.deinit(init.io);

    Log.info("{s}", .{"hello"});
}
