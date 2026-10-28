const std = @import("std");
const config = @import("config");

pub fn main(init: std.process.Init) !void {
    const args = init.minimal.args;

    var buf: [64]u8 = undefined;

    const dir = try std.Io.Dir.cwd().openDir(init.io, config.install_bin, .{});
    defer dir.close(init.io);

    const path = try dir.realPathFileAlloc(init.io, ".", init.gpa);
    defer init.gpa.free(path);

    if (args.vector.len == 1) {
        const bin = try std.fmt.bufPrint(&buf, "./{s}", .{config.examples[0]});
        try run(path, bin, init.gpa, init.io);
        return;
    }

    var iter = try args.iterateAllocator(init.gpa);
    defer iter.deinit();
    _ = iter.next();

    while (iter.next()) |name| {
        for (config.examples) |example| {
            if (std.mem.eql(u8, example, name)) break;
        } else continue;

        const bin = try std.fmt.bufPrint(&buf, "./{s}", .{name});

        try run(path, bin, init.gpa, init.io);
    }
}

fn run(cwd: []const u8, name: []const u8, gpa: std.mem.Allocator, io: std.Io) !void {
    const result = try std.process.run(gpa, io, .{
        .argv = &.{name},
        .cwd = .{ .path = cwd },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    std.debug.print("{s}", .{result.stdout});
    std.debug.print("{s}", .{result.stderr});
}
