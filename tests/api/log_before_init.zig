const std = @import("std");
const consiselog = @import("consiselog");

const io = std.testing.io;
const gpa = std.testing.allocator;

const Log = consiselog.Log(.tests);

test "log before init" {
    Log.err("{s}", .{"test api"});
    Log.warn("{s}", .{"test api"});
    Log.info("{s}", .{"test api"});
    Log.debug("{s}", .{"test api"});
    var w: std.Io.Writer.Discarding = .init(&.{});
    try consiselog.init(io, gpa, .{ .output = .{ .writer = &w.writer } });
    consiselog.deinit(io);
}
