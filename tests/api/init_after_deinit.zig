const consiselog = @import("consiselog");
const std = @import("std");

const io = std.testing.io;
const gpa = std.testing.allocator;

const Log = consiselog.Log(.test_api);

test "init after deinit" {
    try consiselog.init(io, gpa, .default);
    consiselog.deinit(io);
    try consiselog.init(io, gpa, .default); // focus
    consiselog.deinit(io);
}
