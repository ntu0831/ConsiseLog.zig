const std = @import("std");
const consiselog = @import("consiselog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const Log = consiselog.Log(.test_mp);

fn logLoop() !void {
    for (0..100) |i| Log.info("{s} {d}", .{ "test multi producer", i });
}

test "onelog_with_async" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try consiselog.init(io, gpa, .{
        .output = .{ .writer = &w.writer },
    });

    var group: std.Io.Group = .init;
    for (0..3) |_| group.async(io, logLoop, .{});
    try group.await(io);

    consiselog.deinit(io);

    try expectEqual(20970, w.fullCount());
}
