const std = @import("std");

const logger = @import("logger.zig");

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    logger.log(level, scope, format, args);
}

pub const getBaseUtcOffset = @import("localtime.zig").getBaseUtcOffset;

// ResourceHost ResourceContainer ResourceOnwer
pub const ResourceManager = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    resources: std.ArrayList(Resource) = .initBuffer(&.{}),

    const OutputWriter = @import("writer.zig").OutputWriter;

    pub const Resource = union(enum) {
        rotating: *anyopaque,
        stdio: *OutputWriter.Stdio,
        file: *OutputWriter.File,
    };

    pub fn deinit(self: *@This()) void {
        const gpa = self.gpa;
        const io = self.io;
        for (self.resources.items) |res| {
            switch (res) {
                .rotating => |ptr| {
                    ptr.deinit();
                },
                .file => |ptr| ptr.deinit(gpa, io),
            }
        }
    }

    pub fn initRoataingFileLog(self: *@This()) *std.Io.Writer {
        // self.resources
        // self.resources
        // self.resources.append(self.gpa, .{ .rotating =  })
        OutputWriter.File.init(self.gpa, self.io, "lkjaf", 4096);
    }
};
