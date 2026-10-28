const std = @import("std");
const consiselog = @import("consiselog");

const msgs_per_worker = 100;

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = consiselog.helper.logFn,
    .fmt_max_depth = 10,
};

pub fn main(init: std.process.Init) !void {
    try consiselog.init(init.io, init.gpa, .default);
    defer consiselog.deinit(init.io);

    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    try group.concurrent(init.io, workerTaskA, .{init.io});
    try group.concurrent(init.io, workerTaskB, .{init.io});
    try group.concurrent(init.io, workerTaskC, .{init.io});
    try group.await(init.io);
}

fn workerTaskA(io: std.Io) std.Io.Cancelable!void {
    const Log = std.log.scoped(.TaskA);
    for (0..msgs_per_worker) |i| {
        Log.info("processing item {d}", .{i});
        if (i % 25 == 0) try io.sleep(.fromMilliseconds(2), .awake);
    }
}

fn workerTaskB(io: std.Io) std.Io.Cancelable!void {
    const Log = std.log.scoped(.TaskB);
    for (0..msgs_per_worker) |i| {
        switch (i % 4) {
            0 => Log.err("processing item {d}", .{i}),
            1 => Log.warn("processing item {d}", .{i}),
            2 => Log.info("processing item {d}", .{i}),
            else => Log.debug("processing item {d}", .{i}),
        }
        if (i % 25 == 0) try io.sleep(.fromMilliseconds(2), .awake);
    }
}

fn workerTaskC(io: std.Io) std.Io.Cancelable!void {
    const Log = std.log;
    for (0..msgs_per_worker) |i| {
        Log.info("processing item {d}", .{i});
        if (i % 25 == 0) try io.sleep(.fromMilliseconds(2), .awake);
    }
}
