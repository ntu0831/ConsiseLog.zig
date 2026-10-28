const std = @import("std");
const consiselog = @import("consiselog");

const Log = consiselog.Log(.example);

pub fn main(init: std.process.Init) !void {
    try runWithFileWriter(init);
    try runWithAllocatingWriter(init);
}

fn runWithAllocatingWriter(init: std.process.Init) !void {
    var w: std.Io.Writer.Allocating = .init(init.gpa);
    defer w.deinit();

    try consiselog.init(init.io, init.gpa, .{
        .output = .{ .writer = &w.writer },
    });
    defer consiselog.deinit(init.io);

    Log.info("{s}", .{"done"});
    Log.err("error", .{});

    try init.io.sleep(.fromSeconds(1), .awake);

    std.debug.print("{s}\n", .{w.written()});
}

fn runWithFileWriter(init: std.process.Init) !void {
    const logfile = try std.Io.Dir.cwd().createFile(init.io, "log.txt", .{ .truncate = false });
    defer logfile.close(init.io);

    var writer = logfile.writer(init.io, &.{});

    try consiselog.init(init.io, init.gpa, .{
        .output = .{ .writer = &writer.interface },
    });
    defer consiselog.deinit(init.io);

    Log.info("{s}", .{"done"});
    Log.err("error", .{});
}
