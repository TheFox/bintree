const std = @import("std");
const print = std.debug.print;
const allocPrint = std.fmt.allocPrint;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });
    const is_ci = b.option(bool, "ci", "Enable CI mode") orelse false;

    print("target arch: {s}\n", .{@tagName(target.result.cpu.arch)});
    print("target cpu: {s}\n", .{target.result.cpu.model.name});
    print("target os: {s}\n", .{@tagName(target.result.os.tag)});
    print("optimize: {s}\n", .{@tagName(optimize)});
    print("CI: {any}\n", .{is_ci});

    var target_name: []u8 = undefined;
    if (is_ci) {
        target_name = allocPrint(b.allocator, "bintree", .{}) catch @panic("failed to allocate target name");
    } else {
        target_name = allocPrint(
            b.allocator,
            "bintree-{s}-{s}",
            .{
                @tagName(target.result.cpu.arch),
                @tagName(target.result.os.tag),
            },
        ) catch @panic("failed to allocate target name");
    }
    print("target name: {s}\n", .{target_name});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = target_name,
        .root_module = exe_mod,
    });

    const options = b.addOptions();
    options.addOption(bool, "ci", is_ci);
    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
