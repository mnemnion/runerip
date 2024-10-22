// Build script for runerip
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const runerip_module = b.addModule("runerip", .{
        .root_source_file = b.path("src/runerip.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &[0][]const u8{};

    const module_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/runerip.zig"),
        .target = target,
        .optimize = optimize,
        .filters = test_filters,
    });

    const run_module_unit_tests = b.addRunArtifact(module_unit_tests);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&run_module_unit_tests.step);

    const runerip_count_exe = b.addExecutable(.{
        .name = "runerip_count",
        .root_source_file = b.path("demo/runerip_count.zig"),
        .target = target,
        .optimize = optimize,
    });

    runerip_count_exe.root_module.addImport("runerip", runerip_module);

    b.installArtifact(runerip_count_exe);

    const standard_count_exe = b.addExecutable(.{
        .name = "standard_count",
        .root_source_file = b.path("demo/standard_count.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(standard_count_exe);

    const runerip_sum_exe = b.addExecutable(.{
        .name = "runerip_sum",
        .root_source_file = b.path("demo/runerip_sum.zig"),
        .target = target,
        .optimize = optimize,
    });

    runerip_sum_exe.root_module.addImport("runerip", runerip_module);

    b.installArtifact(runerip_sum_exe);

    const standard_sum_exe = b.addExecutable(.{
        .name = "standard_sum",
        .root_source_file = b.path("demo/standard_sum.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(standard_sum_exe);

    const runerip_validate_exe = b.addExecutable(.{
        .name = "runerip_validate",
        .root_source_file = b.path("demo/runerip_validate.zig"),
        .target = target,
        .optimize = optimize,
    });

    runerip_validate_exe.root_module.addImport("runerip", runerip_module);

    b.installArtifact(runerip_validate_exe);

    const runerip_transcode_exe = b.addExecutable(.{
        .name = "runerip_transcode",
        .root_source_file = b.path("demo/runerip_transcode.zig"),
        .target = target,
        .optimize = optimize,
    });

    runerip_transcode_exe.root_module.addImport("runerip", runerip_module);

    b.installArtifact(runerip_transcode_exe);

    const standard_validate_exe = b.addExecutable(.{
        .name = "standard_validate",
        .root_source_file = b.path("demo/standard_validate.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(standard_validate_exe);

    const standard_transcode_exe = b.addExecutable(.{
        .name = "standard_transcode",
        .root_source_file = b.path("demo/standard_transcode.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(standard_transcode_exe);

    const addOutputDirectoryArg = comptime if (@import("builtin").zig_version.order(.{ .major = 0, .minor = 13, .patch = 0 }) == .lt)
        std.Build.Step.Run.addOutputFileArg
    else
        std.Build.Step.Run.addOutputDirectoryArg;

    const run_kcov = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--exclude-line=unreachable,expect(false)",
    });
    run_kcov.addPrefixedDirectoryArg("--include-pattern=", b.path("."));
    const coverage_output = addOutputDirectoryArg(run_kcov, ".");
    run_kcov.addArtifactArg(module_unit_tests);

    run_kcov.enableTestRunnerMode();

    const install_coverage = b.addInstallDirectory(.{
        .source_dir = coverage_output,
        .install_dir = .{ .custom = "coverage" },
        .install_subdir = "",
    });

    const coverage_step = b.step("coverage", "Generate coverage (kcov must be installed)");
    coverage_step.dependOn(&install_coverage.step);
}
