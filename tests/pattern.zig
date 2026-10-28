const std = @import("std");
const consiselog = @import("consiselog");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqualStrings = std.testing.expectEqualStrings;

const Log = consiselog.Log(.pattern);

// TODO 引入config（在build system中通过外部脚本生成本地时间、本地时区等信息作为配置包进行导入）进行对比，毫秒微妙纳秒除外。

test "comptime parse" {
    var w: std.Io.Writer.Allocating = .init(gpa);
    defer w.deinit();

    // consiselog.deinit(io);
    try consiselog.init(io, gpa, .{
        .pattern = .parse("hello"),
        .output = .{ .writer = &w.writer },
    });
    Log.info("", .{});
    consiselog.deinit(io);

    try expectEqualStrings("hello\n", w.written());
}

test "comptime parse with formatter" {
    const local = struct {
        pub fn formatter(ctx: consiselog.config.UserFormatterContext) std.Io.Writer.Error!void {
            if (std.mem.eql(u8, ctx.id, "test")) {
                try ctx.writer.print("{s}", .{"hello"});
            }
        }
    };

    var w: std.Io.Writer.Allocating = .init(gpa);
    defer w.deinit();

    try consiselog.init(io, gpa, .{
        .pattern = .parseWithFormatter("{#test}", local.formatter),
        .output = .{ .writer = &w.writer },
    });
    Log.info("", .{});
    consiselog.deinit(io);

    try expectEqualStrings("hello\n", w.written());
}

test "runtime" {
    const rp: consiselog.config.RuntimePattern = try .parse(gpa, "hello");
    defer rp.deinit(gpa);

    var w: std.Io.Writer.Allocating = .init(gpa);
    defer w.deinit();

    try consiselog.init(io, gpa, .{
        .pattern = rp.toPattern(),
        .output = .{ .writer = &w.writer },
    });
    Log.info("", .{});
    consiselog.deinit(io);

    try expectEqualStrings("hello\n", w.written());
}

test "runtime parse with formatter" {
    const local = struct {
        pub fn formatter(ctx: consiselog.config.UserFormatterContext) std.Io.Writer.Error!void {
            if (std.mem.eql(u8, ctx.id, "test")) {
                try ctx.writer.print("{s}", .{"hello"});
            }
        }
    };

    const rp: consiselog.config.RuntimePattern = try .parseWithFormatter(gpa, "{#test}", local.formatter);
    defer rp.deinit(gpa);

    var w: std.Io.Writer.Allocating = .init(gpa);
    defer w.deinit();

    try consiselog.init(io, gpa, .{
        .pattern = rp.toPattern(),
        .output = .{ .writer = &w.writer },
    });
    Log.info("", .{});
    consiselog.deinit(io);

    try expectEqualStrings("hello\n", w.written());
}
