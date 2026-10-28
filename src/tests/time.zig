test {
    _ = TimeZone;
    _ = RFC3339;
    _ = DateTime;
}

const TimeZone = struct {
    const formatStrftimeZ = time.TimeZone.formatStrftimeZ;
    const formatRFC3339 = time.TimeZone.formatRFC3339;
    const format = time.TimeZone.format;

    test format {}
    test formatStrftimeZ {}
    test formatRFC3339 {}
};

const RFC3339 = struct {
    const format = time.DateTime.RFC3339.format;
    const formatNanoZulu = time.DateTime.RFC3339.formatNanoZulu;
    const formatMicroZulu = time.DateTime.RFC3339.formatMicroZulu;
    const formatMilliZulu = time.DateTime.RFC3339.formatMilliZulu;

    test formatNanoZulu {}

    test formatMicroZulu {
        const cases = [_]struct { ts: i64, want: []const u8 }{
            .{ .ts = 0, .want = "1970-01-01T00:00:00.000000Z" },
            // negative watchpoint
            .{ .ts = -62167219200000000, .want = "0000-01-01T00:00:00.000000Z" }, // RFC3339 min
            .{ .ts = -62167219200000001, .want = "0000-01-01T00:00:00.000000Z" }, // RFC3339 min-1µs
            .{ .ts = std.math.minInt(i64), .want = "0000-01-01T00:00:00.000000Z" }, // 远低于 min（约 -29 万年）：钳位到 min

            .{ .ts = -1, .want = "1969-12-31T23:59:59.999999Z" }, // 负 1µs：逐级借位
            .{ .ts = -1001, .want = "1969-12-31T23:59:59.998999Z" },
            .{ .ts = -86399999999, .want = "1969-12-31T00:00:00.000001Z" },
            .{ .ts = -14182940_000_000, .want = "1969-07-20T20:17:40.000000Z" }, // Apollo 11 登月
            .{ .ts = -2203977600000000, .want = "1900-02-28T00:00:00.000000Z" },
            .{ .ts = -2203891200000000, .want = "1900-03-01T00:00:00.000000Z" }, // 1900 非闰年：不存在 02-29
            // positive
            .{ .ts = 951782400000000, .want = "2000-02-29T00:00:00.000000Z" }, // 闰世纪年
            .{ .ts = 951868800000000, .want = "2000-03-01T00:00:00.000000Z" },
            .{ .ts = 1000000000000000, .want = "2001-09-09T01:46:40.000000Z" },
            .{ .ts = 1700000000123456, .want = "2023-11-14T22:13:20.123456Z" },
            .{ .ts = 1709164800456000, .want = "2024-02-29T00:00:00.456000Z" }, // 普通闰年
            .{ .ts = 4107456000999999, .want = "2100-02-28T00:00:00.999999Z" }, // 非闰世纪年
            .{ .ts = 4107542400000000, .want = "2100-03-01T00:00:00.000000Z" },
            // .{ .ts = -62198755200000000, .want = "-0001-01-01T00:00:00.000000Z" }, // 负年份（ISO 8601 扩展写法）
            // .{ .ts = std.math.maxInt(i64), .want = "294247-01-10T04:00:54.775807Z" }, // i64 极值
            // Corner case
            .{ .ts = -62167219200000000, .want = "0000-01-01T00:00:00.000000Z" }, // 恰好 min：0000-01-01T00:00:00Z
            .{ .ts = -62167219200000001, .want = "0000-01-01T00:00:00.000000Z" }, // 低于 min 1µs（-0001-12-31T23:59:59.999999）：钳位到 min
            .{ .ts = std.math.minInt(i64), .want = "0000-01-01T00:00:00.000000Z" }, // 远低于 min（约 -29 万年）：钳位到 min
            .{ .ts = 253402300799999999, .want = "9999-12-31T23:59:59.999999Z" }, // 恰好 max：9999-12-31T23:59:59.999999Z
            .{ .ts = 253402300800000000, .want = "9999-12-31T23:59:59.999999Z" }, // 高于 max 1µs（10000-01-01）：钳位到 max
            .{ .ts = std.math.maxInt(i64), .want = "9999-12-31T23:59:59.999999Z" }, // 远高于 max（约 +29 万年）：钳位到 max
        };
        var buf: [27]u8 = undefined;
        for (cases) |c| {
            var w: std.Io.Writer = .fixed(&buf);
            try time.DateTime.fromTimestamp(c.ts).toRFC3339().formatMicroZulu(&w);
            try expectEqualStrings(c.want, w.buffered());
        }
    }

    test formatMilliZulu {}

    test format {
        const dt: time.DateTime.RFC3339 = .fromTimestamp(0);
        var buf1: [27]u8 = undefined;
        var buf2: [27]u8 = undefined;
        {
            var w: std.Io.Writer = .fixed(&buf1);
            try w.print("{f}", .{dt});
        }
        {
            var w: std.Io.Writer = .fixed(&buf2);
            try dt.formatMicroZulu(&w);
        }
        try expectEqualStrings(&buf1, &buf2);
    }
};

const DateTime = struct {
    const formatISO8601ExpandedYearWithMilli = time.DateTime.formatISO8601ExpandedYearWithMilli;
    const fromTimestamp = time.DateTime.fromTimestamp;
    const format = time.DateTime.format;

    test format {
        const dt: time.DateTime = .fromTimestamp(1700000000123456);
        var buf1: [32]u8 = undefined;
        var buf2: [32]u8 = undefined;
        {
            var w: std.Io.Writer = .fixed(&buf1);
            try w.print("{f}", .{dt});
        }
        {
            var w: std.Io.Writer = .fixed(&buf2);
            try dt.formatISO8601ExpandedYearWithMilli(&w);
        }
        try expectEqualStrings(&buf1, &buf2);
    }

    test fromTimestamp {
        inline for ([_]struct { ts: i64, e: time.DateTime, desc: []const u8 = "" }{
            .{ .ts = std.math.minInt(i64), .e = .{
                .year = -290308,
                .month = 12,
                .day = 21,
                .hour = 19,
                .minute = 59,
                .second = 5,
                .millisecond = 224,
                .microsecond = 192,
            }, .desc = "min" },
            .{ .ts = std.math.maxInt(i64), .e = .{
                .year = 294247,
                .month = 1,
                .day = 10,
                .hour = 4,
                .minute = 0,
                .second = 54,
                .millisecond = 775,
                .microsecond = 807,
            }, .desc = "max" },

            // corner case
            .{ .ts = -62_135_596_800_000_001, .e = .{
                .year = 0,
                .month = 12,
                .day = 31,
                .hour = 23,
                .minute = 59,
                .second = 59,
                .millisecond = 999,
                .microsecond = 999,
            }, .desc = "// 0001-01-01 的前一微秒" },
            .{ .ts = -62_162_121_600_000_000, .e = .{
                .year = 0,
                .month = 2,
                .day = 29,
                .hour = 0,
                .minute = 0,
                .second = 0,
                .millisecond = 0,
                .microsecond = 0,
                .nanosecond = 0,
            }, .desc = "// 0000-02-29 存在（0 能被 400 整除）" },
            .{ .ts = -62_162_121_600_000_000 + std.time.s_per_day * std.time.us_per_s, .e = .{
                .year = 0,
                .month = 3,
                .day = 1,
                .hour = 0,
                .minute = 0,
                .second = 0,
                .millisecond = 0,
                .microsecond = 0,
            }, .desc = "// 0000-03-01 的前一天就是 0000-02-29" },

            // 微秒借位 / 跨秒、跨天回绕
            .{ .ts = 0, .e = .{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .millisecond = 0, .microsecond = 0 } },
            .{ .ts = 1, .e = .{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .millisecond = 0, .microsecond = 1 } },
            .{ .ts = -1, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .millisecond = 999, .microsecond = 999 } },
            .{ .ts = -999, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .millisecond = 999, .microsecond = 1 } },
            .{ .ts = -1000, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .millisecond = 999, .microsecond = 0 } },
            .{ .ts = -1001, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .millisecond = 998, .microsecond = 999 } },
            .{ .ts = -1000000, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .millisecond = 0, .microsecond = 0 } },
            .{ .ts = -1000001, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 58, .millisecond = 999, .microsecond = 999 } },
            .{ .ts = -86399999999, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 0, .minute = 0, .second = 0, .millisecond = 0, .microsecond = 1 } },
            .{ .ts = -86400000000, .e = .{ .year = 1969, .month = 12, .day = 31, .hour = 0, .minute = 0, .second = 0, .millisecond = 0, .microsecond = 0 } },
            .{ .ts = -86400000001, .e = .{ .year = 1969, .month = 12, .day = 30, .hour = 23, .minute = 59, .second = 59, .millisecond = 999, .microsecond = 999 } },
            // 1900 非闰年（被 100 整除、不被 400 整除）：2 月只有 28 天
            .{ .ts = -2203977600000000, .e = .{ .year = 1900, .month = 2, .day = 28, .hour = 0, .minute = 0, .second = 0, .millisecond = 0, .microsecond = 0 } },
            .{ .ts = -2203977599000000, .e = .{ .year = 1900, .month = 2, .day = 28, .hour = 0, .minute = 0, .second = 1, .millisecond = 0, .microsecond = 0 } },
            .{ .ts = -2203891200000000, .e = .{ .year = 1900, .month = 3, .day = 1, .hour = 0, .minute = 0, .second = 0, .millisecond = 0, .microsecond = 0 } },
            // 亚秒字段拆分（毫秒 + 微秒）
            .{ .ts = 1234567890123456, .e = .{ .year = 2009, .month = 2, .day = 13, .hour = 23, .minute = 31, .second = 30, .millisecond = 123, .microsecond = 456 } },
            // 上下界锚点：0001-01-01（Python datetime 下限）与 9999-12-31
            .{ .ts = -62135596800000000, .e = .{ .year = 1, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .millisecond = 0, .microsecond = 0 } },
            .{ .ts = 253402300799000000, .e = .{ .year = 9999, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .millisecond = 0, .microsecond = 0 } },
        }) |case| try expectDateTime(case.e, .fromTimestamp(case.ts), case.desc);
    }

    // Python datetime 只覆盖 1..9999 年；公历以 400 年为精确周期，
    // 把负时间戳平移 +1200 年（3 个周期）后应得到完全相同的月日时分秒微秒、
    // 年份恰好相差 1200。这里用确定性 LCG 生成 1000 个负时间戳做性质检验。
    test "负数与平移 1200 年的正数结果一致（400 年周期性质）" {
        const cycle_us: i64 = 146097 * std.time.s_per_day * std.time.us_per_s;
        var lcg: u64 = 0x9E37_79B9_7F4A_7C15;
        var i: usize = 0;
        while (i < 1000) : (i += 1) {
            lcg = lcg *% 6364136223846793005 +% 1442695040888963407;
            const r = @rem(@as(i64, @intCast(lcg >> 16)), 2 * cycle_us); // 负到约 800 年前
            const ts: i64 = -(r + 1); // 保证为负

            const a = DateTime.fromTimestamp(ts);
            const b = DateTime.fromTimestamp(ts + 3 * cycle_us);

            try expectEqual(b.year - 1200, a.year);
            try expectEqual(b.month, a.month);
            try expectEqual(b.day, a.day);
            try expectEqual(b.hour, a.hour);
            try expectEqual(b.minute, a.minute);
            try expectEqual(b.second, a.second);
            try expectEqual(b.millisecond, a.millisecond);
            try expectEqual(b.microsecond, a.microsecond);
        }
    }

    // 100 个随机时间戳（50 负 + 50 正，固定种子可复现），期望值由 Python datetime 生成。
    test "随机对照（Python datetime 基准）" {
        const cases = [_]struct { ts: i64, e: time.DateTime }{
            // negative
            .{ .ts = -20317886587682683, .e = .{ .year = 1326, .month = 2, .day = 25, .hour = 6, .minute = 36, .second = 52, .millisecond = 317, .microsecond = 317 } },
            .{ .ts = -32996746025457844, .e = .{ .year = 924, .month = 5, .day = 17, .hour = 5, .minute = 12, .second = 54, .millisecond = 542, .microsecond = 156 } },
            .{ .ts = -16150398519813117, .e = .{ .year = 1458, .month = 3, .day = 20, .hour = 2, .minute = 11, .second = 20, .millisecond = 186, .microsecond = 883 } },
            .{ .ts = -45330903132088030, .e = .{ .year = 533, .month = 7, .day = 9, .hour = 18, .minute = 27, .second = 47, .millisecond = 911, .microsecond = 970 } },
            .{ .ts = -33382309102152502, .e = .{ .year = 912, .month = 2, .day = 27, .hour = 16, .minute = 21, .second = 37, .millisecond = 847, .microsecond = 498 } },
            .{ .ts = -62126305043375834, .e = .{ .year = 1, .month = 4, .day = 18, .hour = 13, .minute = 2, .second = 36, .millisecond = 624, .microsecond = 166 } },
            .{ .ts = -46304768647091305, .e = .{ .year = 502, .month = 8, .day = 30, .hour = 4, .minute = 15, .second = 52, .millisecond = 908, .microsecond = 695 } },
            .{ .ts = -58251992803785438, .e = .{ .year = 124, .month = 1, .day = 26, .hour = 2, .minute = 53, .second = 16, .millisecond = 214, .microsecond = 562 } },
            .{ .ts = -17122777538717610, .e = .{ .year = 1427, .month = 5, .day = 27, .hour = 16, .minute = 54, .second = 21, .millisecond = 282, .microsecond = 390 } },
            .{ .ts = -16794346091184673, .e = .{ .year = 1437, .month = 10, .day = 22, .hour = 23, .minute = 51, .second = 48, .millisecond = 815, .microsecond = 327 } },
            .{ .ts = -53475988982635405, .e = .{ .year = 275, .month = 5, .day = 31, .hour = 22, .minute = 36, .second = 57, .millisecond = 364, .microsecond = 595 } },
            .{ .ts = -32695694241825532, .e = .{ .year = 933, .month = 11, .day = 30, .hour = 14, .minute = 42, .second = 38, .millisecond = 174, .microsecond = 468 } },
            .{ .ts = -54274612258713337, .e = .{ .year = 250, .month = 2, .day = 8, .hour = 14, .minute = 49, .second = 1, .millisecond = 286, .microsecond = 663 } },
            .{ .ts = -7882736824686597, .e = .{ .year = 1720, .month = 3, .day = 16, .hour = 14, .minute = 52, .second = 55, .millisecond = 313, .microsecond = 403 } },
            .{ .ts = -13607706868160812, .e = .{ .year = 1538, .month = 10, .day = 16, .hour = 9, .minute = 25, .second = 31, .millisecond = 839, .microsecond = 188 } },
            .{ .ts = -4704985222089662, .e = .{ .year = 1820, .month = 11, .day = 27, .hour = 3, .minute = 39, .second = 37, .millisecond = 910, .microsecond = 338 } },
            .{ .ts = -51992382222704469, .e = .{ .year = 322, .month = 6, .day = 6, .hour = 7, .minute = 36, .second = 17, .millisecond = 295, .microsecond = 531 } },
            .{ .ts = -53599589162068515, .e = .{ .year = 271, .month = 7, .day = 1, .hour = 9, .minute = 13, .second = 57, .millisecond = 931, .microsecond = 485 } },
            .{ .ts = -58163071373141453, .e = .{ .year = 126, .month = 11, .day = 20, .hour = 7, .minute = 17, .second = 6, .millisecond = 858, .microsecond = 547 } },
            .{ .ts = -11247775814205470, .e = .{ .year = 1613, .month = 7, .day = 28, .hour = 9, .minute = 49, .second = 45, .millisecond = 794, .microsecond = 530 } },
            .{ .ts = -9185882550138884, .e = .{ .year = 1678, .month = 11, .day = 28, .hour = 21, .minute = 57, .second = 29, .millisecond = 861, .microsecond = 116 } },
            .{ .ts = -43890640547278682, .e = .{ .year = 579, .month = 2, .day = 28, .hour = 11, .minute = 24, .second = 12, .millisecond = 721, .microsecond = 318 } },
            .{ .ts = -36349522957053768, .e = .{ .year = 818, .month = 2, .day = 16, .hour = 22, .minute = 17, .second = 22, .millisecond = 946, .microsecond = 232 } },
            .{ .ts = -10133619930001431, .e = .{ .year = 1648, .month = 11, .day = 16, .hour = 17, .minute = 34, .second = 29, .millisecond = 998, .microsecond = 569 } },
            .{ .ts = -21898034248556430, .e = .{ .year = 1276, .month = 1, .day = 29, .hour = 12, .minute = 42, .second = 31, .millisecond = 443, .microsecond = 570 } },
            .{ .ts = -41979227808105853, .e = .{ .year = 639, .month = 9, .day = 25, .hour = 7, .minute = 23, .second = 11, .millisecond = 894, .microsecond = 147 } },
            .{ .ts = -54505482048885907, .e = .{ .year = 242, .month = 10, .day = 16, .hour = 12, .minute = 19, .second = 11, .millisecond = 114, .microsecond = 93 } },
            .{ .ts = -54688840113925576, .e = .{ .year = 236, .month = 12, .day = 24, .hour = 7, .minute = 31, .second = 26, .millisecond = 74, .microsecond = 424 } },
            .{ .ts = -4068080037996589, .e = .{ .year = 1841, .month = 2, .day = 1, .hour = 17, .minute = 46, .second = 2, .millisecond = 3, .microsecond = 411 } },
            .{ .ts = -55944236254025863, .e = .{ .year = 197, .month = 3, .day = 13, .hour = 6, .minute = 22, .second = 25, .millisecond = 974, .microsecond = 137 } },
            .{ .ts = -21495327322067266, .e = .{ .year = 1288, .month = 11, .day = 2, .hour = 11, .minute = 44, .second = 37, .millisecond = 932, .microsecond = 734 } },
            .{ .ts = -21226620790739407, .e = .{ .year = 1297, .month = 5, .day = 9, .hour = 12, .minute = 26, .second = 49, .millisecond = 260, .microsecond = 593 } },
            .{ .ts = -15953074483752952, .e = .{ .year = 1464, .month = 6, .day = 19, .hour = 22, .minute = 25, .second = 16, .millisecond = 247, .microsecond = 48 } },
            .{ .ts = -3943900541736259, .e = .{ .year = 1845, .month = 1, .day = 9, .hour = 0, .minute = 4, .second = 18, .millisecond = 263, .microsecond = 741 } },
            .{ .ts = -34550817282036081, .e = .{ .year = 875, .month = 2, .day = 16, .hour = 6, .minute = 45, .second = 17, .millisecond = 963, .microsecond = 919 } },
            .{ .ts = -3715020322669623, .e = .{ .year = 1852, .month = 4, .day = 11, .hour = 1, .minute = 54, .second = 37, .millisecond = 330, .microsecond = 377 } },
            .{ .ts = -15005051475937743, .e = .{ .year = 1494, .month = 7, .day = 5, .hour = 10, .minute = 8, .second = 44, .millisecond = 62, .microsecond = 257 } },
            .{ .ts = -50834781864972764, .e = .{ .year = 359, .month = 2, .day = 10, .hour = 11, .minute = 15, .second = 35, .millisecond = 27, .microsecond = 236 } },
            .{ .ts = -22018638042410745, .e = .{ .year = 1272, .month = 4, .day = 3, .hour = 15, .minute = 39, .second = 17, .millisecond = 589, .microsecond = 255 } },
            .{ .ts = -12923253057127723, .e = .{ .year = 1560, .month = 6, .day = 24, .hour = 7, .minute = 29, .second = 2, .millisecond = 872, .microsecond = 277 } },
            .{ .ts = -15759290410390205, .e = .{ .year = 1470, .month = 8, .day = 10, .hour = 19, .minute = 19, .second = 49, .millisecond = 609, .microsecond = 795 } },
            .{ .ts = -6343874006523466, .e = .{ .year = 1768, .month = 12, .day = 20, .hour = 12, .minute = 46, .second = 33, .millisecond = 476, .microsecond = 534 } },
            .{ .ts = -19066065848171808, .e = .{ .year = 1365, .month = 10, .day = 26, .hour = 22, .minute = 35, .second = 51, .millisecond = 828, .microsecond = 192 } },
            .{ .ts = -4713017794387428, .e = .{ .year = 1820, .month = 8, .day = 26, .hour = 4, .minute = 23, .second = 25, .millisecond = 612, .microsecond = 572 } },
            .{ .ts = -11569971550735172, .e = .{ .year = 1603, .month = 5, .day = 13, .hour = 7, .minute = 0, .second = 49, .millisecond = 264, .microsecond = 828 } },
            .{ .ts = -24155491927587586, .e = .{ .year = 1204, .month = 7, .day = 17, .hour = 13, .minute = 7, .second = 52, .millisecond = 412, .microsecond = 414 } },
            .{ .ts = -8650329370184456, .e = .{ .year = 1695, .month = 11, .day = 18, .hour = 10, .minute = 43, .second = 49, .millisecond = 815, .microsecond = 544 } },
            .{ .ts = -38654909148605137, .e = .{ .year = 745, .month = 1, .day = 28, .hour = 5, .minute = 14, .second = 11, .millisecond = 394, .microsecond = 863 } },
            .{ .ts = -43749177042387991, .e = .{ .year = 583, .month = 8, .day = 23, .hour = 18, .minute = 49, .second = 17, .millisecond = 612, .microsecond = 9 } },
            .{ .ts = -11036380959807928, .e = .{ .year = 1620, .month = 4, .day = 9, .hour = 2, .minute = 37, .second = 20, .millisecond = 192, .microsecond = 72 } },
            // positive
            .{ .ts = 13431956928492293, .e = .{ .year = 2395, .month = 8, .day = 23, .hour = 11, .minute = 8, .second = 48, .millisecond = 492, .microsecond = 293 } },
            .{ .ts = 78054289768551560, .e = .{ .year = 4443, .month = 6, .day = 11, .hour = 3, .minute = 9, .second = 28, .millisecond = 551, .microsecond = 560 } },
            .{ .ts = 72596440292778005, .e = .{ .year = 4270, .month = 6, .day = 28, .hour = 13, .minute = 51, .second = 32, .millisecond = 778, .microsecond = 5 } },
            .{ .ts = 149064141817454454, .e = .{ .year = 6693, .month = 8, .day = 27, .hour = 10, .minute = 3, .second = 37, .millisecond = 454, .microsecond = 454 } },
            .{ .ts = 207695201169814967, .e = .{ .year = 8551, .month = 8, .day = 7, .hour = 15, .minute = 26, .second = 9, .millisecond = 814, .microsecond = 967 } },
            .{ .ts = 174915189114721802, .e = .{ .year = 7512, .month = 11, .day = 4, .hour = 8, .minute = 31, .second = 54, .millisecond = 721, .microsecond = 802 } },
            .{ .ts = 160448217321322281, .e = .{ .year = 7054, .month = 5, .day = 27, .hour = 13, .minute = 15, .second = 21, .millisecond = 322, .microsecond = 281 } },
            .{ .ts = 81067109168266017, .e = .{ .year = 4538, .month = 11, .day = 30, .hour = 17, .minute = 26, .second = 8, .millisecond = 266, .microsecond = 17 } },
            .{ .ts = 66037182339359603, .e = .{ .year = 4062, .month = 8, .day = 20, .hour = 5, .minute = 45, .second = 39, .millisecond = 359, .microsecond = 603 } },
            .{ .ts = 16163947141180054, .e = .{ .year = 2482, .month = 3, .day = 19, .hour = 17, .minute = 19, .second = 1, .millisecond = 180, .microsecond = 54 } },
            .{ .ts = 159451674499778499, .e = .{ .year = 7022, .month = 10, .day = 28, .hour = 11, .minute = 48, .second = 19, .millisecond = 778, .microsecond = 499 } },
            .{ .ts = 62822046260070999, .e = .{ .year = 3960, .month = 10, .day = 2, .hour = 0, .minute = 24, .second = 20, .millisecond = 70, .microsecond = 999 } },
            .{ .ts = 43429821017447189, .e = .{ .year = 3346, .month = 3, .day = 27, .hour = 23, .minute = 10, .second = 17, .millisecond = 447, .microsecond = 189 } },
            .{ .ts = 208117932297478090, .e = .{ .year = 8564, .month = 12, .day = 29, .hour = 8, .minute = 44, .second = 57, .millisecond = 478, .microsecond = 90 } },
            .{ .ts = 239414329834473953, .e = .{ .year = 9556, .month = 9, .day = 27, .hour = 4, .minute = 30, .second = 34, .millisecond = 473, .microsecond = 953 } },
            .{ .ts = 135221490980323094, .e = .{ .year = 6254, .month = 12, .day = 31, .hour = 13, .minute = 16, .second = 20, .millisecond = 323, .microsecond = 94 } },
            .{ .ts = 99780304446758283, .e = .{ .year = 5131, .month = 11, .day = 30, .hour = 15, .minute = 14, .second = 6, .millisecond = 758, .microsecond = 283 } },
            .{ .ts = 161522012663155061, .e = .{ .year = 7088, .month = 6, .day = 5, .hour = 17, .minute = 44, .second = 23, .millisecond = 155, .microsecond = 61 } },
            .{ .ts = 236753626776745875, .e = .{ .year = 9472, .month = 6, .day = 4, .hour = 0, .minute = 19, .second = 36, .millisecond = 745, .microsecond = 875 } },
            .{ .ts = 125127897323455988, .e = .{ .year = 5935, .month = 2, .day = 23, .hour = 13, .minute = 15, .second = 23, .millisecond = 455, .microsecond = 988 } },
            .{ .ts = 241840644282181801, .e = .{ .year = 9633, .month = 8, .day = 16, .hour = 12, .minute = 44, .second = 42, .millisecond = 181, .microsecond = 801 } },
            .{ .ts = 138359700927615721, .e = .{ .year = 6354, .month = 6, .day = 12, .hour = 10, .minute = 15, .second = 27, .millisecond = 615, .microsecond = 721 } },
            .{ .ts = 146736907390579585, .e = .{ .year = 6619, .month = 11, .day = 28, .hour = 20, .minute = 3, .second = 10, .millisecond = 579, .microsecond = 585 } },
            .{ .ts = 129734313426481601, .e = .{ .year = 6081, .month = 2, .day = 11, .hour = 13, .minute = 17, .second = 6, .millisecond = 481, .microsecond = 601 } },
            .{ .ts = 16525672624165215, .e = .{ .year = 2493, .month = 9, .day = 4, .hour = 8, .minute = 37, .second = 4, .millisecond = 165, .microsecond = 215 } },
            .{ .ts = 112339444435163955, .e = .{ .year = 5529, .month = 11, .day = 24, .hour = 1, .minute = 13, .second = 55, .millisecond = 163, .microsecond = 955 } },
            .{ .ts = 221140007352947470, .e = .{ .year = 8977, .month = 8, .day = 24, .hour = 19, .minute = 49, .second = 12, .millisecond = 947, .microsecond = 470 } },
            .{ .ts = 83565075345007318, .e = .{ .year = 4618, .month = 1, .day = 27, .hour = 8, .minute = 55, .second = 45, .millisecond = 7, .microsecond = 318 } },
            .{ .ts = 105524602628477778, .e = .{ .year = 5313, .month = 12, .day = 10, .hour = 13, .minute = 37, .second = 8, .millisecond = 477, .microsecond = 778 } },
            .{ .ts = 183048235316965411, .e = .{ .year = 7770, .month = 7, .day = 26, .hour = 20, .minute = 1, .second = 56, .millisecond = 965, .microsecond = 411 } },
            .{ .ts = 26034655976834725, .e = .{ .year = 2795, .month = 1, .day = 3, .hour = 0, .minute = 52, .second = 56, .millisecond = 834, .microsecond = 725 } },
            .{ .ts = 132614546737566165, .e = .{ .year = 6172, .month = 5, .day = 21, .hour = 14, .minute = 5, .second = 37, .millisecond = 566, .microsecond = 165 } },
            .{ .ts = 188010419035636231, .e = .{ .year = 7927, .month = 10, .day = 25, .hour = 12, .minute = 23, .second = 55, .millisecond = 636, .microsecond = 231 } },
            .{ .ts = 49022852613787562, .e = .{ .year = 3523, .month = 6, .day = 23, .hour = 3, .minute = 3, .second = 33, .millisecond = 787, .microsecond = 562 } },
            .{ .ts = 64539291300558654, .e = .{ .year = 4015, .month = 3, .day = 3, .hour = 12, .minute = 55, .second = 0, .millisecond = 558, .microsecond = 654 } },
            .{ .ts = 13656339546430230, .e = .{ .year = 2402, .month = 10, .day = 2, .hour = 11, .minute = 39, .second = 6, .millisecond = 430, .microsecond = 230 } },
            .{ .ts = 105869389980626661, .e = .{ .year = 5324, .month = 11, .day = 13, .hour = 3, .minute = 53, .second = 0, .millisecond = 626, .microsecond = 661 } },
            .{ .ts = 188406951177516612, .e = .{ .year = 7940, .month = 5, .day = 19, .hour = 0, .minute = 12, .second = 57, .millisecond = 516, .microsecond = 612 } },
            .{ .ts = 149212602394577732, .e = .{ .year = 6698, .month = 5, .day = 11, .hour = 17, .minute = 6, .second = 34, .millisecond = 577, .microsecond = 732 } },
            .{ .ts = 1237825861906893, .e = .{ .year = 2009, .month = 3, .day = 23, .hour = 16, .minute = 31, .second = 1, .millisecond = 906, .microsecond = 893 } },
            .{ .ts = 224291355010930425, .e = .{ .year = 9077, .month = 7, .day = 5, .hour = 18, .minute = 10, .second = 10, .millisecond = 930, .microsecond = 425 } },
            .{ .ts = 184562693648270184, .e = .{ .year = 7818, .month = 7, .day = 24, .hour = 6, .minute = 54, .second = 8, .millisecond = 270, .microsecond = 184 } },
            .{ .ts = 218709712555394370, .e = .{ .year = 8900, .month = 8, .day = 20, .hour = 9, .minute = 55, .second = 55, .millisecond = 394, .microsecond = 370 } },
            .{ .ts = 204830820073089709, .e = .{ .year = 8460, .month = 10, .day = 30, .hour = 2, .minute = 1, .second = 13, .millisecond = 89, .microsecond = 709 } },
            .{ .ts = 206020465690369289, .e = .{ .year = 8498, .month = 7, .day = 12, .hour = 3, .minute = 8, .second = 10, .millisecond = 369, .microsecond = 289 } },
            .{ .ts = 35994193342117450, .e = .{ .year = 3110, .month = 8, .day = 12, .hour = 11, .minute = 2, .second = 22, .millisecond = 117, .microsecond = 450 } },
            .{ .ts = 13031571907460641, .e = .{ .year = 2382, .month = 12, .day = 15, .hour = 9, .minute = 5, .second = 7, .millisecond = 460, .microsecond = 641 } },
            .{ .ts = 20216718198769118, .e = .{ .year = 2610, .month = 8, .day = 23, .hour = 19, .minute = 3, .second = 18, .millisecond = 769, .microsecond = 118 } },
            .{ .ts = 67805188534466637, .e = .{ .year = 4118, .month = 8, .day = 30, .hour = 6, .minute = 35, .second = 34, .millisecond = 466, .microsecond = 637 } },
            .{ .ts = 164773713726111489, .e = .{ .year = 7191, .month = 6, .day = 22, .hour = 4, .minute = 2, .second = 6, .millisecond = 111, .microsecond = 489 } },
        };
        for (cases) |c| try expectDateTime(c.e, .fromTimestamp(c.ts), "");
    }
};

fn expectDateTime(expected: time.DateTime, actual: time.DateTime, desc: []const u8) !void {
    const e = expected;
    const a = actual;
    expectEqualDeep(e, a) catch |err| {
        if (desc.len != 0) std.debug.print("Desc: {s}\n", .{desc});
        std.debug.print("ts: expected {d}-{d}-{d} {d}:{d}:{d}.{d}{d}{d} but got {d}-{d}-{d} {d}:{d}:{d}.{d}{d}{d}\n", .{
            e.year,        e.month,       e.day,
            e.hour,        e.minute,      e.second,
            e.millisecond, e.microsecond, e.nanosecond,
            a.year,        a.month,       a.day,
            a.hour,        a.minute,      a.second,
            a.millisecond, a.microsecond, a.nanosecond,
        });
        return err;
    };
}

const expectEqual = std.testing.expectEqual;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqualStrings = std.testing.expectEqualStrings;

const time = @import("../time.zig");

const std = @import("std");
