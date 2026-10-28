const std = @import("std");

pub const PatternToken = union(enum) {
    literal: []const u8,
    custom: []const u8, // {#id}

    msg, // {@msg}
    scope, // {@scope}
    level_full, // {@level} 小写
    level_short, // {@LEVEL} 大写
    rfc3339, // {@RFC3339} e.g. 2014-10-02T15:01:23.045123456+00:00
    rfc3339zulu, // {@RFC3339Z} RFC3339DateTimeWithNanoMulu e.g. 2014-10-02T15:01:23.045123456Z
    millisecond, // {@ms}
    microsecond, // {@us}
    nanosecond, // {@ns}

    // from strftime
    year_4, // {%Y}
    year_2, // {%y}
    month, // {%m}
    day, // {%d}
    hour_24, // {%H}
    minute, // {%M}
    second, // {%S}
    time, // {%T} e.g. 14:05:09
    date, // {%D} e.g. 03/05/24
    zone, // {%z} +0800
    zone_gnu, // {%:z} +06:00

    pub fn needDateTime(self: @This()) bool {
        return switch (self) {
            .year_4 => true,
            .year_2 => true,
            .month => true,
            .day => true,
            .hour_24 => true,
            .minute => true,
            .second => true,
            .millisecond => true,
            .microsecond => true,
            .nanosecond => true,
            .rfc3339 => true,
            .rfc3339zulu => true,
            else => false,
        };
    }

    pub fn needTimeZone(self: @This()) bool {
        return switch (self) {
            .zone => true,
            .zone_gnu => true,
            .rfc3339 => true,
            else => false,
        };
    }

    fn fromField(field: []const u8) error{UnknownField}!@This() {
        inline for ([_]struct { field: []const u8, token: std.meta.Tag(PatternToken) }{
            .{ .field = "@msg", .token = .msg },
            .{ .field = "@scope", .token = .scope },
            .{ .field = "@level", .token = .level_full },
            .{ .field = "@LEVEL", .token = .level_short },
            .{ .field = "@RFC3339", .token = .rfc3339 },
            .{ .field = "@RFC3339Z", .token = .rfc3339zulu },

            .{ .field = "@ms", .token = .millisecond },
            .{ .field = "@us", .token = .microsecond },
            .{ .field = "@ns", .token = .nanosecond },

            .{ .field = "%Y", .token = .year_4 },
            .{ .field = "%y", .token = .year_2 },
            .{ .field = "%m", .token = .month },
            .{ .field = "%d", .token = .day },
            .{ .field = "%H", .token = .hour_24 },
            .{ .field = "%M", .token = .minute },
            .{ .field = "%S", .token = .second },
            .{ .field = "%T", .token = .time },
            .{ .field = "%D", .token = .date },
            .{ .field = "%z", .token = .zone },
            .{ .field = "%:z", .token = .zone_gnu },
        }) |entry| {
            if (std.mem.eql(u8, field, entry.field)) return entry.token;
        } else if (std.mem.startsWith(u8, field, "#")) return .{
            .custom = field[1..],
        } else return error.UnknownField;
    }
};

pub const ParseError = error{
    UnknownField,
    UnmatchedOpenBrace,
    UnmatchedCloseBrace,
} || std.mem.Allocator.Error;

/// 解析 `pattern`，返回 token 切片（调用方负责 `free`）。
///
/// 花括号转义与未闭合报错语义对齐 `std.Io.Writer.print`：
/// - `{{` / `}}` 表示字面量 `{` / `}`，作为指向 `pattern` 内部的单字符
///   literal token 输出（相邻字面量可能因此拆成多个 token，渲染结果不变）；
/// - `{` 未闭合（包括末尾孤立的 `{`）=> `UnmatchedOpenBrace`；
/// - 单独出现的 `}` => `UnmatchedCloseBrace`；
/// - `{x}` 内容无法识别 => `UnknownField`。
/// 所有 literal/custom 切片均指向 `pattern` 内部，不额外分配。
pub fn parsePattern(
    gpa: std.mem.Allocator,
    pattern: []const u8,
) ParseError![]PatternToken {
    var tokens: std.ArrayList(PatternToken) = .empty;
    defer tokens.deinit(gpa);

    var i: usize = 0;
    var literal_start: usize = 0;

    while (i < pattern.len) {
        const c = pattern[i];
        if (c == '{' or c == '}') {
            if (i + 1 < pattern.len and pattern[i + 1] == c) {
                // {{ / }} 转义：先输出之前累积的字面量，再输出单个花括号
                if (i > literal_start) try tokens.append(gpa, .{ .literal = pattern[literal_start..i] });
                try tokens.append(gpa, .{ .literal = pattern[i .. i + 1] });
                i += 2;
                literal_start = i;
            } else if (c == '}') {
                return error.UnmatchedCloseBrace;
            } else {
                const close = std.mem.indexOfScalarPos(u8, pattern, i + 1, '}') orelse
                    return error.UnmatchedOpenBrace;

                if (i > literal_start) try tokens.append(gpa, .{ .literal = pattern[literal_start..i] });
                try tokens.append(gpa, try .fromField(pattern[i + 1 .. close]));

                i = close + 1;
                literal_start = i;
            }
        } else {
            i += 1;
        }
    }

    if (literal_start < pattern.len) {
        try tokens.append(gpa, .{ .literal = pattern[literal_start..] });
    }

    return try tokens.toOwnedSlice(gpa);
}

/// comptime 版 [`parsePattern`]，语义完全一致，返回指向常量数据的 token 切片。
pub fn parsePatternComptime(comptime pattern: []const u8) ParseError![]const PatternToken {
    return comptime blk: {
        // 上界：每个字符至多贡献一个 token
        var tokens: [pattern.len]PatternToken = undefined;
        var n: usize = 0;

        var i: usize = 0;
        var literal_start: usize = 0;

        while (i < pattern.len) {
            const c = pattern[i];
            if (c == '{' or c == '}') {
                if (i + 1 < pattern.len and pattern[i + 1] == c) {
                    if (i > literal_start) {
                        tokens[n] = .{ .literal = pattern[literal_start..i] };
                        n += 1;
                    }
                    tokens[n] = .{ .literal = pattern[i .. i + 1] };
                    n += 1;

                    i += 2;
                    literal_start = i;
                } else if (c == '}') {
                    break :blk error.UnmatchedCloseBrace;
                } else {
                    const close = std.mem.indexOfScalarPos(u8, pattern, i + 1, '}') orelse
                        break :blk error.UnmatchedOpenBrace;

                    if (i > literal_start) {
                        tokens[n] = .{ .literal = pattern[literal_start..i] };
                        n += 1;
                    }

                    tokens[n] = PatternToken.fromField(pattern[i + 1 .. close]) catch |err|
                        break :blk err;
                    n += 1;

                    i = close + 1;
                    literal_start = i;
                }
            } else {
                i += 1;
            }
        }

        if (literal_start < pattern.len) {
            tokens[n] = .{ .literal = pattern[literal_start..] };
            n += 1;
        }

        const finalized = tokens[0..n].*;

        break :blk &finalized;
    };
}

test {
    _ = @import("./tests/pattern.zig");
}
