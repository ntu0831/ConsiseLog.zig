const std = @import("std");

const consiselog = "consiselog";

pub fn build(b: *std.Build) !void {
    var ctx: Context = .{
        .optimize = b.standardOptimizeOption(.{}),
        .target = b.standardTargetOptions(.{}),
    };

    // zig build run
    // zig build examples
    // zig build test
    // zig build test-unit
    // zig build test-examples
    // zig build test-integration

    try addModule(b, &ctx);
    try addRunner(b, &ctx);
    try addExamples(b, &ctx);
    try addIntegrationTest(b, &ctx);
    try addCommand(b, &ctx);
}

fn addCommand(b: *std.Build, ctx: *Context) !void {
    const build_docs = b.step("docs", "Build the docs");
    build_docs.dependOn(&b.addInstallDirectory(.{
        .source_dir = ctx.mod_test.?.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);

    const run_example = b.step("run", "Run examples");
    const run_runner = b.addRunArtifact(ctx.runner.?);
    run_runner.addPassthruArgs();
    run_example.dependOn(&run_runner.step);

    const build_examples = b.step("examples", "Build examples");
    for (ctx.examples_exe.items) |exe| {
        build_examples.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }

    const test_all = b.step("test", "Run all tests");

    const test_unit = b.step("test-unit", "Run unit tests");
    test_unit.dependOn(&b.addRunArtifact(ctx.mod_test.?).step);

    const test_examples = b.step("test-examples", "Run example tests");
    for (ctx.examples_test.items) |t| {
        test_examples.dependOn(&b.addRunArtifact(t).step);
    }

    const test_integration = b.step("test-integration", "Run integration tests");
    for (ctx.integration_test.items) |t| {
        test_integration.dependOn(&b.addRunArtifact(t).step);
    }

    run_example.dependOn(build_examples);
    test_all.dependOn(test_unit);
    test_all.dependOn(test_examples);
    test_all.dependOn(test_integration);
}

fn addModule(b: *std.Build, ctx: *Context) !void {
    const mod = b.addModule(consiselog, .{
        .root_source_file = b.path("src/root.zig"),
        .target = ctx.target,
        .optimize = ctx.optimize,
    });
    ctx.mod_test = b.addTest(.{ .root_module = mod });
    ctx.mod = mod;
}

fn addExamples(b: *std.Build, ctx: *Context) !void {
    const io = b.graph.io;
    const gpa = b.allocator;

    const examples_dir = try b.root.openDir(io, "examples", .{
        .iterate = true,
    });
    defer examples_dir.close(io);

    inline for (static.examples) |example| {
        const mod = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .imports = &.{.{ .name = consiselog, .module = ctx.mod.? }},
        });
        try ctx.examples_test.append(gpa, b.addTest(.{ .root_module = mod }));
        try ctx.examples_exe.append(gpa, b.addExecutable(.{
            .name = example.name,
            .root_module = mod,
        }));
    }
}

fn addRunner(b: *std.Build, ctx: *Context) !void {
    const config = b.addOptions();
    config.addOptionPathUntracked("install_bin", .{
        .relative = .{ .base = .install_bin },
    });
    config.addOption([]const []const u8, "examples", static.examples_name);

    ctx.runner = b.addExecutable(.{
        .name = "run",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/runner/runner.zig"),
            .target = ctx.target,
            .optimize = ctx.optimize,
            .imports = &.{
                .{ .name = consiselog, .module = ctx.mod.? },
                .{ .name = "config", .module = config.createModule() },
            },
        }),
    });
}

fn addIntegrationTest(b: *std.Build, ctx: *Context) !void {
    inline for (static.tests) |t| {
        const test_bin = b.addTest(.{
            .name = t.name,
            .test_runner = if (t.test_runner) |path| .{
                .path = b.path(path),
                .mode = .server,
            } else null,
            .root_module = b.createModule(.{
                .root_source_file = b.path(t.path),
                .target = ctx.target,
                .optimize = ctx.optimize,
                .imports = &.{.{ .name = consiselog, .module = ctx.mod.? }},
            }),
        });
        try ctx.integration_test.append(b.allocator, test_bin);
    }
}

const Context = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    mod: ?*std.Build.Module = null,
    mod_test: ?*std.Build.Step.Compile = null,

    runner: ?*std.Build.Step.Compile = null,

    examples_exe: std.ArrayList(*std.Build.Step.Compile) = .empty,
    examples_test: std.ArrayList(*std.Build.Step.Compile) = .empty,

    integration_test: std.ArrayList(*std.Build.Step.Compile) = .empty,
};

const static = struct {
    // const examples: []const Example = &.{
    // const examples: []const struct { name: []const u8, path: []const u8 } = &.{
    const examples = &.{
        .{ .name = "minimal", .path = "examples/minimal.zig" },
        .{ .name = "stdlog", .path = "examples/stdlog.zig" },
        .{ .name = "filelog", .path = "examples/filelog.zig" },
        .{ .name = "writerlog", .path = "examples/writerlog.zig" },
        .{ .name = "errorhandling", .path = "examples/errorhandling.zig" },
        .{ .name = "pattern", .path = "examples/pattern.zig" },
    };
    const examples_name = &.{ "minimal", "stdlog", "filelog", "writerlog", "errorhandling" };
    const tests = [_]struct { name: []const u8, path: []const u8, test_runner: ?[]const u8 = null }{
        .{ .name = "init_after_deinit", .path = "tests/api/init_after_deinit.zig" },
        .{ .name = "deinit_before_init", .path = "tests/api/deinit_before_init.zig" },
        .{ .name = "double_deinit", .path = "tests/api/double_deinit.zig" },
        .{ .name = "double_init_after_deinit", .path = "tests/api/double_init_after_deinit.zig" },
        .{ .name = "double_init_before_deinit", .path = "tests/api/double_init_before_deinit.zig" },
        .{ .name = "log_after_deinit", .path = "tests/api/log_after_deinit.zig" },
        .{ .name = "log_before_init", .path = "tests/api/log_before_init.zig" },

        // single producer
        .{ .name = "onelog_with_self", .path = "tests/sp/onelog_with_self.zig" },
        .{ .name = "onelog_with_async", .path = "tests/sp/onelog_with_async.zig" },
        .{ .name = "onelog_with_concurrent", .path = "tests/sp/onelog_with_concurrent.zig" },
        .{ .name = "looplog_with_self", .path = "tests/sp/looplog_with_self.zig" },
        .{ .name = "looplog_with_async", .path = "tests/sp/looplog_with_async.zig" },
        .{ .name = "looplog_with_concurrent", .path = "tests/sp/looplog_with_concurrent.zig" },

        // multi producer
        .{ .name = "onelog_with_async", .path = "tests/mp/onelog_with_async.zig" },
        .{ .name = "onelog_with_concurrent", .path = "tests/mp/onelog_with_concurrent.zig" },
        .{ .name = "looplog_with_async", .path = "tests/mp/looplog_with_async.zig" },
        .{ .name = "looplog_with_concurrent", .path = "tests/mp/looplog_with_concurrent.zig" },

        .{ .name = "large_msg", .path = "tests/large_msg.zig" },
        .{ .name = "pattern", .path = "tests/pattern.zig" },

        .{ .name = "pool_buf_exhaustion", .path = "tests/pool_buf_exhaustion.zig" },
        .{
            .name = "record_buf_exhaustion",
            .path = "tests/record_buf_exhaustion/record_buf_exhaustion.zig",
            .test_runner = "tests/record_buf_exhaustion/test_runner_0_17.zig",
        },
    };
};
