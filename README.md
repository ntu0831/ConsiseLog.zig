# ConsiseLog.zig

A customizable logging library for Zig with a zero-allocation hot path.

## Features

- **0 dependencies**: Only the Zig standard library
- **0 allocation**: Memory is preallocated only during init in async or concurrent mode
- **libc-free**: Only the `.initLocalTimeByHelper` function depends on libc
  > Use .initLocalTimeByHelper to get the local time zone. Alternatively, you can use a third-party library to configure the local time zone.
- **Large records** A record can span multiple pool blocks in async/concurrent mode 
- **Drop-in `std.log` support**: `ConsiseLog.helper.logfn` replace `std.Options.logFn`, `ConsiseLog.Log` replace `std.log.scoped`
- **Custom patterns**: Supports multiple format specifiers for output
- **Custom formatters**: Through `{#id}` specifiers, users can implement formatting
- **Custom writers**: Any `std.Io.Writer` can be used as the destination
- **Three running modes**: `sync`, `async`, and `concurrent`

## Installation

Requires Zig **0.17.0** 

```sh
zig fetch --save git+https://github.com/ntu0831/ConsiseLog.zig.git#v0.1.0
```

Then add the module in `build.zig`:

```zig
const consiselog = b.dependency("consiselog", .{}).module("consiselog");
exe.root_module.addImport("consiselog", consiselog);
```

## Usage

### Minimal example

```zig
const std = @import("std");
const consiselog = @import("consiselog");

const log = consiselog.Log(.app);

pub fn main(init: std.process.Init) !void {
    try consiselog.init(init.io, init.gpa, .default);
    defer consiselog.deinit(init.io);

    log.info("hello {s}", .{"world"});
}
```

```text
[2026-10-28T16:52:42.429564000Z] [app](I): hello world
```

- **`deinit` must be called.** It stops the writer, drains any queued records, flushes the output, and frees the preallocated memory.


### `std.log`  example 

```zig
const std = @import("std");
const consiselog = @import("consiselog");

pub const std_options: std.Options = .{
    .logFn = consiselog.helper.logFn,
};

pub fn main(init: std.process.Init) !void {
    try consiselog.init(init.io, init.gpa, .{
        .pattern = .parse("{@RFC3339Z} [{@scope}] [{@level}] {@msg}"),
    });
    defer consiselog.deinit(init.io);

    std.log.info("ready", .{});
    std.log.scoped(.database).warn("slow query: {d} ms", .{120});
}
```

```text
2026-10-28T16:52:42.429564000Z [default] [info] ready
2026-10-28T16:52:42.429564000Z [database] [warning] slow query: 120 ms
```

### Configuration

```zig
pub const Config = struct {
    level: Level = std.log.default_level,
    mode: RunningMode = .default,
    output: Output = .default,
    errhandler: ErrorHandler = .default,
    timezone: TimeZoneOffset = .default,
    pattern: Pattern = .default,
};
```

| Field | Type | Default | Purpose |
| --- | --- | --- | --- |
| `level` | `std.log.Level` | `std.log.default_level` | Minimum level that is written. |
| `mode` | `RunningMode` | `.concurrent` | Sync, async, or concurrent. |
| `output` | `Output` | `.stdout` | Destination and buffer size. |
| `errhandler` | `ErrorHandler` | print to stderr | Called when a write fails. |
| `timezone` | `TimeZoneOffset` | `.utc` | Time zone for date/time fields. |
| `pattern` | `Pattern` | `[{@RFC3339Z}] [{@scope}]({@LEVEL}): {@msg}` | Record layout and custom formatter. |

- The output can be `.stdout`, `.stderr`, `.file`, or a custom `.writer`. 
- Local time zones are fixed per logger. Use `.initLocalTimeByHelper()` to read the OS offset, or pass `.local = seconds`.

#### Pattern

A pattern is plain text plus fields. Literal braces are written as `{{` and `}}`; unknown fields, an unclosed `{`, or a stray `}` are parse errors.

- `{@<field>}`: built-in style
- `{%<field>}`: strftime style
- `{#<field>}`: custom id

| Field | Output |
| --- | --- |
| `{@msg}` | The log message. |
| `{@scope}` | The logging namespace. |
| `{@level}` / `{@LEVEL}` | Full lowercase level name / single letter. |
| `{@RFC3339}` / `{@RFC3339Z}` | RFC 3339 timestamp with numeric offset / with `Z`. |
| `{@ms}` / `{@us}` / `{@ns}` | Millisecond / microsecond / nanosecond part, three digits each. |
| `{%Y}` `{%y}` `{%m}` `{%d}` `{%H}` `{%M}` `{%S}` | Year, month, day, hour, minute, second. |
| `{%T}` / `{%D}` | `{%H}:{%M}:{%S}` / `{%m}/{%d}/{%y}`. |
| `{%z}` / `{%:z}` | Numeric offset `+0000` / `+00:00`. |
| `{#id}` | Custom field rendered by the formatter. |

#### RunningMode

| Mode | Behavior |
| --- | --- |
| `.sync` | Format and write on the calling thread; concurrent calls are serialized by a mutex. |
| `.async` | Format on the calling thread; write on the `Io.async` event loop |
| `.concurrent` | Format on the calling thread; write on the `Io.concurrent` event loop |

- Pool exhausted: `.block`, `.drop`, or `.truncate`.
- Record quota exhausted: `.truncate` (write the prefix that fits) or `.drop`.
- `sync` has no per-record size limit. In async / concurrent mode, the limit is `max_buffers_per_record × buffer.size`; the default is about 64 KiB.

#### Compile-time options

Declare `pub const consiselog_options` in the root source file:

```zig
pub const consiselog_options: consiselog.Options = .{
    // Maximum blocks a single record may occupy.
    .max_buffers_per_record = 16,

    // Maximum blocks the writer takes in one batch.
    .max_buffers_per_batch = 16,
};
```

These values size fixed arrays on the logging path, so they must be known at compile time. `max_buffers_per_record` (together with `buffer.size`) determines the maximum record size; each async log call keeps `max_buffers_per_record + 1` slice entries on the stack.

## Examples

```sh
zig build examples
```

| Example | Description |
| --- | --- |
| [minimal.zig](examples/minimal.zig) | Minimal init, log, deinit. |
| [stdlog.zig](examples/stdlog.zig) |  `std.log` alternative. |
| [filelog.zig](examples/filelog.zig) | Write to a file. |
| [writerlog.zig](examples/writerlog.zig) | Custom writers. |
| [pattern.zig](examples/pattern.zig) | Custom patterns and a `{#id}` formatter. |
| [errorhandling.zig](examples/errorhandling.zig) | Custom error handler and failing writer. |

## Benchmark

> Work in progress 

## Docs

### Local

```sh
zig build docs
```

### Online

See the [API Documentation](https://ntu0831.github.io/ConsiseLog.zig).
