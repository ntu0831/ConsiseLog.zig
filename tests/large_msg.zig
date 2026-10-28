/// test for multi buf(alloc)
const consiselog = @import("consiselog");
const std = @import("std");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = consiselog.Log(.large_msg);

test "large msg" {
    var w: std.Io.Writer.Discarding = .init(&.{});
    try consiselog.init(io, gpa, .{
        .mode = .{ .async = .{ .buffer = .{ .size = 4, .count = 20 } } },
        .output = .{ .writer = &w.writer },
    });
    Log.info("{s}", .{"test small size"});
    consiselog.deinit(io);
    try expectEqual(65, w.fullCount());
}
