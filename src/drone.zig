//! Global drone control module.

const std = @import("std");
const log = std.log.scoped(.drone);

pub const command = @import("lib/command.zig");

pub var safe = true; // (read-only)
pub var shutdown_host = false; // Whether to also shutdown the host system on drone shutdown (read-only)

/// Safely shut down the drone.
pub fn shutdown() void {
    // Don't print anything here, it could cause a deadlock
    // as shutdown() can be called from multiple threads
    safe = false;
}

/// Safely shut down the drone and the host system.
pub fn shutdownHost() void {
    shutdown_host = true;
    shutdown();
}

/// Instantly kill (shut down) the host system if it has been requested.
/// WARNING: This is a dangerous operation and should be used with caution!
pub fn killHost() void {
    if (!shutdown_host)
        return;
    log.info("!!! shutting down host !!!", .{});
    if (!command.run(std.heap.page_allocator, "shutdown", &[_][]const u8{ "-h", "now" }))
        log.warn("failed to issue shutdown command", .{});
}
