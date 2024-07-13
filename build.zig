const std = @import("std");

const BuildError = error{
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
    const target = resolveTargetFromName(b, platform) catch |err| {
        std.debug.print("failed to resolve target ({})\n", .{err});
        std.process.exit(1);
    };

    // Create the executable target and install it
    const exe = b.addExecutable(.{
        .name = "nwdrone",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = b.standardOptimizeOption(.{
            // Default release mode should be ReleaseSafe as it's not that much slower than ReleaseFast
            .preferred_optimize_mode = .ReleaseSafe
        })
    });

    b.installArtifact(exe);
}
