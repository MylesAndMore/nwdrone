//! Handles motion of the quadcopter in 3D space.
//! This is one step above quad motor control.

const std = @import("std");
const fmt = std.fmt;
const log = std.log.scoped(.motion);
const time = std.time;

pub const quad = @import("quad.zig");

pub const pixy = @import("../device/pixy.zig");
pub const ultrasonic = @import("../device/ultrasonic.zig");

pub const PID = @import("../lib/pid.zig");

pub const sockets = @import("../remote/sockets.zig");

const MotionState = enum {
    IDLE,
    REV,
    TAKEOFF,
    BLOCKLOCK,
    TELEOP,
    LAND,
};

// Quadcopter's altitude, in cm (read-write).
pub var alt: f32 = 0.0;

const MAX_UPDATE_RATE = 200; // update will be throttled to this rate if needed, hz
const MAX_UPDATE_PERIOD = time.ms_per_s / MAX_UPDATE_RATE;
pub const PIDS_TAU = 0.1 * MAX_UPDATE_PERIOD; // tau constant for PID controllers, including those nested under motion controller

const LANDED_ALT = 5.0; // cm
const IGNORE_XY_GUIDANCE_BELOW_ALT = 10.0; // cm
const INITIAL_HOVER_ALT = 50.0; // cm
const MAX_ALT = 350.0; // cm

const ALT_OFFSET = 7.0; // Offset from ultrasonic sensor to ground, in cm
const CUTOFF_THRUST = 10.0; // Thrust at which to cut motors, in percent

var sonar = ultrasonic.HC_SR04{ .trig = 17, .echo = 27 };
var prev_update: i64 = 0; // Time of the previous call to update()
var state = MotionState.IDLE; // Current state of the motion controller

// PID controllers for X, Y, and Z movement
// TODO: tune params
var pid_x = PID.Controller {
    .kp = 0.1,
    .ki = 0.0,
    .kd = 0.2,
    .tau = PIDS_TAU,
    .lim_min = -3.0,
    .lim_max = 3.0,
};
var pid_y = PID.Controller {
    .kp = 0.1,
    .ki = 0.0,
    .kd = 0.2,
    .tau = PIDS_TAU,
    .lim_min = -3.0,
    .lim_max = 3.0,
};
var pid_z = PID.Controller {
    .kp = 0.1,
    .ki = 0.3,
    .kd = 0.5,
    .tau = PIDS_TAU,
    .lim_min = 0.0,
    .lim_max = 40.0,
};

/// Event handler for the `takeoff` event.
fn takeoffEvent(_: sockets.SocketData) !void {
    if (state == .IDLE)
        takeoff();
}

/// Event handler for the `land` event.
fn landEvent(_: sockets.SocketData) !void {
    land();
}

/// Event handler for the `move` event.
fn moveEvent(event: sockets.SocketData) !void {
    const map = event.data.map;

    // Possible cases for automatically switching into teleop
    switch (state) {
        .IDLE => takeoff(), // Takeoff -> blocklock -> teleop
        .BLOCKLOCK => state = .TELEOP,
        else => {},
    }
    if (state != .TELEOP)
        return;

    if (map.get("roll")) |roll|
        quad.roll = try fmt.parseFloat(@TypeOf(quad.roll), roll);
    if (map.get("pitch")) |pitch|
        quad.pitch = try fmt.parseFloat(@TypeOf(quad.pitch), pitch);
}

/// Initialize the motion controller.
pub fn init(allocator: std.mem.Allocator) !void {
    try quad.init(allocator);
    try sonar.init();
    try sockets.subscribe("takeoff", takeoffEvent, .Receive);
    try sockets.subscribe("land", landEvent, .Receive);
    try sockets.subscribe("move", moveEvent, .Receive);
}

/// Deinitialize the motion controller.
pub fn deinit() void {
    sockets.unsubscribe("move");
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
    log.info("taking off!", .{});
    state = .REV;
}

/// Initiate landing of the quadcopter.
/// The actual landing is performed in `update()`.
pub fn land() void {
    log.info("landing...", .{});
    state = .LAND;
    alt = 0.0;
}

/// Update the motion controller.
pub fn update() !void {
    if (time.milliTimestamp() - prev_update < MAX_UPDATE_PERIOD)
        return;

    // Get altitude from ultrasonic sensor
    const meas_alt = try sonar.measure() - ALT_OFFSET;
    if (meas_alt > MAX_ALT) {
        log.warn("altitude too high, landing...", .{});
        land();
    }

    switch (state) {
        .REV => {
            quad.rev();
            alt = INITIAL_HOVER_ALT;
            state = .TAKEOFF;
        },
        .TAKEOFF => {
            if (meas_alt > INITIAL_HOVER_ALT - 5.0) {
                state = .BLOCKLOCK;
                log.info("in flight!", .{});
            }
        },
        .BLOCKLOCK => {
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
                target_x = block.x;
                target_y = block.y;
            }
            // Update PIDs and send to quad controller
            pid_x.update(@floatFromInt(pixy.HALF_FRAME_WIDTH), @floatFromInt(target_x));
            pid_y.update(@floatFromInt(pixy.HALF_FRAME_HEIGHT), @floatFromInt(target_y));
            quad.roll = @floatCast(pid_x.out);
            quad.pitch = @floatCast(pid_y.out);
        },
        // --All movement for teleop happens in the move event handler--
        .LAND => {
            if (meas_alt < LANDED_ALT) {
                log.info("landed!", .{});
                state = .IDLE;
            }
        },
        else => {},
    }

    // Z (altitude) PID is updated regardless of state
    pid_z.update(@floatCast(alt), @floatCast(meas_alt));
    if (pid_z.out < CUTOFF_THRUST) {
        quad.base = 0.0;
    } else {
        quad.base = @floatCast(pid_z.out);
    }
    
    try quad.update();

    prev_update = time.milliTimestamp();
}
