const std = @import("std");
const linux = std.os.linux;
const log = std.log;

// All (relavent) imported namespaces are marked public so as to appear in documentation.
// This is done in all files.

pub const quad = @import("control/quad.zig");

pub const pixy = @import("device/pixy.zig");

pub const pigpio = @import("lib/pigpio.zig");
pub const signal = @import("lib/signal.zig");

pub const drone = @import("drone.zig");

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
    try signal.handle(&sigs, drone.shutdown );

    // Initialize hardware and system components
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
    try quad.init();
    defer quad.deinit();
    // -- more hardware initialization can go here --

    // Once everything is initialized, we can enter the main loop
    // This is wrapped to catch any errors that make their way up here,
    // so that we can put the drone into a safe state before the program exits
    // The loop will also exit if any external functions call `drone.shutdown()`
    while (drone.safe) {
        loop() catch |err| {
            log.err("main loop threw error: {}", .{ err });
            break; // Break out of the loop to safely shut down
        };
    }
    // No shutdown routine is needed here, all deinits have already been deferred
    log.info("shutting down...", .{});
}

inline fn loop() !void {
    quad.update();
}
