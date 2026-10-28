const std = @import("std");
const builtin = @import("builtin");

pub const getBaseUtcOffset = switch (builtin.target.os.tag) {
    .windows => Windows.getBaseUtcOffset,
    else => Posix.getBaseUtcOffset,
};

pub const Windows = struct {
    const WCHAR = std.os.windows.WCHAR;
    const LONG = std.os.windows.LONG;
    const WORD = std.os.windows.WORD;
    const TIME_ZONE_ID_INVALID = @as(u32, 4294967295);
    const TIME_ZONE_INFORMATION = extern struct {
        Bias: LONG,
        StandardName: [32]WCHAR,
        StandardDate: SYSTEMTIME,
        StandardBias: LONG,
        DaylightName: [32]WCHAR,
        DaylightDate: SYSTEMTIME,
        DaylightBias: LONG,
    };
    pub const SYSTEMTIME = extern struct {
        wYear: WORD,
        wMonth: WORD,
        wDayOfWeek: WORD,
        wDay: WORD,
        wHour: WORD,
        wMinute: WORD,
        wSecond: WORD,
        wMilliseconds: WORD,
    };
    extern "kernel32" fn GetTimeZoneInformation(tzi: ?*TIME_ZONE_INFORMATION) callconv(.winapi) u32;
    pub fn getBaseUtcOffset() !isize {
        var tzi: TIME_ZONE_INFORMATION = std.mem.zeroes(TIME_ZONE_INFORMATION);

        if (GetTimeZoneInformation(&tzi) == TIME_ZONE_ID_INVALID) {
            return error.GetTimeZoneInformation;
        }
        return -((tzi.Bias + tzi.StandardBias) * 60);
    }
};

pub const Posix = struct {
    const Tm = extern struct {
        tm_sec: c_int,
        tm_min: c_int,
        tm_hour: c_int,
        tm_mday: c_int,
        tm_mon: c_int,
        tm_year: c_int,
        tm_wday: c_int,
        tm_yday: c_int,
        tm_isdst: c_int,
    };

    extern "c" fn gmtime_r(noalias [*c]const std.c.time_t, noalias ?*anyopaque) ?*anyopaque;
    extern "c" fn mktime(noalias ?*anyopaque) std.c.time_t;
    extern "c" fn time([*c]std.c.time_t) std.c.time_t;

    pub fn getBaseUtcOffset() !isize {
        var now_utc_without_tz = time(null);
        var buf: [256]u8 align(@alignOf(Tm)) = std.mem.zeroes([256]u8);
        if (gmtime_r(&now_utc_without_tz, &buf) == null) {
            return error.gmtime;
        }
        const ptr: *Tm = @ptrCast(@alignCast(&buf));
        ptr.tm_isdst = 0;
        const utc_with_tz = mktime(&buf);
        return now_utc_without_tz - utc_with_tz;
    }
};

test {
    _ = @import("./tests/localtime.zig");
}
