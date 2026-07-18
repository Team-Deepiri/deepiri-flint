const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wasm3 = b.addStaticLibrary(.{
        .name = "wasm3",
        .target = target,
        .optimize = optimize,
    });
    wasm3.linkLibC();
    wasm3.addIncludePath(b.path("vendor/wasm3"));
    wasm3.addCSourceFiles(.{
        .files = &.{
            "vendor/wasm3/m3_bind.c",
            "vendor/wasm3/m3_code.c",
            "vendor/wasm3/m3_compile.c",
            "vendor/wasm3/m3_core.c",
            "vendor/wasm3/m3_env.c",
            "vendor/wasm3/m3_exec.c",
            "vendor/wasm3/m3_function.c",
            "vendor/wasm3/m3_info.c",
            "vendor/wasm3/m3_module.c",
            "vendor/wasm3/m3_parse.c",
        },
        .flags = &.{
            "-std=c99",
            "-Dd_m3HasFloat=0",
            "-Dd_m3CascadedOpcodes=0",
            "-Dd_m3VerboseErrorMessages=1",
            "-fno-tree-vectorize",
            "-fno-sanitize=undefined",
            "-Wno-unused-parameter",
            "-Wno-unused-function",
            "-Wno-unused-variable",
            "-Wno-unused-but-set-variable",
        },
    });
    b.installArtifact(wasm3);

    const exe = b.addExecutable(.{
        .name = "flint",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibrary(wasm3);
    exe.addIncludePath(b.path("vendor/wasm3"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run flint");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkLibC();
    unit_tests.linkLibrary(wasm3);
    unit_tests.addIncludePath(b.path("vendor/wasm3"));
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Sample freestanding WASM skill (echo)
    const echo_wasm = b.addExecutable(.{
        .name = "echo_skill",
        .root_source_file = b.path("skills/echo_skill.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        }),
        .optimize = .ReleaseSmall,
    });
    echo_wasm.rdynamic = true;
    echo_wasm.entry = .disabled;
    // Install under zig-out/skills/
    const install_echo = b.addInstallBinFile(
        echo_wasm.getEmittedBin(),
        "../skills/echo_skill.wasm",
    );
    install_echo.step.dependOn(&echo_wasm.step);
    const skills_step = b.step("skills", "Build sample WASM skills");
    skills_step.dependOn(&install_echo.step);
    // Also build skills as part of default install
    b.getInstallStep().dependOn(&install_echo.step);

    const pass_wasm = b.addExecutable(.{
        .name = "passthrough_skill",
        .root_source_file = b.path("skills/passthrough_skill.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        }),
        .optimize = .ReleaseSmall,
    });
    pass_wasm.rdynamic = true;
    pass_wasm.entry = .disabled;
    const install_pass = b.addInstallBinFile(pass_wasm.getEmittedBin(), "../skills/passthrough_skill.wasm");
    install_pass.step.dependOn(&pass_wasm.step);
    skills_step.dependOn(&install_pass.step);
    b.getInstallStep().dependOn(&install_pass.step);

}

