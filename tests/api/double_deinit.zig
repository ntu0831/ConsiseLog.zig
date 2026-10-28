const consiselog = @import("consiselog");
const std = @import("std");

const io = std.testing.io;
const gpa = std.testing.allocator;

const Log = consiselog.Log(.test_api);

test "double deinit" {
    try consiselog.init(io, gpa, .default);
    consiselog.deinit(io);
    consiselog.deinit(io); // focus
}
