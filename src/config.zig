//! Configuration for ConsiseLog.
//!
//! The values in this file are read once, when the logger is initialized, and
//! copied into the logger's own state; changing them afterwards has no effect
//! on a running logger. See `Config` for the settings chosen per logger and
//! `Options` for the limits fixed at compile time.

const std = @import("std");

const root = @import("root");
const p = @import("pattern.zig");
const h = @import("helper.zig");
const PatternToken = p.PatternToken;

/// Compile-time settings, overridable by the root source file.
///
/// A root source file can declare `pub const consiselog_options: Options` to
/// override the values below for the whole program; when it does not, the
/// defaults declared in `Options` apply. The values must be known at comptime
/// because they size fixed arrays on the logging path.
pub const options: Options = if (@hasDecl(root, "consiselog_options")) root.consiselog_options else .{};

/// Limits on the blocks a log call may occupy, and on the size of one write
/// burst.
///
/// Both limits count blocks of the kind described by `BufferPool`, not bytes.
pub const Options = struct {
    /// The maximum number of blocks one log record may occupy.
    ///
    /// A record that needs one more block is handled according to
    /// `AsyncConfig.on_record_exhausted`. The blocks a record holds are
    /// returned to the pool once the record has been written.
    max_buffers_per_record: usize = 16,

    /// The maximum number of blocks the writer task takes from the pending
    /// queue in one batch, i.e. the upper bound of a single write burst.
    max_buffers_per_batch: usize = 16,
};

/// Settings accepted by `consiselog.init`.
///
/// Every field is read once during initialization; mutating a `Config` after
/// the logger has been initialized has no effect. The log level is the only
/// setting that can be changed while the logger is running, see
/// `consiselog.setLevel` and `consiselog.disable`.
///
/// Example:
/// ```
/// try consiselog.init(io, gpa, .{
///     .level = .debug,
///     .output = .{ .file = .{ .path = "app.log" } },
///     .pattern = .parse("[{@RFC3339}] [{@scope}] {@msg}"),
/// });
/// ```
pub const Config = struct {
    /// The lowest level that is written out.
    ///
    /// Records below this level are discarded before any formatting work is
    /// done. The default depends on the build mode of the root module.
    level: Level = std.log.default_level,

    /// How a record is handed over to the output.
    ///
    /// `sync` formats and writes on the calling thread, while `async` and
    /// `concurrent` queue the record to a writer task and return. See
    /// `RunningMode`.
    mode: RunningMode = .default,

    /// The destination records are written to, and the size of the buffer used
    /// on the way there.
    output: Output = .default,

    /// Called when writing to `output` fails.
    ///
    /// See `ErrorHandler` for the callback and the two predefined handlers.
    errhandler: ErrorHandler = .default,

    /// The time zone used to render the date and time fields named by
    /// `pattern`.
    timezone: TimeZoneOffset = .default,

    /// The layout of a formatted record, along with the callback used by
    /// custom `{#id}` fields.
    pattern: Pattern = .default,

    /// A `Config` with every field set to its default value.
    ///
    /// Equivalent to `.{}`, since all fields have defaults.
    pub const default: Config = .{};
};

pub const Level = std.log.Level;

/// How a log call delivers its record to the output.
///
/// In the `sync` mode the record has reached the destination by the time the
/// call returns. The other two modes only queue the record, so the call
/// returns before the write happens and a full queue is handled according to
/// the policies in `AsyncConfig`.
pub const RunningMode = union(enum) {
    /// Format and write the record on the calling thread.
    ///
    /// Concurrent calls are serialized, so their records never interleave. Use
    /// this when the output is cheap, or when records must not be lost when
    /// the process exits abruptly.
    sync,

    /// Queue the record and let a task write it.
    ///
    /// The task shares the thread that drives the `Io` instance, so this mode
    /// needs an `Io` implementation that supports stackful tasks, but not
    /// necessarily threads.
    async: AsyncConfig,

    /// Queue the record and let a dedicated thread write it.
    ///
    /// Requires an `Io` implementation that can spawn threads, such as the
    /// default one. A slow destination delays the writer thread rather than
    /// the callers, until the pool of blocks runs out.
    concurrent: AsyncConfig,

    /// The default mode: `concurrent` with default settings.
    pub const default: @This() = .{ .concurrent = .default };
};

/// Settings for the `async` and `concurrent` running modes.
///
/// A record is formatted into blocks borrowed from `buffer` and submitted to
/// the writer task. `on_pool_exhausted` decides what happens when the pool is
/// empty, and `on_record_exhausted` what happens when a single record has used
/// up its quota.
pub const AsyncConfig = struct {
    /// The pool of blocks that formatted records are built from.
    buffer: BufferPool = .default,

    /// What to do when the pool has no free block left.
    ///
    /// The writer task returns blocks to the pool, so in `block` mode a record
    /// can always make progress eventually.
    on_pool_exhausted: PoolExhaustionPolicy = .block,

    /// What to do when a record already holds `max_buffers_per_record` blocks
    /// and needs one more.
    on_record_exhausted: RecordExhaustionPolicy = .truncate,

    const default: @This() = .{};
};

/// The fixed-size buffers that formatted records are built in.
///
/// The pool holds `count` blocks of `size` bytes each. A block is owned by one
/// record at a time, which lets the writer task read a finished block without
/// copying it out.
pub const BufferPool = struct {
    /// Size of one block in bytes.
    size: usize = 4096,

    /// Number of blocks in the pool.
    count: usize = 32,

    /// A pool with the default block size and block count.
    pub const default: BufferPool = .{};
};

/// What a log call does when `BufferPool` has no free block.
pub const PoolExhaustionPolicy = enum {
    /// Wait until the writer task returns a block, then continue.
    ///
    /// The record is written in full, at the cost of blocking the caller.
    block,

    /// Give up and discard the whole record.
    ///
    /// Blocks already taken by the call are returned to the pool, so nothing
    /// of this record is printed.
    drop,

    /// Stop formatting and hand over what has been formatted so far.
    ///
    /// Blocks already taken stay with the partial record and are returned
    /// after it is written; the rest of the record is not printed.
    truncate,
};

/// What a log call does when the record has used `max_buffers_per_record`
/// blocks and needs another one.
///
/// Waiting cannot help here, because the quota does not grow while the record
/// is being formatted, so the call either drops the record or prints what fits.
pub const RecordExhaustionPolicy = enum {
    /// Discard the record; nothing is printed.
    drop,

    /// Print the part of the record that fits in the quota.
    truncate,
};

/// The arguments passed to a `UserFormatter`.
pub const UserFormatterContext = struct {
    /// The severity of the record being formatted.
    level: std.log.Level,

    /// The timestamp taken when the log call started.
    ts: std.Io.Timestamp,

    /// Receives the bytes rendered for the field.
    ///
    /// Only valid for the duration of the call.
    writer: *std.Io.Writer,

    /// The name written between `{#` and `}`, i.e. without the `#`.
    id: []const u8,

    /// The `Io` instance used by the logger.
    io: std.Io,

    /// The allocator used by the logger; valid for the lifetime of the logger.
    gpa: std.mem.Allocator,
};

/// Renders a custom `{#id}` field into `ctx.writer`.
///
/// `ctx.id` names the field, so one formatter can serve several fields. An
/// error aborts the record; log calls have no error return, so the error is not
/// passed on to the caller. Errors writing to the destination are reported
/// through `ErrorHandler` instead.
pub const UserFormatter = *const fn (ctx: UserFormatterContext) std.Io.Writer.Error!void;

/// The layout of a formatted record, parsed from a pattern string at compile
/// time.
///
/// A pattern is literal text with fields following this format:
/// ```
/// {@name}   built-in field
/// {%field}  strftime field
/// {#id}     custom field
/// ```
///
/// The examples below assume a `.utc` time zone, scope `main`, level `.info`,
/// and the timestamp `2014-10-02T15:01:23.045123456Z`.
///
/// Built-in fields:
/// - `{@msg}`: the message, rendered from the log call's `format` and `args`,
///   e.g. `starting up`
/// - `{@scope}`: the scope of the logging namespace, e.g. `main`
/// - `{@level}`: the level in full and lowercase, e.g. `info`
/// - `{@LEVEL}`: the level as one uppercase letter, e.g. `I`
/// - `{@RFC3339}`: date and time with the numeric offset of `timezone`, e.g.
///   `2014-10-02T15:01:23.045123456+00:00`
/// - `{@RFC3339Z}`: date and time with a `Z` suffix, e.g.
///   `2014-10-02T15:01:23.045123456Z`
/// - `{@ms}`, `{@us}`, `{@ns}`: the sub-second part of the timestamp, three
///   digits each, e.g. `045`, `123`, `456`
///
/// `strftime` fields:
/// - `{%Y}`: four-digit year, e.g. `2014`
/// - `{%y}`: two-digit year, e.g. `14`
/// - `{%m}`: month, e.g. `10`
/// - `{%d}`: day of the month, e.g. `02`
/// - `{%H}`: hour, e.g. `15`
/// - `{%M}`: minute, e.g. `01`
/// - `{%S}`: second, e.g. `23`
/// - `{%T}`: `{%H}:{%M}:{%S}`, e.g. `15:01:23`
/// - `{%D}`: `{%m}/{%d}/{%y}`, e.g. `10/02/14`
/// - `{%z}`: numeric offset, e.g. `+0000`
/// - `{%:z}`: numeric offset with a colon, e.g. `+00:00`
///
/// Custom fields:
/// - `{#id}`: passed to `formatter`, with `id` holding the text after the `#`
///
/// Date and time fields are rendered in `timezone`. Note that
/// `{@RFC3339Z}` always writes a literal `Z`, even when `timezone` is not
/// `.utc`; keep `timezone` at `.utc` when using that field.
///
/// A literal `{` or `}` is written by doubling it: `{{` and `}}`. Unknown
/// field names and unbalanced braces are rejected when the pattern is parsed.
///
/// See `PatternToken` for the token each field parses to.
pub const Pattern = struct {
    /// The tokens the pattern was compiled to, including the literal text
    /// between the fields.
    tokens: []const PatternToken,

    /// Renders the custom `{#id}` fields of `tokens`.
    ///
    /// Must be non-null if `tokens` contains a `custom` token, otherwise
    /// `consiselog.init` fails with `error.UserFormatterNull`.
    formatter: ?UserFormatter = null,

    /// The default pattern, `[{@RFC3339Z}] [{@scope}]({@LEVEL}): {@msg}`,
    /// which renders records like this:
    /// ```
    /// [2014-10-02T15:01:23.045123456Z] [main](I): starting up
    /// ```
    pub const default: @This() = .{ .tokens = &.{
        .{ .literal = "[" },
        .rfc3339zulu,
        .{ .literal = "] [" },
        .scope,
        .{ .literal = "](" },
        .level_short,
        .{ .literal = "): " },
        .msg,
    } };

    /// Parses `pattern` at compile time and returns it as a token slice.
    ///
    /// A malformed pattern is a compile error. Use `RuntimePattern.parse` to
    /// parse a pattern that is only known at runtime.
    pub fn parse(comptime pattern: []const u8) Pattern {
        return .{ .tokens = comptime p.parsePatternComptime(pattern) catch unreachable };
    }

    /// Same as `parse`, but renders `{#id}` fields with `f`.
    pub fn parseWithFormatter(comptime pattern: []const u8, f: UserFormatter) Pattern {
        return .{ .tokens = comptime p.parsePatternComptime(pattern) catch unreachable, .formatter = f };
    }
};

/// A pattern parsed at runtime.
///
/// The tokens are allocated from the allocator given to `parse` and borrow
/// from the pattern string, which must therefore outlive the `RuntimePattern`.
/// Call `deinit` to release the tokens.
pub const RuntimePattern = struct {
    /// See `Pattern.tokens`.
    tokens: []const PatternToken,

    /// See `Pattern.formatter`.
    formatter: ?UserFormatter = null,

    /// Releases the token slice; the pattern string itself is not freed.
    pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
        gpa.free(self.tokens);
    }

    /// Returns a `Pattern` that shares `tokens` with `self`.
    ///
    /// The returned value does not own the tokens and must not outlive them;
    /// do not call `deinit` while it is still in use.
    pub fn toPattern(self: @This()) Pattern {
        return .{ .formatter = self.formatter, .tokens = self.tokens };
    }

    /// Parses `pattern`, allocating the tokens from `gpa`.
    ///
    /// Returns `error.UnknownField`, `error.UnmatchedOpenBrace`,
    /// `error.UnmatchedCloseBrace`, or an allocator error; see `ParseError`.
    /// On success the caller owns the returned `RuntimePattern`.
    pub fn parse(gpa: std.mem.Allocator, pattern: []const u8) p.ParseError!@This() {
        return .{ .tokens = try p.parsePattern(gpa, pattern) };
    }

    /// Same as `parse`, but renders `{#id}` fields with `f`.
    pub fn parseWithFormatter(gpa: std.mem.Allocator, pattern: []const u8, f: UserFormatter) p.ParseError!@This() {
        return .{ .tokens = try p.parsePattern(gpa, pattern), .formatter = f };
    }
};

/// The time zone that date and time fields are rendered in.
pub const TimeZoneOffset = union(enum) {
    /// UTC, rendered as `+00:00` or with a `Z` suffix.
    utc,

    /// The local time zone, given as an offset from UTC in seconds.
    ///
    /// Positive values are east of UTC, so UTC+08:00 is `28800`. The offset is
    /// fixed for the lifetime of the logger; daylight-saving transitions that
    /// happen later are not applied.
    local: isize,

    /// UTC.
    pub const default: @This() = .utc;

    /// Returns a `local` offset read from the operating system.
    ///
    /// The returned offset is the current base offset of the local time zone.
    /// Returns an error if the offset cannot be determined.
    pub fn initLocalTimeByHelper() error{unknow}!TimeZoneOffset {
        return .{ .local = h.getBaseUtcOffset() catch return error.unknow };
    }
};

/// The destination that records are written to.
pub const Output = union(enum) {
    /// A caller-supplied writer.
    ///
    /// The logger serializes its own writes, so at most one task calls into
    /// `writer` at a time; the caller must not write to it concurrently.
    writer: *std.Io.Writer,

    /// Standard error, buffered with `Stream.bufsize`.
    stderr: Stream,

    /// Standard output, buffered with `Stream.bufsize`.
    stdout: Stream,

    /// A file, created if it does not exist and buffered with `File.bufsize`.
    file: File,

    /// Options for writing to a standard stream.
    pub const Stream = struct {
        /// Size of the buffer the stream is written through.
        bufsize: usize = 4096,
    };

    /// Options for writing to a file.
    pub const File = struct {
        /// Size of the buffer the file is written through.
        bufsize: usize = 4096,

        /// Path of the file. A relative path is resolved against the current
        /// working directory.
        path: []const u8,
    };

    /// Standard output with the default buffer size.
    pub const default: @This() = .{ .stdout = .{} };
};

/// How write errors are reported.
///
/// The callback runs on the task that performed the write and cannot return an
/// error, so a failing destination cannot stop logging.
pub const ErrorHandler = struct {
    /// Called with the logger's `Io` and the writer that failed.
    ///
    /// The writer is the one that reported the error, so the callback can
    /// inspect its error state to find out what went wrong.
    func: *const fn (std.Io, *std.Io.Writer) void,

    /// Prints a fixed message to standard error.
    pub const default: ErrorHandler = .{ .func = &debugPrint };

    /// Ignores write errors silently.
    pub const discarding: ErrorHandler = .{ .func = noop };

    fn noop(_: std.Io, _: *std.Io.Writer) void {}

    fn debugPrint(_: std.Io, _: *std.Io.Writer) void {
        std.debug.print("{s}\n", .{"ConsiseLog Writer Error"});
    }
};
