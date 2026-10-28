const std = @import("std");

const context = @import("context.zig");
const Context = context.Context;
const options = &@import("config.zig").options;

fn enabled(now: i8, target: i8) bool {
    return now >= target;
}

pub var global: Context = .{
    .io = undefined,
    .arena = undefined,
    .ow = undefined,
    .mode = undefined,
};

pub fn log(
    level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const ctx = &global;
    const io = ctx.io;

    if (enabled(ctx.level.load(.monotonic), @backingInt(level)) == false) return;

    const ts = std.Io.Clock.now(.real, io);

    switch (ctx.mode) {
        .blocking => {
            var lw = BlockingloggerWriter.init() catch return;
            defer lw.deinit();

            ctx.formatter.exec(
                level,
                scope,
                format,
                args,
                &lw.interface,
                ctx.arena.child_allocator,
                io,
                ts,
            ) catch return;

            lw.interface.flush() catch return;
        },
        .non_blocking => {
            var storage: [options.max_buffers_per_record + 1][]u8 = undefined;

            var lw = NonBlockingLoggerWriter.init(&storage);
            defer lw.deinit();

            ctx.formatter.exec(
                level,
                scope,
                format,
                args,
                &lw.interface,
                ctx.arena.child_allocator,
                io,
                ts,
            ) catch if (lw.notNeedFlushWhenErr()) return;

            lw.interface.flush() catch return;
        },
    }
}

const BlockingloggerWriter = struct {
    interface: std.Io.Writer,
    err: ?Error = null,

    const Error = std.Io.Writer.Error;

    fn init() !@This() {
        try global.mode.blocking.writer_mutex.lock(global.io);
        return .{ .interface = .{
            .buffer = &.{},
            .vtable = &.{
                .drain = drain,
                .flush = flush,
                .sendFile = std.Io.Writer.unimplementedSendFile,
                .rebase = std.Io.Writer.failingRebase,
            },
        } };
    }

    fn deinit(self: *@This()) void {
        if (self.err != null) {
            global.ow.errorhandler.func(global.io, global.ow.interface);
        }
        global.mode.blocking.writer_mutex.unlock(global.io);
    }

    fn drain(
        w: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        const lw: *@This() = @alignCast(@fieldParentPtr("interface", w));
        const writer = global.ow.interface;
        return writer.vtable.drain(writer, data, splat) catch |e| lw.emitError(e);
    }

    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const lw: *@This() = @alignCast(@fieldParentPtr("interface", w));
        const writer = global.ow.interface;
        writer.writeByte('\n') catch |e| return lw.emitError(e);
        writer.flush() catch |e| return lw.emitError(e);
    }

    fn emitError(self: *@This(), err: Error) Error {
        self.err = err;
        return err;
    }
};

// drain 申请
// flush 提交
// deinit 回收
const NonBlockingLoggerWriter = struct {
    storage: [][]u8,
    remaining: [][]u8,
    used: usize,
    err: ?anyerror = null,
    interface: std.Io.Writer,

    const Error = std.Io.QueueClosedError || std.Io.Writer.Error || error{ Dropped, Truncated };

    fn init(buf: [][]u8) @This() {
        return .{ .storage = buf, .remaining = buf[0 .. buf.len - 1], .used = 0, .interface = .{
            .buffer = &.{},
            .vtable = &.{
                .drain = drain,
                .flush = flush,
                .sendFile = std.Io.Writer.unimplementedSendFile,
                .rebase = std.Io.Writer.failingRebase,
            },
        } };
    }

    fn deinit(self: *@This()) void {
        const buf = self.storage[0..self.used];
        self.freeBuf(buf) catch |e| switch (e) {
            error.Closed => {},
        };
    }

    inline fn notNeedFlushWhenErr(self: @This()) bool {
        // 发生截断时需要flush，发生截断时err为空
        return self.err.? != Error.Truncated;
    }

    fn drain(
        w: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        const lw: *NonBlockingLoggerWriter = @alignCast(@fieldParentPtr("interface", w));

        std.debug.assert(data.len != 0);

        const pool_size = global.mode.non_blocking.pool.size;

        const needed_write_bytes = blk: {
            var bytes: usize = data[data.len - 1].len * splat;
            for (data[0 .. data.len - 1]) |slice| bytes += slice.len;
            break :blk bytes;
        };
        const needed_newbuf_bytes = blk: {
            const remaing_buf_bytes = w.buffer.len - w.end;
            break :blk needed_write_bytes - remaing_buf_bytes;
        };
        const needed_newbuf_count = @divCeil(needed_newbuf_bytes, pool_size);

        const secondary = lw.acquireBuf(needed_newbuf_count) catch |e| switch (e) {
            error.Closed, error.Dropped => |err| {
                lw.err = err;
                return error.WriteFailed;
            },
        };

        const primary = w.buffer[w.end..];
        const end = memcopy(data, splat, primary, secondary) catch |e| {
            lw.err = e;
            w.end = pool_size;
            return error.WriteFailed;
        };

        w.buffer = secondary[secondary.len - 1];
        w.end = end;

        return needed_write_bytes;
    }

    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const lw: *NonBlockingLoggerWriter = @alignCast(@fieldParentPtr("interface", w));

        if (lw.used == 0) return;

        const storage = lw.storage;
        const used = lw.used;
        storage[used - 1] = storage[used - 1][0..w.end];
        storage[used] = @constCast(context.newline);
        const used_storage = storage[0 .. used + 1];

        // const used_storage = lw.storage[0..used];
        // used_storage[used - 1] = used_storage[used - 1][0..w.end];

        lw.submitBuf(used_storage) catch |e| switch (e) {
            error.Closed => {
                lw.err = std.Io.QueueClosedError.Closed;
                return error.WriteFailed;
            },
        };

        lw.used = 0;
    }

    /// src 依次复制进 primary、secondary，切片不够就挨个填充；
    /// 最后一个切片按 splat 指定的总次数重复写入。
    ///
    /// - primary 与 secondary 的各切片按顺序共同视为一段连续缓冲区；
    /// - 单个 src 切片可跨目标切片边界拆分填充，不留空洞；
    /// - splat 为最后一个切片总共写入的次数：splat=1 与不重复时行为一致，
    ///   splat=0 表示最后一个切片不写入；src 为空时 splat 无效（无切片可重复）；
    /// - 总容量不足时，先尽量填满所有目标切片（部分写入），再返回 error.Truncated；
    /// - 成功时，目标切片中的剩余空间与未用到的切片保持原样。
    fn memcopy(src: []const []const u8, splat: usize, primary: []u8, secondary: [][]u8) error{Truncated}!usize {
        const last = src.len - 1;
        var dst = primary; // 当前正在填充的目标切片
        var pos: usize = 0; // dst 内已写入的偏移
        var next: usize = 0; // 下一个待启用的 secondary 切片下标

        // 有效写入序列：src[0..last) 各一次，最后一个切片 splat 次
        for (0..last + splat) |step| {
            var rest = src[if (step < last) step else last];
            while (rest.len > 0) {
                if (pos == dst.len) {
                    if (next == secondary.len) return error.Truncated;
                    dst = secondary[next];
                    next += 1;
                    pos = 0;
                    continue; // 新切片长度可能为 0，回到循环开头再判断
                }
                const n = @min(rest.len, dst.len - pos);
                @memcpy(dst[pos .. pos + n], rest[0..n]);
                pos += n;
                rest = rest[n..];
            }
        }

        return pos;
    }

    const acquireBufError = std.Io.QueueClosedError || error{Dropped};
    inline fn acquireBuf(self: *@This(), count: usize) acquireBufError![][]u8 {
        const remaining = self.remaining;
        const want = if (remaining.len < count) switch (global.mode.non_blocking.record_policy) {
            .drop => return error.Dropped, // TODO metrics
            .truncate => remaining.len, // TODO metrics
        } else count;

        const pool_free = &global.mode.non_blocking.pool.free;
        const real = switch (global.mode.non_blocking.pool_policy) {
            .block => try pool_free.getUncancelable(global.io, remaining[0..want], want),
            .truncate => try pool_free.getUncancelable(global.io, remaining[0..want], 0), // TODO metrics
            .drop => blk: { // TODO metrics
                const real = try pool_free.getUncancelable(global.io, remaining[0..want], 0);
                if (real != want) {
                    self.used += real;
                    return error.Dropped;
                }
                break :blk real;
            },
        };

        self.used += real;
        self.remaining = remaining[real..];

        const pool_size = global.mode.non_blocking.pool.size;
        for (0..real) |i| remaining[i] = remaining[i].ptr[0..pool_size];
        return remaining[0..real];
    }

    inline fn freeBuf(self: @This(), buf: [][]u8) std.Io.QueueClosedError!void {
        _ = self;
        const pool_free = &global.mode.non_blocking.pool.free;
        _ = try pool_free.putUncancelable(global.io, buf, buf.len);
    }

    inline fn submitBuf(self: @This(), buf: [][]u8) std.Io.QueueClosedError!void {
        _ = self;
        const pool_pending = &global.mode.non_blocking.pool.pending;
        _ = try pool_pending.putUncancelable(global.io, buf, buf.len);
    }
};
