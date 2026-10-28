const std = @import("std");

const us_per_ms = std.time.us_per_ms;
const us_per_s = std.time.us_per_s;
const s_per_min = std.time.s_per_min;
const s_per_hour = std.time.s_per_hour;
const s_per_day = std.time.s_per_day;
const days_per_1y = 365;
const days_per_4y = days_per_1y * 4 + 1;
const days_per_100y = days_per_1y * 100 + 24; // 36524
const days_per_400y = days_per_1y * 400 + 97; // 146097
const days_before_epoch = 719468; // 0000-03-01 与 1970-01-01 之间的天数

pub const TimeZone = struct {
    hour: i8,
    minute: u8,

    const min_per_hour = 60;

    const max: @This() = .{ .hour = 14, .minute = 0 };
    const min: @This() = .{ .hour = -12, .minute = 0 };

    pub fn toSeconds(self: @This()) isize {
        const total_minutes: isize = @as(isize, @abs(self.hour)) * min_per_hour + self.minute;
        const total_seconds: isize = total_minutes * s_per_min;
        return if (self.hour < 0) -total_seconds else total_seconds;
    }

    pub fn fromSeconds(offset: isize) @This() {
        std.debug.assert(offset <= comptime max.toSeconds());
        std.debug.assert(offset >= comptime min.toSeconds());
        const total_minutes = @divTrunc(offset, 60);
        return .{
            .hour = @intCast(@divTrunc(total_minutes, min_per_hour)),
            .minute = @intCast(@rem(total_minutes, min_per_hour)),
        };
    }

    pub fn formatStrftimeZ(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        const sign: u8 = if (self.hour < 0) '-' else '+';
        try w.print("{c}{d:0>2}{d:0>2}", .{ sign, @abs(self.hour), self.minute });
    }

    pub fn formatRFC3339(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        const sign: u8 = if (self.hour < 0) '-' else '+';
        try w.print("{c}{d:0>2}:{d:0>2}", .{ sign, @abs(self.hour), self.minute });
    }

    pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        try self.formatRFC3339(w);
    }
};

pub const DateTime = struct {
    /// allow year<0,year>9999
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
    microsecond: u16,
    nanosecond: u16 = 0,

    pub fn toRFC3339(self: @This()) RFC3339 {
        if (self.year < 1) {
            @branchHint(.cold);
            return .min;
        }
        if (self.year > 9999) {
            @branchHint(.cold);
            return .max;
        }
        return .{
            .year = @intCast(self.year),
            .month = self.month,
            .day = self.day,
            .hour = self.hour,
            .minute = self.minute,
            .second = self.second,
            .millisecond = self.millisecond,
            .microsecond = self.microsecond,
            .nanosecond = self.nanosecond,
        };
    }

    pub fn fromTimestampNano(ns_ts: i96) DateTime {
        if (ns_ts < 0) {
            @branchHint(.cold);
            const ns: u16 = @intCast(@mod(ns_ts, std.time.ns_per_us));
            var dt = fromNegativeTimestamp(@intCast(@divFloor(ns_ts, std.time.ns_per_us)));
            dt.nanosecond = ns;
            return dt;
        }
        const ns: u16 = @intCast(@rem(ns_ts, std.time.ns_per_us));
        var dt = fromNonNegativeTimestamp(@intCast(@divTrunc(ns_ts, std.time.ns_per_us)));
        dt.nanosecond = ns;
        return dt;
    }

    /// 把 Unix 时间戳（微秒）转换为 DateTime，支持负数（1970-01-01 之前）。
    /// 按符号分发：非负走无符号快速路径，负数走借位路径。
    ///
    /// 特殊情况处理（详见两个子函数）：
    ///  - 负数拆分必须用 @divFloor/@mod（余数恒非负），不能用 @divTrunc/@rem
    ///    （向零截断，负数会得到负余数）：-1 µs = -1 秒 + 999_999 µs，
    ///    -1 秒 = 昨天 23:59:59，逐级借位都正确。
    ///  - 闰年规则完整（4/100/400）：1900、2100 非闰年，2000 闰年，year 0 闰年。
    ///  - 年份为 i32，可完整表示任意 i64 时间戳（约 ±29.5 万年），无错误分支。
    ///  - Unix 时间不含闰秒（不存在 23:59:60），与 C/Python/Go 行为一致。
    pub fn fromTimestamp(us_ts: i64) DateTime {
        if (us_ts < 0) {
            @branchHint(.cold);
            return fromNegativeTimestamp(us_ts);
        }
        return fromNonNegativeTimestamp(@intCast(us_ts));
    }

    /// 非负时间戳（1970-01-01T00:00:00Z 及之后）：无符号算法。
    /// 整除与取余天然满足要求，自 0000-03-01 起的天数也恒为非负。
    fn fromNonNegativeTimestamp(us_ts: u64) DateTime {
        const seconds = @divTrunc(us_ts, us_per_s);
        const sub_second_us = @rem(us_ts, us_per_s);
        const day_n = days_before_epoch + seconds / s_per_day; // 相对 0000-03-01 的天数，恒 >= 0
        const seconds_since_midnight = seconds % s_per_day;
        // return fromParts(.civilFromDayNumber(day_n), seconds_since_midnight, sub_second_us);
        const civil: CivilDate = .fromDayNumber(day_n);
        return civil.toDateTime(seconds_since_midnight, sub_second_us);
    }

    /// 负数时间戳（1970-01-01T00:00:00Z 之前）：核心是两级"借位"。
    ///  1. 拆分用 @divFloor/@mod（余数符号跟随除数，恒非负）而不是向零截断：
    ///     -1 µs = -1 秒 + 999_999 µs；-1 秒 = 昨天 23:59:59（86_399 秒处借位）。
    ///  2. 自 0000-03-01 起的天数可能为负（早于 0000 年 3 月）：减去整数个
    ///     400 年周期把余下天数归一到 0..146_096，复用公共年月日算法，
    ///     再把周期数乘 400 折算回年份。
    fn fromNegativeTimestamp(us_ts: i64) DateTime {
        const seconds = @divFloor(us_ts, us_per_s);
        const sub_second_us: u64 = @intCast(@mod(us_ts, us_per_s));
        const days = @divFloor(seconds, s_per_day);
        const seconds_since_midnight: u64 = @intCast(@mod(seconds, s_per_day));

        const day_n: i64 = days_before_epoch + days;
        const era: i32 = @intCast(@divFloor(day_n, days_per_400y)); // 负数周期数（floor 语义）
        const day_in_era: u64 = @intCast(day_n - era * days_per_400y); // 0..146_096

        var civil: CivilDate = .fromDayNumber(day_in_era);
        civil.year += era * 400;

        return civil.toDateTime(seconds_since_midnight, sub_second_us);
    }

    pub fn formatISO8601ExpandedYearWithMilli(dt: DateTime, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{d:0>3}Z", .{
            dt.year,   dt.month,  dt.day,         dt.hour,
            dt.minute, dt.second, dt.millisecond, dt.microsecond,
        });
    }

    pub fn format(dt: DateTime, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try dt.formatISO8601ExpandedYearWithMilli(w);
    }

    pub const RFC3339 = struct {
        /// 0000-9999
        year: u16,
        month: u8,
        day: u8,
        hour: u8,
        minute: u8,
        second: u8,
        millisecond: u16,
        microsecond: u16,
        nanosecond: u16,

        pub const min: @This() = .{
            .year = 0,
            .month = 1,
            .day = 1,
            .hour = 0,
            .minute = 0,
            .second = 0,
            .millisecond = 0,
            .microsecond = 0,
            .nanosecond = 0,
        };

        pub const max: @This() = .{
            .year = 9999,
            .month = 12,
            .day = 31,
            .hour = 23,
            .minute = 59,
            .second = 59,
            .millisecond = 999,
            .microsecond = 999,
            .nanosecond = 999,
        };

        pub fn fromTimestamp(ns_ts: i96) @This() {
            return DateTime.fromTimestampNano(ns_ts).toRFC3339();
        }

        /// 固定长度30字符
        pub fn formatNanoZulu(d: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{d:0>3}{d:0>3}Z", .{
                d.year,        d.month,       d.day,
                d.hour,        d.minute,      d.second,
                d.millisecond, d.microsecond, d.nanosecond,
            });
        }

        /// 固定长度27字符
        pub fn formatMicroZulu(d: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{d:0>3}Z", .{
                d.year,   d.month,  d.day,         d.hour,
                d.minute, d.second, d.millisecond, d.microsecond,
            });
        }

        /// 固定长度24字符
        pub fn formatMilliZulu(d: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{
                d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond,
            });
        }

        pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
            try self.formatMicroZulu(w);
        }
    };
};

const CivilDate = struct {
    year: i32,
    month: u8,
    day: u8,

    /// 天数（自 0000-03-01 起、非负）-> 公历年月日。
    /// 以 3 月 1 日为"年首"，闰日 2/29 落在"年末"，不会被闰日切断跨年；
    /// 逐年剥离 100 年块、4 年块，再做月日换算（153 天为 5 个月的周期）。
    fn fromDayNumber(day_n_in: u64) CivilDate {
        var day_n = day_n_in;

        var temp = 4 * (day_n + days_per_100y + 1) / days_per_400y - 1;
        var year: i32 = @intCast(100 * temp);
        day_n -= days_per_100y * temp + temp / 4;

        temp = 4 * (day_n + days_per_1y + 1) / days_per_4y - 1;
        year += @intCast(temp);
        day_n -= days_per_1y * temp + temp / 4;

        var month = (5 * day_n + 2) / 153;
        const day = day_n - (month * 153 + 2) / 5 + 1;
        month += 3;
        if (month > 12) {
            month -= 12;
            year += 1;
        }

        return .{ .year = year, .month = @intCast(month), .day = @intCast(day) };
    }

    fn toDateTime(self: @This(), seconds_since_midnight: u64, sub_second_us: u64) DateTime {
        return .{
            .year = self.year,
            .month = self.month,
            .day = self.day,
            .hour = @intCast(@divTrunc(seconds_since_midnight, s_per_hour)),
            .minute = @intCast(seconds_since_midnight % s_per_hour / s_per_min),
            .second = @intCast(seconds_since_midnight % s_per_min),
            .millisecond = @intCast(sub_second_us / us_per_ms),
            .microsecond = @intCast(sub_second_us % us_per_ms),
        };
    }
};

test {
    _ = @import("./tests/time.zig");
}
