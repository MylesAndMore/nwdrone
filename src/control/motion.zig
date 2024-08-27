//! Handles motion of the quadcopter in 3D space.
//! This is one step above quad motor control.

const std = @import("std");
const log = std.log.scoped(.motion);

pub const quad = @import("quad.zig");

pub const pixy = @import("../device/pixy.zig");
pub const ultrasonic = @import("../device/ultrasonic.zig");

pub const PID = @import("../lib/pid.zig");

pub const sockets = @import("../remote/sockets.zig");

// Quadcopter's altitude, in cm (read-write).
pub var alt: f32 = 0.0;

const ALT_OFFSET: f32 = 7.0; // Offset from ultrasonic sensor to ground, in cm
const IGNORE_XY_GUIDANCE_BELOW_ALT: f32 = 10.0; // cm
const INITIAL_HOVER_ALT: f32 = 50.0; // cm
const MAX_ALT: f32 = 350.0; // cm

var sonar = ultrasonic.HC_SR04{ .trig = 17, .echo = 27 };

// PID controllers for X, Y, and Z movement
// TODO: tune params
var pid_x = PID.Controller {
    .kp = 0.5,
    .ki = 0.0,
    .kd = 0.2,
    .tau = 0.1,
    .lim_min = -3.0,
    .lim_max = 3.0,
};
var pid_y = PID.Controller {
    .kp = 0.5,
    .ki = 0.0,
    .kd = 0.2,
    .tau = 0.1,
    .lim_min = -3.0,
    .lim_max = 3.0,
};
var pid_z = PID.Controller {
    .kp = 0.5,
    .ki = 0.01,
    .kd = 0.2,
    .tau = 0.1,
    .lim_min = 0.0,
    .lim_max = 40.0,
};

/// Event handler for the `takeoff` event.
fn takeoffEvent(_: sockets.SocketData) !void {
    takeoff();
}

/// Event handler for the `land` event.
fn landEvent(_: sockets.SocketData) !void {
    land();
}

/// Initialize the motion controller.
pub fn init(allocator: std.mem.Allocator) !void {
    try quad.init(allocator);
    try sonar.init();
    try sockets.subscribe("takeoff", takeoffEvent, .Receive);
    try sockets.subscribe("land", landEvent, .Receive);
}

/// Deinitialize the motion controller.
pub fn deinit() void {
    sockets.unsubscribe("land");
    sockets.unsubscribe("takeoff");
    sonar.deinit();
    quad.deinit();
}

/// Initiate takeoff of the quadcopter.
/// This function blocks for a significant amount of time (~2s) while the
/// quadcopter prepares for takeoff.
/// The actual takeoff is performed in `update()`.
pub fn takeoff() void {
    log.info("preparing for takeoff...", .{});
    // Try a maximum of 10 times to zero the quadcopter's attitude
    var tries: usize = 0;
    while (tries < 10) {
        log.info("zeroing attitude (try {})", .{ tries });
        const zeroed = quad.zeroAttitude() catch |err| {
            log.warn("failed to zero attitude ({})", .{ err });
            return;
        };
        if (zeroed)
            break;
        tries += 1;
    }
    if (tries == 10) {
        log.warn("failed to zero attitude (timed out)", .{});
        return;
    }
    quad.rev();
    alt = INITIAL_HOVER_ALT;
    log.info("taking off!", .{});
}

/// Initiate landing of the quadcopter.
/// The actual landing is performed in `update()`.
pub fn land() void {
    log.info("landing...", .{});
    alt = 0.0;
}

/// Update the motion controller.
pub fn update() !void {
    // Default target is the center of the frame (aka perfectly on target)
    var target_x: u16 = pixy.HALF_FRAME_WIDTH;
    var target_y: u16 = pixy.HALF_FRAME_HEIGHT;
    var buf: [pixy.MAX_BLOCKS]pixy.Block = undefined;
    const blocks = try pixy.getBlocks(&buf);
    // If we are in a good position to lock onto a target, do so
    // "Good position" is defined as one or more blocks detected and above a min alt
    if (blocks.len > 1 and alt > IGNORE_XY_GUIDANCE_BELOW_ALT) {
        var block = blocks[0];
        // Find the largest block; that's what we'll lock onto
        for (blocks[1..]) |b| {
            if (b.width * b.height > block.width * block.height)
                block = b;
        }
        target_x = blocks[0].x;
        target_y = blocks[0].y;
    }

    pid_x.update(@floatFromInt(pixy.HALF_FRAME_WIDTH), @floatFromInt(target_x));
    pid_y.update(@floatFromInt(pixy.HALF_FRAME_HEIGHT), @floatFromInt(target_y));
    // pid_z.update(@floatCast(alt), @floatCast(try sonar.measure() - ALT_OFFSET));
    pid_z.update(@floatCast(alt), @floatCast(0.0));

    quad.roll = @floatCast(pid_x.out);
    quad.pitch = @floatCast(pid_y.out);
    quad.base = @floatCast(pid_z.out);

    try quad.update();
}
