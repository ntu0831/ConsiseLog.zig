const consiselog = @import("consiselog");
const std = @import("std");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectError = std.testing.expectError;

const Log = consiselog.Log(.test_api);

test "double init before deinit" {
    try consiselog.init(io, gpa, .default);
    defer consiselog.deinit(io);
    try expectError(error.Initialized, consiselog.init(io, gpa, .default));
}
