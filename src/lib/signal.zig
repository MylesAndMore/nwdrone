//! Library for easily interfacing with Linux signals through Zig.

const std = @import("std");
const linux = std.os.linux;

/// Connect a signal handler to the given signals.
/// Signals can be found in `std.os.linux.SIG`.
pub fn handle(sigs: []const u6, comptime handler: *const fn () void) !void {
    const sighandler = struct {
        fn sighandler(sig: c_int) callconv(.C) void {
            handler();
            _ = sig;
        }
    }.sighandler;
    const act = linux.Sigaction {
        .handler = .{ .handler = sighandler },
        .mask = linux.empty_sigset,
        .flags = 0,
    };

    for (sigs) |sig| {
        if (linux.sigaction(sig, &act, null) != 0)
            return error.Failure;
        std.log.info("registered signal handler for {}", .{ sig });
    }
}
