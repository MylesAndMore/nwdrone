//! Safety-critical operations to ensure safe operation of the drone.

const std = @import("std");

/// Forcefully and instantly shut down the drone.
pub fn shutdown() void {
    std.log.err("!!! EMERGENCY SHUTDOWN !!!", .{});
    // TODO: safety things when implemented (cut motors, etc.)
    std.process.exit(1);
}
