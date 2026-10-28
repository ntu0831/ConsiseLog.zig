const std = @import("std");
const consiselog = @import("consiselog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = consiselog.Log(.test_mp);

fn log() !void {
    Log.info("{s}", .{"test multi producer"});
}

test "onelog_with_async" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try consiselog.init(io, gpa, .{
        .output = .{ .writer = &w.writer },
    });

    var group: std.Io.Group = .init;
    for (0..3) |_| try group.concurrent(io, log, .{});
    try group.await(io);

    consiselog.deinit(io);

    try expectEqual(201, w.fullCount());
}
