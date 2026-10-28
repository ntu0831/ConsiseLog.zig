const std = @import("std");
const consiselog = @import("consiselog");

const Log = consiselog.Log(.example);

pub fn main(init: std.process.Init) !void {
    try runWithPattern(init);
    try runWithPatternAndFormatter(init);
}

pub fn runWithPattern(init: std.process.Init) !void {
    try consiselog.init(init.io, init.gpa, .{
        // python logging style
        // %(asctime)s - %(name)s - %(levelname)s - %(message)s
        // 2005-03-19 15:10:26,618 - simple_example - DEBUG - debug message
        .pattern = .parse("{%Y}-{%m}-{%d} {%T},{@ms} - {@scope} - {@level} - {@msg}"),
    });
    defer consiselog.deinit(init.io);

    Log.info("{s}", .{"hello"});
}

pub fn runWithPatternAndFormatter(init: std.process.Init) !void {
    const local = struct {
        pub fn formatter(ctx: consiselog.config.UserFormatterContext) std.Io.Writer.Error!void {
            if (std.mem.eql(u8, ctx.id, "ts")) try ctx.writer.print("{d}", .{ctx.ts});
            if (std.mem.eql(u8, ctx.id, "level")) try ctx.writer.print("{d}", .{@backingInt(ctx.level)});
        }
    };

    try consiselog.init(init.io, init.gpa, .{
        .pattern = .parseWithFormatter("{#ts} {#level} {@msg}", local.formatter),
    });
    defer consiselog.deinit(init.io);

    Log.info("{s}", .{"hello"});
}

test {
    var w: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer w.deinit();

    const pattern = "{@msg}";
    try consiselog.init(std.testing.io, std.testing.allocator, .{
        .pattern = .parse(pattern),
        .output = .{ .writer = &w.writer },
    });
    Log.info("{s}", .{"hello"});
    consiselog.deinit(std.testing.io);

    try std.testing.expectEqualStrings("hello\n", w.written());
}

test "paseeWithFormatter" {
    // TODO
}
