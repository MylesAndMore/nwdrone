//! Global drone control module.

const std = @import("std");

pub var safe = true; // (read-only)

/// Safely shut down the drone.
pub fn shutdown() void {
    // Don't print anything here, it could cause a deadlock
    // as shutdown() can be called from multiple threads
    safe = false;
}
