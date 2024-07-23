const std = @import("std");
const Build = std.Build;
const Compile = Build.Step.Compile;

const BuildError = error {
    UnknownPlatform,
};

// A single target contains its name and its details, structured as a `Query` to be resolved by the build system.
const Target = struct {
    name: []const u8,
    details: std.Target.Query,
};

// An array of possible targets to build for.
const targets = [_]Target {
    .{
        .name = "rpi0",
        .details = .{
            .abi = .gnueabihf,
            .cpu_arch = .arm,
            .cpu_model = .{
                .explicit = &std.Target.arm.cpu.arm1176jzf_s,
            },
            .os_tag = .linux,
        },
    },
    .{
        .name = "rpi02",
        .details = .{
            .abi = .gnueabihf,
            .cpu_arch = .aarch64,
            .cpu_model = .{
                .explicit = &std.Target.arm.cpu.cortex_a53,
            },
            .os_tag = .linux,
        },
    },
};

/// Resolve a target from the `targets` array based on the provided platform name.
/// If the platform is `null`, the host target is returned.
fn resolveTargetFromName(b: *Build, platform: ?[]const u8) !Build.ResolvedTarget {
    if (platform == null)
        return b.graph.host;
    
    for (targets) |target| {
        if (std.mem.eql(u8, target.name, platform.?))
            return b.resolveTargetQuery(target.details);
    }
    return error.UnknownPlatform; // Didn't find a matching target
}
/// Add include paths to a compile step.
fn addIncludePaths(b: *Build, compile: *Compile, comptime paths: []const []const u8) void {
    for (paths) |path|
        compile.addIncludePath(b.path(path));
}

/// Add library paths to a compile step.
fn addLibraryPaths(alloc: std.mem.Allocator, b: *Build, compile: *Compile, comptime paths: []const []const u8) !void {
    const triple = try compile.rootModuleTarget().linuxTriple(alloc);
    defer alloc.free(triple);
    for (paths) |path| {
        const lib_path = try std.fmt.allocPrint(alloc, "{s}/{s}/", .{ path, triple });
        defer alloc.free(lib_path);
        compile.addLibraryPath(b.path(lib_path));
    }
}

/// Forcefully link system libraries to the root module of a compile step.
fn forceLinkSystemLibraries(compile: *Compile, comptime libs: []const []const u8) void {
    for (libs) |lib|
        compile.root_module.linkSystemLibrary(lib, .{ .needed = true });
}

pub fn build(b: *Build) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Resolve the internal build options based on the provided platform name
    const platform = b.option([]const u8, "platform", "Platform to build for (rpi0, rpi02, blank for host)");
    const selected_target = try resolveTargetFromName(b, platform);
    const strip = b.option(bool, "strip", "Strip the executable after building") orelse false;

    // Executable target
    const exe = b.addExecutable(.{
        .name = "nwdrone",
        .root_source_file = b.path("src/main.zig"),
        .target = selected_target,
        .optimize = b.standardOptimizeOption(.{
            // Default release mode should be ReleaseSafe as it's not that much slower than ReleaseFast
            .preferred_optimize_mode = .ReleaseSafe
        }),
        .link_libc = true,
        .strip = strip,
    });
    // Add C include paths and libraries
    const includes = [_][]const u8{ "lib/pixyusb/include" };
    addIncludePaths(b, exe, &includes);
    const lib_paths = [_][]const u8{ "lib/pixyusb" };
    try addLibraryPaths(alloc, b, exe, &lib_paths);
    const libs = [_][]const u8{ "pixyusb", "boost_chrono", "boost_system", "boost_thread", "usb-1.0" };
    forceLinkSystemLibraries(exe, &libs);

    b.installArtifact(exe);

    // Testing step
    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = b.graph.host,
        .test_runner = b.path("test_runner.zig"),
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    // Documentation (generation) step
    const docs_step = b.step("docs", "Generate documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
