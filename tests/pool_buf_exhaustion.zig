const std = @import("std");
const consiselog = @import("consiselog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Log = consiselog.Log(.pool_buf_exhaustion);

test "truncate" {
    var w: std.Io.Writer.Allocating = .init(gpa);
    defer w.deinit();

    try consiselog.init(io, gpa, .{
        .pattern = .parse("{@msg}"),
        .mode = .{ .async = .{
            .on_pool_exhausted = .truncate,
            .buffer = .{ .count = 2, .size = 4 },
        } },
        .output = .{ .writer = &w.writer },
    });
    Log.info("{s}", .{"1234567890"});
    consiselog.deinit(io);

    try expectEqualStrings("12345678\n", w.written());
}

test "drop" {
    var w: std.Io.Writer.Discarding = .init(&.{});

    try consiselog.init(io, gpa, .{
        .pattern = .parse("{@msg}"),
        .mode = .{ .async = .{
            .on_pool_exhausted = .drop,
            .buffer = .{ .count = 2, .size = 4 },
        } },
        .output = .{ .writer = &w.writer },
    });
    Log.info("{s}", .{"1234567890"});
    consiselog.deinit(io);

    try expectEqual(0, w.fullCount());
}
