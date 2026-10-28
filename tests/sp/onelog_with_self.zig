const std = @import("std");
const consiselog = @import("consiselog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = consiselog.Log(.test_sp);

fn log() !void {
    Log.info("{s}", .{"test single producer"});
}

test "onelog with self" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try consiselog.init(io, gpa, .{ .output = .{ .writer = &w.writer } });

    try log();

    consiselog.deinit(io);

    try expectEqual(68, w.fullCount());
}
