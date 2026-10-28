const std = @import("std");

pub const RawOutputWriter = struct {
    pub const Stdio = struct {
        buf: []u8,
        fw: std.Io.File.Writer,

        pub fn init(gpa: std.mem.Allocator, io: std.Io, target: enum { stderr, stdout }, buf_size: usize) !@This() {
            const buf = try gpa.alloc(u8, buf_size);
            errdefer gpa.free(buf);

            return .{ .buf = buf, .fw = switch (target) {
                .stderr => std.Io.File.stderr().writer(io, buf),
                .stdout => std.Io.File.stdout().writer(io, buf),
            } };
        }

        pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
            gpa.free(self.buf);
        }

        pub fn writer(self: *@This()) *std.Io.Writer {
            return &self.fw.interface;
        }
    };

    pub const File = struct {
        file: std.Io.File,
        buf: []u8,
        fw: std.Io.File.Writer,

        pub fn init(gpa: std.mem.Allocator, io: std.Io, path: []const u8, buf_size: usize) !@This() {
            const f = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write }) catch |e| switch (e) {
                error.FileNotFound => try std.Io.Dir.cwd().createFile(io, path, .{}),
                else => return e,
            };
            errdefer f.close(io);

            const buffer = try gpa.alloc(u8, buf_size);
            errdefer gpa.free(buffer);

            return .{ .file = f, .buf = buffer, .fw = f.writer(io, buffer) };
        }

        pub fn deinit(self: @This(), gpa: std.mem.Allocator, io: std.Io) void {
            gpa.free(self.buf);
            self.file.close(io);
        }

        pub fn writer(self: *@This()) *std.Io.Writer {
            return &self.fw.interface;
        }
    };
};

pub const BridgeWriter = struct {
    //
};
