const std = @import("std");
const linux = std.os.linux;
const log = std.log;

// All (relavent) imported namespaces are marked public so as to appear in documentation.
// This is done in all files.

const pwm = @import("hw/pwm.zig");

pub const pixy = @import("device/pixy.zig");

pub const pigpio = @import("lib/pigpio.zig");
pub const signal = @import("lib/signal.zig");

pub fn main() !void {
    // Create our allocator to be used for all heap allocations
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak)
            log.warn("memory leak(s) detected", .{});
    }
    const alloc = gpa.allocator();
    _ = alloc; // FIXME: temporary, remove when allocator is used

    // Connect our shutdown function to the SIGINT and SIGTERM signals,
    // so that the drone can be safely shut down when the process must be terminated
    const sigs = [_]u6{ linux.SIG.INT, linux.SIG.TERM };
    try signal.handle(&sigs, shutdown );

    // Initialize hardware and devices
    pigpio.init() catch |err| {
        log.err("failed to connect to pigpiod, are you sure it's running?", .{});
        return err;
    };
    defer pigpio.deinit();
    pixy.init() catch |err| {
        log.err("failed to connect to Pixy camera, are you sure it's plugged in/does this user have USB privileges?", .{});
        return err;
    };
    defer pixy.deinit();
    // -- more hardware initialization can go here --

    // Once everything is initialized, we can enter the main loop
    // This is wrapped in to catch any errors that make their way up here,
    // so that we can put the drone into a safe state before the program exits
    while (true) {
        loop() catch |err| {
            log.err("performing emergency shutdown due to {}", .{err});
            shutdown();
            return err; // Re-throw the error to exit
        };
    }
}

inline fn loop() !void {
    // zooooom
}

fn shutdown() void {
    // TODO: safety things when implemented (cut motors, etc.)
}

test "root" {
    std.testing.refAllDeclsRecursive(@This()); // Include all tests in files used by this one
}
