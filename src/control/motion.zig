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

const ALT_OFFSET: f32 = 0.0; // Offset from ultrasonic sensor to ground, in cm
const INITIAL_HOVER_ALT: f32 = 50.0; // cm
const MAX_ALT: f32 = 350.0; // cm

var sonar = ultrasonic.HC_SR04{ .trig = 5, .echo = 5 };

// PID controllers for X, Y, and Z movement
// TODO: tune params
var pid_x = PID.Controller{
    .kp = 0.5,
    .ki = 0.0,
    .kd = 0.2,
    .tau = 0.1,
    .lim_min = -3.0,
    .lim_max = 3.0,
};
var pid_y = PID.Controller{
    .kp = 0.5,
    .ki = 0.0,
    .kd = 0.2,
    .tau = 0.1,
    .lim_min = -3.0,
    .lim_max = 3.0,
};
var pid_z = PID.Controller{
    .kp = 0.5,
    .ki = 0.0,
    .kd = 0.2,
    .tau = 0.1,
    .lim_min = -2.0,
    .lim_max = 2.0,
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
    var buf: [pixy.MAX_BLOCKS]pixy.Block = undefined;
    const blocks = try pixy.getBlocks(&buf);
    if (blocks.len == 0) {
        log.warn("no blocks detected", .{});
        return;
    }
    const block = blocks[0];

    pid_x.update(@floatCast(pixy.FRAME_WIDTH / 2), @floatFromInt(block.x));
    pid_y.update(@floatCast(pixy.FRAME_HEIGHT / 2), @floatFromInt(block.y));
    pid_z.update(@floatCast(alt), @floatCast(try sonar.measure() - ALT_OFFSET));

    quad.roll = @floatCast(pid_x.out);
    quad.pitch = @floatCast(pid_y.out);
    quad.base = @floatCast(pid_z.out);

    try quad.update();
}
