//! The global logging interface.
//!
//! Call `init` once before logging or changing settings, log through the
//! namespace returned by `Log`, and call `deinit` to release the logger.

const std = @import("std");

const Logger = @import("logger.zig");
const Config = @import("config.zig").Config;

var mutex: std.Io.Mutex = .init;

pub const InitError = std.Io.ConcurrentError || std.mem.Allocator.Error || std.Io.File.OpenError || error{
    Initialized,
    UserFormatterNull,
};

/// Initializes the global logger with `config`.
///
/// You must call `deinit()` to clean up allocated resources.
///
/// Calling it while a logger is initialized returns `error.Initialized`; call
/// `deinit` first to reconfigure. A failed call leaves no logger behind, so it
/// can be retried.
///
/// Also returns `error.UserFormatterNull` if `config.pattern` has custom fields
/// but no formatter, and forwards the errors of allocating and opening the
/// output.
///
/// - Thread-safe: concurrent calls are serialized.
pub fn init(io: std.Io, gpa: std.mem.Allocator, config: Config) InitError!void {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);

    if (Logger.global.inited) return error.Initialized;

    Logger.global = try .init(io, gpa, config);
    errdefer Logger.global.deinit();
    try Logger.global.start();
}

/// Releases the global logger.
///
/// Stops the writer task, flushes the output, and frees the resources the
/// logger owns. Does nothing when no logger is initialized, so it is safe to
/// call more than once.
///
/// - Thread-safe.
pub fn deinit(io: std.Io) void {
    mutex.lockUncancelable(io);
    defer mutex.unlock(io);
    Logger.global.deinit();
}

/// Sets the lowest level that is logged.
///
/// Records below `level` are discarded before formatting. Takes effect
/// immediately, including for other threads.
///
/// - Thread-safe.
pub fn setLevel(level: std.log.Level) void {
    Logger.global.setLevel(level);
}

/// Disables all logging until `setLevel` is called again.
///
/// Takes effect immediately, including for other threads.
///
/// - Thread-safe.
pub fn disable() void {
    Logger.global.disable();
}

/// Returns a logging namespace that tags every record with `scope`.
///
/// The namespace has one function per level, mirroring `std.log`; `scope` is a
/// `@EnumLiteral()` rendered by the `{@scope}` pattern field. All of its
/// functions are thread-safe.
pub fn Log(comptime scope: @EnumLiteral()) type {
    return struct {
        pub fn err(comptime format: []const u8, args: anytype) void {
            @branchHint(.cold);
            Logger.log(.err, scope, format, args);
        }
        pub fn warn(comptime format: []const u8, args: anytype) void {
            Logger.log(.warn, scope, format, args);
        }
        pub fn info(comptime format: []const u8, args: anytype) void {
            Logger.log(.info, scope, format, args);
        }
        pub fn debug(comptime format: []const u8, args: anytype) void {
            Logger.log(.debug, scope, format, args);
        }
    };
}
