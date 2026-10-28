const std = @import("std");

pub const Metrics = struct {
    drop: std.atomic.Value(usize) = .init(0),
    block: std.atomic.Value(usize) = .init(0),
    format: std.atomic.Value(usize) = .init(0),

    pub fn dropEvent(self: *@This()) void {
        _ = self.drop.fetchAdd(1, .monotonic);
    }

    pub fn blockEvent(self: *@This()) void {
        _ = self.block.fetchAdd(1, .monotonic);
    }

    pub fn formatErrorEvent(self: *@This()) void {
        _ = self.format.fetchAdd(1, .monotonic);
    }

    pub fn dropEventWithError(self: *@This()) !void {
        self.drop.fetchAdd(1, .monotonic);
        return error.drop;
    }
};
