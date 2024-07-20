const std = @import("std");

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
            .abi = .musleabihf,
            .cpu_arch = .arm,
            .cpu_model = .{
                .explicit = &std.Target.arm.cpu.arm1176jzf_s,
            },
            .os_tag = .linux,
        }
    },
    .{
        .name = "rpi02w",
        .details = .{
            .abi = .musleabihf,
            .cpu_arch = .aarch64,
            .cpu_model = .{
                .explicit = &std.Target.arm.cpu.cortex_a53,
            },
            .os_tag = .linux,
        },
    },
};

/// Resolves a target from the `targets` array based on the provided platform name.
/// If the platform is `null`, the host target is returned.
fn resolveTargetFromName(b: *std.Build, platform: ?[]const u8) !std.Build.ResolvedTarget {
    if (platform == null)
        return b.graph.host;
    
    for (targets) |target| {
        if (std.mem.eql(u8, target.name, platform.?))
            return b.resolveTargetQuery(target.details);
    }
    return error.UnknownPlatform; // Didn't find a matching target
}

pub fn build(b: *std.Build) void {
    // Resolve the internal build options based on the provided platform name
    const platform = b.option([]const u8, "platform", "Platform to build for (rpi0, rpi02w, blank for host)");
    const selected_target = resolveTargetFromName(b, platform) catch |err| {
        std.log.err("failed to resolve target ({})", .{err});
        std.process.exit(1);
    };
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
    b.installArtifact(exe);

    // Testing step
    const test_step = b.step("test", "Run unit tests");
    for (targets) |target| {
        const tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(target.details),
            .test_runner = b.path("test_runner.zig"),
        });
        const run_tests = b.addRunArtifact(tests);
        run_tests.skip_foreign_checks = true;
        test_step.dependOn(&run_tests.step);
    }

    // Documentation (generation) step
    const docs_step = b.step("docs", "Generate documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
