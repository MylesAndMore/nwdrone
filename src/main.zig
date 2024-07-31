const std = @import("std");
const linux = std.os.linux;
const log = std.log;

// All (relavent) imported namespaces are marked public so as to appear in documentation.
// This is done in all files.

pub const quad = @import("control/quad.zig");

pub const pixy = @import("device/pixy.zig");

pub const pigpio = @cImport({ @cInclude("pigpio.h"); });
pub const err = @import("lib/err.zig");
pub const signal = @import("lib/signal.zig");

pub const drone = @import("drone.zig");

pub fn main() !void {
    // Connect our shutdown function to the SIGINT and SIGTERM signals,
    // so that the drone can be safely shut down when the process must be terminated
    const sigs = [_]u6{ linux.SIG.INT, linux.SIG.TERM };
    try signal.handle(&sigs, drone.shutdown );

    // Initialize hardware and system components
    var cfg = pigpio.gpioCfgGetInternals();
    cfg |= 1 << 10; // Disable signal usage by pigpio since we need it for our own signal handling
    _ = try err.check(pigpio.gpioCfgSetInternals(cfg));
    _ = err.check(pigpio.gpioInitialise()) catch |e| {
        log.err("failed to initialize pigpio, are you root?", .{});
        return e;
    };
    defer pigpio.gpioTerminate();
    pixy.init() catch |e| {
        log.err("failed to connect to Pixy camera, are you sure it's plugged in/does this user have USB privileges?", .{});
        return e;
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
        loop() catch |e| {
            log.err("main loop threw error: {}", .{ e });
            break; // Break out of the loop to safely shut down
        };
    }
    // No shutdown routine is needed here, all deinits have already been deferred
    log.info("shutting down...", .{});
}

inline fn loop() !void {
    try quad.update();
}
