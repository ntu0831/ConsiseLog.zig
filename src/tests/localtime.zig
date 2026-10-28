test "timezone" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;

    const cases = .{
        // Non DST
        .{ .tz = "Asia/Shanghai", .offset = 28800 },
        .{ .tz = "America/Phoenix", .offset = -25200 },
        // DST
        .{ .tz = "America/New_York", .offset = -18000 }, // classic
        .{ .tz = "Europe/London", .offset = 0 }, // dst: 3-10
        .{ .tz = "Australia/Sydney", .offset = 36000 }, // dst: 10-4
        .{ .tz = "America/Santiago", .offset = -14400 }, // specical
        // Non-whole-hour offset
        .{ .tz = "Asia/Colombo", .offset = 19800 }, // 30min
        .{ .tz = "Asia/Kathmandu", .offset = 20700 }, // 45min
        .{ .tz = "Australia/Eucla", .offset = 31500 }, // 45min
    };

    inline for (cases) |case| {
        _ = setenv("TZ", case.tz, 1);
        try expectEqual(case.offset, try Darwin.getBaseUtcOffset());
    }
}

pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) ?[*:0]u8;

const expectEqual = std.testing.expectEqual;
const Darwin = localtime.Posix;

const localtime = @import("../localtime.zig");

const builtin = @import("builtin");
const std = @import("std");
