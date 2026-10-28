const std = @import("std");
const consiselog = @import("consiselog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = consiselog.Log(.test_sp);

fn logLoop() !void {
    for (0..100) |i| Log.info("{s} {d}", .{ "test single producer", i });
}

test "looplog_with_self" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try consiselog.init(io, gpa, .{
        .output = .{ .writer = &w.writer },
    });

    var f = std.Io.async(io, logLoop, .{});
    try f.await(io);

    consiselog.deinit(io);

    try expectEqual(7090, w.fullCount());
}
