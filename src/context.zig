const std = @import("std");

const c = @import("config.zig");

const options = c.options;
const Config = c.Config;
const PoolExhaustionPolicy = c.PoolExhaustionPolicy;
const RecordExhaustionPolicy = c.RecordExhaustionPolicy;
const ErrorHandler = c.ErrorHandler;
const RawOutputWriter = @import("writer.zig").RawOutputWriter;
const Formatter = @import("formatter.zig");
const Metrics = @import("metrics.zig").Metrics;

pub const newline: []const u8 = "\n";

pub const LogEvent = []u8;

const Pool = struct {
    free: std.Io.Queue(LogEvent) = undefined,
    pending: std.Io.Queue(LogEvent) = undefined,
    size: usize = 0,
};

const RunMode = union(enum) {
    blocking: Blocking,
    non_blocking: NonBlocking,

    pub const Blocking = struct {
        writer_mutex: std.Io.Mutex = .init,
    };

    pub const NonBlocking = struct {
        pool: Pool,
        pool_policy: PoolExhaustionPolicy,
        record_policy: RecordExhaustionPolicy,
        tasks: std.Io.Group = .init,
        running: bool = false, // run tasks
        kind: enum { async, concurrent } = .concurrent,
    };
};

pub const OutputWriter = struct {
    interface: *std.Io.Writer,
    kind: Kind,
    errorhandler: ErrorHandler = undefined,

    const Kind = enum {
        custom,
        stdout,
        stderr,
        file,
    };
};

pub const Context = struct {
    inited: bool = init_inited, // init resource
    // closed: bool = init_closed, // run task

    io: std.Io,
    arena: std.heap.ArenaAllocator,

    level: std.atomic.Value(i8) = init_level,
    metrics: Metrics = .{},

    ow: OutputWriter,
    mode: RunMode,
    formatter: Formatter = .{},

    const init_inited: bool = false;
    const init_level: std.atomic.Value(i8) = .init(-1);

    pub fn deinit(self: *@This()) void {
        if (self.inited == false) return;

        const io = self.io;

        if (self.mode == .non_blocking) {
            const mode = &self.mode.non_blocking;
            mode.pool.free.close(io);
            mode.pool.pending.close(io);
            mode.tasks.cancel(io);
            self.ow.interface.flush() catch {}; // TODO need call errorhandler?
        }

        switch (self.ow.kind) {
            .stderr, .stdout => {
                const fw: *std.Io.File.Writer = @alignCast(@fieldParentPtr("interface", self.ow.interface));
                const row: *RawOutputWriter.Stdio = @alignCast(@fieldParentPtr("fw", fw));
                row.deinit(self.arena.allocator());
            },
            .file => {
                const fw: *std.Io.File.Writer = @alignCast(@fieldParentPtr("interface", self.ow.interface));
                const row: *RawOutputWriter.File = @alignCast(@fieldParentPtr("fw", fw));
                row.deinit(self.arena.allocator(), self.io);
            },
            .custom => {},
        }

        var arena = self.arena;
        arena.deinit();

        self.inited = init_inited;
        self.level = init_level;
    }

    pub fn init(io: std.Io, alloc: std.mem.Allocator, config: Config) !@This() {
        var ctx_arena: std.heap.ArenaAllocator = .init(alloc);
        errdefer ctx_arena.deinit();
        const arena = ctx_arena.allocator();

        var ow: OutputWriter = switch (config.output) {
            .stdout => |cfg| stdout: {
                const ow = try arena.create(RawOutputWriter.Stdio);
                errdefer arena.destroy(ow);
                ow.* = try .init(arena, io, .stdout, cfg.bufsize);
                errdefer ow.deinit(arena);
                break :stdout .{ .interface = ow.writer(), .kind = .stdout };
            },
            .stderr => |cfg| stderr: {
                const ow = try arena.create(RawOutputWriter.Stdio);
                errdefer arena.destroy(ow);
                ow.* = try .init(arena, io, .stderr, cfg.bufsize);
                errdefer ow.deinit(arena);
                break :stderr .{ .interface = ow.writer(), .kind = .stderr };
            },
            .file => |cfg| file: {
                const ow = try arena.create(RawOutputWriter.File);
                errdefer arena.destroy(ow);
                ow.* = try .init(arena, io, cfg.path, cfg.bufsize);
                errdefer ow.deinit(arena, io);
                break :file .{ .interface = ow.writer(), .kind = .file };
            },
            .writer => |interface| .{
                .interface = interface,
                .kind = .custom,
            },
        };
        ow.errorhandler = config.errhandler;

        const pattern_has_date: bool = for (config.pattern.tokens) |tokens| {
            if (tokens.needDateTime()) break true;
        } else false;
        const pattern_has_zone: bool = for (config.pattern.tokens) |tokens| {
            if (tokens.needTimeZone()) break true;
        } else false;
        const pattern_has_formatter: bool = for (config.pattern.tokens) |tokens| {
            if (tokens == .custom) break true;
        } else false;

        if (pattern_has_formatter and config.pattern.formatter == null) {
            return error.UserFormatterNull;
        }

        const mode: RunMode = switch (config.mode) {
            .sync => .{ .blocking = .{} },
            .async, .concurrent => |cfg| .{
                .non_blocking = .{
                    .pool_policy = cfg.on_pool_exhausted,
                    .record_policy = cfg.on_record_exhausted,
                    .kind = switch (config.mode) {
                        .async => .async,
                        .concurrent => .concurrent,
                        else => unreachable,
                    },
                    .pool = blk: {
                        const size = cfg.buffer.size;
                        const count = cfg.buffer.count;
                        const pool_buffer_storage = try arena.alloc(u8, size * count);
                        errdefer arena.free(pool_buffer_storage);
                        const pool_free_storage = try arena.alloc(LogEvent, count);
                        errdefer arena.free(pool_free_storage);
                        const pool_pending_storage = try arena.alloc(LogEvent, count * 2);
                        errdefer arena.free(pool_pending_storage);

                        var free_pool_buf = try arena.alloc([]u8, count);
                        defer arena.free(free_pool_buf);
                        for (0..count) |idx| {
                            const baseline = idx * size;
                            free_pool_buf[idx] = pool_buffer_storage[baseline .. baseline + size];
                        }
                        var free: std.Io.Queue(LogEvent) = .init(pool_free_storage);
                        _ = free.putUncancelable(io, free_pool_buf, free_pool_buf.len) catch unreachable;

                        break :blk .{
                            .size = size,
                            .pending = .init(pool_pending_storage),
                            .free = free,
                        };
                    },
                },
            },
        };

        return .{
            .io = io,
            .arena = ctx_arena,
            .ow = ow,
            .inited = true,
            .level = .init(@backingInt(config.level)),
            .mode = mode,
            .formatter = .{
                .userformatter = config.pattern.formatter orelse undefined,
                .timezone = config.timezone,
                .pattern = config.pattern.tokens,
                .pattern_has_datetime = pattern_has_date,
                .pattern_has_timezone = pattern_has_zone,
            },
        };
    }

    pub fn start(self: *@This()) !void {
        if (self.inited == false) return;
        if (self.mode == .non_blocking) {
            const mode = &self.mode.non_blocking;
            const io = self.io;
            switch (mode.kind) {
                .async => mode.tasks.async(io, loop, .{self}),
                .concurrent => try mode.tasks.concurrent(io, loop, .{self}),
            }
            mode.running = true;
        }
    }

    pub fn setLevel(self: *@This(), level: std.log.Level) void {
        self.level.store(@backingInt(level), .monotonic);
    }

    pub fn disable(self: *@This()) void {
        self.level.store(-1, .monotonic);
    }
};

/// writer loop
fn loop(ctx: *Context) void {
    const io = ctx.io;
    const ow = ctx.ow;
    const writer = ow.interface;

    const pending = &ctx.mode.non_blocking.pool.pending;
    const free = &ctx.mode.non_blocking.pool.free;

    // Protect the write call from cancellation
    const old_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_protection);

    var storage: [options.max_buffers_per_batch][]u8 = undefined;
    var storage2: [options.max_buffers_per_batch][]u8 = undefined;

    while (true) {
        var idx: usize = 0;
        const count = pending.getUncancelable(io, &storage, 1) catch |e| switch (e) {
            error.Closed => return,
        };
        const valid = storage[0..count];

        for (valid) |buf| {
            writer.writeAll(buf) catch ow.errorhandler.func(io, writer);
            if (buf.ptr != newline.ptr) {
                storage2[idx] = buf;
                idx += 1;
            }
        }

        _ = free.putUncancelable(io, storage2[0..idx], idx) catch |e| switch (e) {
            error.Closed => {},
        };
    }
}
