//! Global drone control module.

const std = @import("std");

pub var safe = true; // (read-only)

/// Safely shut down the drone.
pub fn shutdown() void {
    std.log.info("shutdown flag set", .{});
    safe = false;
}
