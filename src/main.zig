const std = @import("std");
const linux = std.os.linux;
const log = std.log.scoped(.main);

// All (relavent) imported namespaces are marked public so as to appear in documentation.
// This is done in all files.

pub const quad = @import("control/quad.zig");

pub const pixy = @import("device/pixy.zig");

pub const err = @import("lib/err.zig");
pub const pigpio = @cImport({ @cInclude("pigpio.h"); });
pub const signal = @import("lib/signal.zig");

pub const server  = @import("remote/server.zig");
pub const sockets = @import("remote/sockets.zig");

pub const drone = @import("drone.zig");

pub fn main() !void {
    // killHost() is deferred at the start of main() so it is called last,
    // and will only kill the host if it has been requested to do so
    defer drone.killHost();
    // Create our allocator to be used for all heap allocations
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Connect our shutdown function to the SIGINT and SIGTERM signals,
    // so that the drone can be safely shut down if the process must be terminated
    const sigs = [_]u6{ linux.SIG.INT, linux.SIG.TERM };
    try signal.handle(&sigs, drone.shutdown );

    // Initialize the webserver for remote control
    // This is done now so that other modules can subscribe to websocket events
    try server.start(alloc);
    defer server.stop();
    // Subscribe to kill and shutdown events so the drone/system can be safely shut down
    try sockets.subscribe("kill", killEvent);
    try sockets.subscribe("shutdown", shutdownEvent);

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

    std.time.sleep(std.time.ns_per_s * 10);
    _ = try quad.zeroAttitude();

    // Once everything is initialized, we can enter the main loop
    // This is wrapped to catch any errors that make their way up here,
    // so that we can put the drone into a safe state before the program exits
    // The loop will also exit if any external functions call `drone.shutdown()`
    while (drone.safe) {
        loop() catch |e| {
            log.err("loop threw error: {}", .{ e });
            break; // Break out of the loop to safely shut down
        };
    }
    // No shutdown routine is needed here, all deinits have already been deferred
    log.info("shutting down...", .{});
}

/// Main control loop for the drone.
inline fn loop() !void {
    try quad.update();
    std.time.sleep(std.time.ns_per_ms * 5);
}

fn killEvent(_: sockets.Data) void {
    drone.shutdown();
}

fn shutdownEvent(_: sockets.Data) void {
    drone.shutdownHost();
}
