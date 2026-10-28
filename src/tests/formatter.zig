test "none userformatter" {
    const pattern: []const PatternToken = &.{
        .msg,         .{ .literal = "|" },
        .scope,       .{ .literal = "|" },
        .level_full,  .{ .literal = "|" },
        .level_short, .{ .literal = "|" },
        .rfc3339,     .{ .literal = "|" },
        .rfc3339zulu, .{ .literal = "|" },
        .millisecond, .{ .literal = "|" },
        .microsecond, .{ .literal = "|" },
        .nanosecond,  .{ .literal = "|" },

        .year_4,      .{ .literal = "|" },
        .year_2,      .{ .literal = "|" },
        .month,       .{ .literal = "|" },
        .day,         .{ .literal = "|" },
        .hour_24,     .{ .literal = "|" },
        .minute,      .{ .literal = "|" },
        .second,      .{ .literal = "|" },
        .time,        .{ .literal = "|" },
        .date,        .{ .literal = "|" },
        .zone,        .{ .literal = "|" },
        .zone_gnu,
    };

    var allocating: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer allocating.deinit();

    {
        allocating.clearRetainingCapacity();
        const formatter: Formatter = .{
            .pattern = pattern,
            .timezone = .{ .local = 50400 }, // +14:00
            .pattern_has_timezone = true,
            .pattern_has_datetime = true,
        };
        try formatter.exec(.debug, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));
        try formatter.exec(.err, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));
        try formatter.exec(.info, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));
        try formatter.exec(.warn, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));

        const expected = std.fmt.comptimePrint("{s}{s}{s}{s}", .{
            "message|scope|debug|D|1970-01-01T14:00:00.000000000+14:00|1970-01-01T14:00:00.000000000Z|000|000|000|1970|70|01|01|14|00|00|14:00:00|01/01/70|+1400|+14:00",
            "message|scope|error|E|1970-01-01T14:00:00.000000000+14:00|1970-01-01T14:00:00.000000000Z|000|000|000|1970|70|01|01|14|00|00|14:00:00|01/01/70|+1400|+14:00",
            "message|scope|info|I|1970-01-01T14:00:00.000000000+14:00|1970-01-01T14:00:00.000000000Z|000|000|000|1970|70|01|01|14|00|00|14:00:00|01/01/70|+1400|+14:00",
            "message|scope|warning|W|1970-01-01T14:00:00.000000000+14:00|1970-01-01T14:00:00.000000000Z|000|000|000|1970|70|01|01|14|00|00|14:00:00|01/01/70|+1400|+14:00",
        });
        try expectEqualStrings(expected, allocating.written());
    }
    {
        allocating.clearRetainingCapacity();
        const formatter: Formatter = .{
            .pattern = pattern,
            .timezone = .{ .local = -43200 }, // -12:00
            .pattern_has_timezone = true,
            .pattern_has_datetime = true,
        };
        try formatter.exec(.debug, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));
        try formatter.exec(.err, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));
        try formatter.exec(.info, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));
        try formatter.exec(.warn, .scope, "{s}", .{"message"}, &allocating.writer, std.testing.allocator, std.testing.io, .fromNanoseconds(0));

        const expected = std.fmt.comptimePrint("{s}{s}{s}{s}", .{
            "message|scope|debug|D|1969-12-31T12:00:00.000000000-12:00|1969-12-31T12:00:00.000000000Z|000|000|000|1969|69|12|31|12|00|00|12:00:00|12/31/69|-1200|-12:00",
            "message|scope|error|E|1969-12-31T12:00:00.000000000-12:00|1969-12-31T12:00:00.000000000Z|000|000|000|1969|69|12|31|12|00|00|12:00:00|12/31/69|-1200|-12:00",
            "message|scope|info|I|1969-12-31T12:00:00.000000000-12:00|1969-12-31T12:00:00.000000000Z|000|000|000|1969|69|12|31|12|00|00|12:00:00|12/31/69|-1200|-12:00",
            "message|scope|warning|W|1969-12-31T12:00:00.000000000-12:00|1969-12-31T12:00:00.000000000Z|000|000|000|1969|69|12|31|12|00|00|12:00:00|12/31/69|-1200|-12:00",
        });
        try expectEqualStrings(expected, allocating.written());
    }
}

test "userformatter" {
    const local = struct {
        pub fn userformatter(ctx: UserFormatterContext) std.Io.Writer.Error!void {
            if (std.mem.eql(u8, ctx.id, "ts")) {
                try ctx.writer.print("{d}", .{ctx.ts});
            }
            if (std.mem.eql(u8, ctx.id, "allocator")) {
                const str = getStr(ctx.gpa) catch unreachable;
                defer ctx.gpa.free(str);
                try ctx.writer.writeAll(str);
            }
            if (std.mem.eql(u8, ctx.id, "io")) {
                var result = std.Io.async(ctx.io, getStr, .{ctx.gpa});
                const str = result.await(ctx.io) catch unreachable;
                defer ctx.gpa.free(str);
                try ctx.writer.writeAll(str);
            }
        }

        pub fn getStr(allocator: std.mem.Allocator) ![]u8 {
            var a: std.Io.Writer.Allocating = .init(allocator);
            defer a.deinit();
            try a.writer.print("{s}", .{"test"});
            return try a.toOwnedSlice();
        }
    };
    const formatter: Formatter = .{
        .pattern = &.{
            .{ .custom = "ts" },
            .{ .literal = "-" },
            .{ .custom = "allocator" },
            .{ .literal = "-" },
            .{ .custom = "io" },
        },
        .userformatter = local.userformatter,
    };
    var allocating: std.Io.Writer.Allocating = .init(gpa);
    defer allocating.deinit();
    try formatter.exec(.info, .userfomatter, "", .{}, &allocating.writer, gpa, io, .fromNanoseconds(0));
    try expectEqualStrings("0-test-test", allocating.written());
}

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqualStrings = std.testing.expectEqualStrings;

const Formatter = @import("../formatter.zig");
const PatternToken = @import("../pattern.zig").PatternToken;
const UserFormatterContext = @import("../config.zig").UserFormatterContext;

const std = @import("std");
