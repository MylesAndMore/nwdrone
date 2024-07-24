//! Handles quad motor control between all four motors.

const std = @import("std");
const log = std.log;
const time = std.time;

pub const motor = @import("../device/motor.zig");

pub const PID = @import("../lib/pid.zig");

// Publicly modifiable variables for the quadcopter's attitude, relative to the
// inertial frame, in degrees.
pub var roll: f32 = 0.0;
pub var pitch: f32 = 0.0;
pub var yaw: f32 = 0.0;

const MAX_UPDATE_RATE = 200; // update will be throttled to this rate if needed, hz
const MAX_UPDATE_PERIOD = time.ms_per_s / MAX_UPDATE_RATE;

var fl = motor.Motor{ .pin = 6, .pw_min = 1030.0, .pw_max = 1450.0 }; // front left (CW)
var fr = motor.Motor{ .pin = 13, .pw_min = 1230.0, .pw_max = 1750.0 }; // front right (CCW)
var bl = motor.Motor{ .pin = 19, .pw_min = 1200.0, .pw_max = 1700.0 }; // back left (CCW)
var br = motor.Motor{ .pin = 26, .pw_min = 1230.0, .pw_max = 1730.0 }; // back right (CW)
var motors = [_]*motor.Motor{ &fl, &fr, &bl, &br };

// PID controllers for roll, pitch, and yaw
// TODO: tune params
var pid_roll = PID.Controller {
    .kp = 1.0,
    .ki = 0.0,
    .kd = 0.0,
    .tau = 0.1 * MAX_UPDATE_PERIOD,
    .lim_min = -1.0,
    .lim_max = 1.0,
};
var pid_pitch = PID.Controller {
    .kp = 1.0,
    .ki = 0.0,
    .kd = 0.0,
    .tau = 0.1 * MAX_UPDATE_PERIOD,
    .lim_min = -1.0,
    .lim_max = 1.0,
};
var pid_yaw = PID.Controller {
    .kp = 1.0,
    .ki = 0.0,
    .kd = 0.0,
    .tau = 0.1 * MAX_UPDATE_PERIOD,
    .lim_min = -1.0,
    .lim_max = 1.0,
};

var prev_update: i64 = 0; // Time of the previous call to update()

/// Apply `thrust` to all motors.
inline fn setThrust(thrust: f32) void {
    for (motors) |m|
        m.thrust = thrust;
}

/// Initialize all quadcopter motors.
/// This function blocks for a significant amount of time (~4s) during
/// initialization.
pub fn init() !void {
    for (motors) |m|
        try m.init();
    // Wait for controllers to do their...beeping
    time.sleep(time.ns_per_s * 4);
    for (motors) |m|
        try m.startUpdateAsync();
    log.info("all motors initialized and updating", .{});
}

/// Deinitialize all quadcopter motors.
pub fn deinit() void {
    for (motors) |m|
        m.deinit();
    log.info("all motors deinitialized", .{});
}

/// Rev all motors in a sequence.
/// This function blocks for a significant amount of time (~2s) during the
/// sequence.
pub fn rev() void {
    setThrust(2.0);
    time.sleep(std.time.ns_per_s * 1);
    setThrust(20.0);
    time.sleep(std.time.ns_per_ms * 200);
    setThrust(5.0);
    time.sleep(std.time.ns_per_ms * 300);
    setThrust(30.0);
    time.sleep(std.time.ns_per_ms * 200);
    setThrust(5.0);
    time.sleep(std.time.ns_per_ms * 400);
}

/// Update the quadcopter motors.
/// This should be called at a regular interval to keep the drone in a stable pose.
pub fn update() void {
    if (time.milliTimestamp() - prev_update < MAX_UPDATE_PERIOD)
        return;
    
    

    prev_update = time.milliTimestamp();
}

// TODO: rest of quad impl should contain:
// - ability to set roll, pitch, and yaw attitudes
// - ability to set altitude? or at least thrust
// - should be able to handle keeping differential thrust whilst changing overall thrust
// it should (probably) not contain:
// - ability to set individual motor thrusts (that should be done in this module; that's its abstraction)
