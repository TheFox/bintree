const config = @import("build.zig.zon");
const std = @import("std");
const print = std.debug.print;
const aprint = std.fmt.allocPrint;

pub fn build(b: *std.Build) !void {
    const version = try std.SemanticVersion.parse(config.version);
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .small,
    });
    const is_ci = b.option(bool, "ci", "Enable CI mode") orelse false;

    const target_name = try if (is_ci)
        aprint(b.allocator, "bintree", .{})
    else
        aprint(b.allocator, "bintree-{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag) });

    print("version: {s}\n", .{config.version});
    print("target arch: {s}\n", .{@tagName(target.result.cpu.arch)});
    print("target cpu: {s}\n", .{target.result.cpu.model.name});
    print("target os: {s}\n", .{@tagName(target.result.os.tag)});
    print("target name: {s}\n", .{target_name});
    print("optimize: {s}\n", .{@tagName(optimize)});
    print("is_ci: {any}\n", .{is_ci});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "VERSION", config.version);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .strip = optimize != .debug,
        .optimize = optimize,
    });
    exe_mod.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = target_name,
        .version = version,
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
