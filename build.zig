const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const no_fail = b.option(bool, "no_fail", "Ignore build panic") orelse false;

    // TinyCC options
    const CONFIG_TCC_BCHECK = b.option(bool, "CONFIG_TCC_BCHECK", "compile with built-in memory and bounds checker (implies -g)") orelse true;
    const CONFIG_TCC_BACKTRACE = b.option(bool, "CONFIG_TCC_BACKTRACE", "link with backtrace (stack dump) support [show max N callers]") orelse true;
    const CONFIG_MEM_DEBUG = b.option(bool, "CONFIG_MEM_DEBUG", "compile with MEM_DEBUG flag defined for tcc") orelse false;

    switch (target.result.os.tag) {
        .windows, .macos, .linux, .dragonfly, .freebsd, .netbsd, .openbsd => {},
        else => if (no_fail) return else @panic("Unsupported OS"),
    }
    switch (target.result.cpu.arch) {
        .x86_64, .arm, .aarch64, .riscv64 => {},
        else => if (no_fail) return else @panic("Unsupported CPU architecture"),
    }

    const tcc_dep = b.dependency("tinycc", .{});

    const build_native_target: std.Build.ResolvedTarget = .{
        .query = try std.Target.Query.parse(.{}),
        .result = builtin.target,
    };

    const c2str_step = b.step("config-tcc", "Generate tccdefs_.h");
    {
        const c2str_exe = b.addExecutable(.{
            .name = "config-tcc",
            .root_module = b.createModule(.{
                .target = build_native_target,
                .optimize = .Debug,
            }),
        });

        c2str_exe.linkLibC();
        c2str_exe.addCSourceFile(.{
            .file = b.path("config/conftest.c"),
            .flags = &.{"-DC2STR"},
        });

        const run_exe = b.addRunArtifact(c2str_exe);

        run_exe.addArg(tcc_dep.path("include/tccdefs.h").getPath(b));
        run_exe.addArg(b.path("src/config/tccdefs_.h").getPath(b));

        c2str_step.dependOn(&run_exe.step);
    }

    const lib = b.addLibrary(.{
        .name = "libtinycc",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.linkLibC();
    lib.addIncludePath(b.path("src/config"));
    lib.addIncludePath(tcc_dep.path("."));
    lib.addIncludePath(tcc_dep.path("include"));

    lib.step.dependOn(c2str_step);

    const cpu_arch = target.result.cpu.arch;
    const os_tag = target.result.os.tag;

    var FLAGS = std.ArrayList([]const u8).init(b.allocator);
    var C_SOURCES = std.ArrayList([]const u8).init(b.allocator);

    try FLAGS.append("-Wall");
    try FLAGS.append("-fno-strict-aliasing");
    try FLAGS.append("-fno-sanitize=undefined");
    try FLAGS.append("-O3");

    try FLAGS.append("-DCONFIG_TCC_PREDEFS");
    try FLAGS.append("-DONE_SOURCE=0");
    try FLAGS.append("-DTCC_LIBTCC1=\"\\0\"");

    if (!CONFIG_TCC_BCHECK)
        try FLAGS.append("-DCONFIG_TCC_BCHECK=0");
    if (!CONFIG_TCC_BACKTRACE)
        try FLAGS.append("-DCONFIG_TCC_BACKTRACE=0");
    if (CONFIG_MEM_DEBUG)
        try FLAGS.append("-DMEM_DEBUG=2");

    for (SOURCES) |file|
        try C_SOURCES.append(file);

    switch (cpu_arch) {
        .x86_64 => {
            for (X86_64_SOURCES) |file|
                try C_SOURCES.append(file);
        },
        .arm => {
            for (ARM_SOURCES) |file|
                try C_SOURCES.append(file);
        },
        .aarch64 => {
            for (AARCH64_SOURCES) |file|
                try C_SOURCES.append(file);
        },
        .riscv64 => {
            for (RISCV64_SOURCES) |file|
                try C_SOURCES.append(file);
        },
        else => unreachable,
    }

    switch (os_tag) {
        .windows => {
            for (WINDOWS_SOURCES) |file|
                try C_SOURCES.append(file);
        },
        .macos => {
            for (MACOS_SOURCES) |file|
                try C_SOURCES.append(file);
        },
        .linux => {},
        .dragonfly, .freebsd, .netbsd, .openbsd => {},
        else => unreachable,
    }

    switch (cpu_arch) {
        .x86_64 => try FLAGS.append("-DTCC_TARGET_X86_64"),
        .arm => try FLAGS.append("-DTCC_TARGET_ARM"),
        .aarch64 => try FLAGS.append("-DTCC_TARGET_ARM64"),
        .riscv64 => try FLAGS.append("-TCC_TARGET_RISCV64"),
        else => unreachable,
    }

    switch (os_tag) {
        .windows => {
            try FLAGS.append("-DTCC_TARGET_PE");
            try FLAGS.append("-DCONFIG_WIN32");
            try FLAGS.append("-D_STDDEF_H");
        },
        .macos => {
            try FLAGS.append("-DTCC_TARGET_MACHO");
            try FLAGS.append("-DCONFIG_CODESIGN");
            try FLAGS.append("-DCONFIG_NEW_MACHO");
        },
        .linux => {
            if (target.result.abi == .musl)
                try FLAGS.append("-DCONFIG_TCC_MUSL");
        },
        .dragonfly => try FLAGS.append("-DTARGETOS_DragonFly"),
        .freebsd => try FLAGS.append("-DTARGETOS_FreeBSD"),
        .netbsd => try FLAGS.append("-DTARGETOS_NetBSD"),
        .openbsd => try FLAGS.append("-DTARGETOS_OpenBSD"),
        else => unreachable,
    }

    lib.addCSourceFiles(.{
        .root = tcc_dep.path(""),
        .files = C_SOURCES.items,
        .flags = FLAGS.items,
    });

    const module = b.addModule("tinycc", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(lib);

    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.linkLibrary(lib);

    b.installArtifact(unit_tests);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

const SOURCES = [_][]const u8{
    "libtcc.c",
    "tccpp.c",
    "tccrun.c",
    "tccgen.c",
    "tccdbg.c",
    "tccelf.c",
    "tccasm.c",
};

// OS sources
const MACOS_SOURCES = [_][]const u8{
    "tccmacho.c",
};
const WINDOWS_SOURCES = [_][]const u8{
    "tccpe.c",
};

// Architecture sources
const X86_64_SOURCES = [_][]const u8{
    "x86_64-gen.c",
    "x86_64-link.c",
    "i386-asm.c",
};
const AARCH64_SOURCES = [_][]const u8{
    "arm64-gen.c",
    "arm64-link.c",
    "arm64-asm.c",
};
const ARM_SOURCES = [_][]const u8{
    "arm-gen.c",
    "arm-link.c",
    "arm-asm.c",
};
const RISCV64_SOURCES = [_][]const u8{
    "riscv64-gen.c",
    "riscv64-link.c",
    "riscv64-asm.c",
};
