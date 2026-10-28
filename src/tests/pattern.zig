test "parse all supported fields in one pattern" {
    const pattern = " {#id} {%Y}-{%y}-{%m}-{%d} {%H}:{%M}:{%S} {%T} {%D} {%z} {%:z} {@RFC3339} {@RFC3339Z} {@ms}{@us}{@ns} [{@LEVEL}] [{@level}] ({@scope}): {@msg}";
    const expected = [_]PatternToken{
        .{ .literal = " " },   .{ .custom = "id" },
        .{ .literal = " " },   .year_4,
        .{ .literal = "-" },   .year_2,
        .{ .literal = "-" },   .month,
        .{ .literal = "-" },   .day,
        .{ .literal = " " },   .hour_24,
        .{ .literal = ":" },   .minute,
        .{ .literal = ":" },   .second,
        .{ .literal = " " },   .time,
        .{ .literal = " " },   .date,
        .{ .literal = " " },   .zone,
        .{ .literal = " " },   .zone_gnu,
        .{ .literal = " " },   .rfc3339,
        .{ .literal = " " },   .rfc3339zulu,
        .{ .literal = " " },   .millisecond,
        .microsecond,          .nanosecond,
        .{ .literal = " [" },  .level_short,
        .{ .literal = "] [" }, .level_full,
        .{ .literal = "] (" }, .scope,
        .{ .literal = "): " }, .msg,
    };

    const runtime_result = try parsePattern(gpa, pattern);
    defer gpa.free(runtime_result);
    try expectTokens(&expected, runtime_result);
    try expectTokens(&expected, try parsePatternComptime(pattern));

    var map: std.AutoHashMapUnmanaged(isize, bool) = .empty;
    defer map.deinit(gpa);

    inline for (@typeInfo(std.meta.Tag(PatternToken)).@"enum".field_values) |tag| {
        try map.put(gpa, tag, false);
    }
    for (runtime_result) |item| {
        try map.put(gpa, @backingInt(std.meta.activeTag(item)), true);
    }

    var it = map.iterator();
    while (it.next()) |item| {
        if (item.value_ptr.* == false) {
            const tag: std.meta.Tag(PatternToken) = @fromBackingInt(@intCast(item.key_ptr.*));
            std.debug.print("PatterToken: {s} not exist\n", .{@tagName(tag)});
            return error.TokenNotExist;
        }
    }
}

test "{{ }}" {
    inline for ([_]struct { pattern: []const u8, expected: []const PatternToken }{
        .{ .expected = &.{.{ .literal = "{" }}, .pattern = "{{" },
        .{ .expected = &.{.{ .literal = "}" }}, .pattern = "}}" },
        .{ .expected = &.{ .{ .literal = "{" }, .msg }, .pattern = "{{{@msg}" },
        .{ .expected = &.{ .msg, .{ .literal = "}" } }, .pattern = "{@msg}}}" },
    }) |case| try expectTokensByPattern(case.expected, case.pattern);
}

test "empty pattern" {
    try expectTokensByPattern(&.{}, "");
}

test "parse error" {
    inline for ([_]struct { pattern: []const u8, expected: ParseError }{
        .{ .expected = error.UnmatchedOpenBrace, .pattern = "{" },
        .{ .expected = error.UnmatchedOpenBrace, .pattern = "prefix{" },
        .{ .expected = error.UnmatchedOpenBrace, .pattern = "{@msg" },
        .{ .expected = error.UnmatchedOpenBrace, .pattern = "prefix{@msg" },

        .{ .expected = error.UnmatchedCloseBrace, .pattern = "}" },
        .{ .expected = error.UnmatchedCloseBrace, .pattern = "}suffix" },
        .{ .expected = error.UnmatchedCloseBrace, .pattern = "@msg}" },
        .{ .expected = error.UnmatchedCloseBrace, .pattern = "@msg}suffix" },

        .{ .expected = error.UnknownField, .pattern = "{}" },
        .{ .expected = error.UnknownField, .pattern = "{foo}" },
        .{ .expected = error.UnknownField, .pattern = "{@tmp}" },
        .{ .expected = error.UnknownField, .pattern = "{%Z}" },
    }) |case| try expectErrorByPattern(case.expected, case.pattern);
}

fn expectErrorByPattern(expected: anyerror, comptime pattern: []const u8) !void {
    try expectError(expected, parsePattern(gpa, pattern)); // runtime
    try expectError(expected, parsePatternComptime(pattern)); // comptime
}

fn expectTokensByPattern(expected: []const PatternToken, comptime pattern: []const u8) !void {
    { // runtime
        const actual = try parsePattern(gpa, pattern);
        defer gpa.free(actual);
        try expectTokens(expected, actual);
    }
    { // comptime
        try expectTokens(expected, try parsePatternComptime(pattern));
    }
}

fn expectTokens(expected: []const PatternToken, actual: []const PatternToken) !void {
    try expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| {
        try expectEqual(std.meta.activeTag(e), std.meta.activeTag(a));
        if (e == .literal) try expectEqualStrings(e.literal, a.literal);
        if (e == .custom) try expectEqualStrings(e.custom, a.custom);
    }
}

const ParseError = Pattern.ParseError;
const PatternToken = Pattern.PatternToken;
const parsePattern = Pattern.parsePattern;
const parsePatternComptime = Pattern.parsePatternComptime;

const gpa = std.testing.allocator;
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Pattern = @import("../pattern.zig");

const std = @import("std");
