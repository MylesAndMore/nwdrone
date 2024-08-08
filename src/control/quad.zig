//! Handles quad motor control between all four motors.

const std = @import("std");
const log = std.log.scoped(.quad);
const time = std.time;

pub const motor = @import("../device/motor.zig");
pub const mpu = @import("../device/mpu6050.zig");

pub const math3d = @import("../lib/math3d.zig");
pub const PID = @import("../lib/pid.zig");

pub const sockets = @import("../remote/sockets.zig");

pub const drone = @import("../drone.zig");

// Publicly modifiable variables for the quadcopter's attitude, relative to the
// inertial frame, in degrees.
pub var roll: f32 = 0.0;
pub var pitch: f32 = 0.0;
pub var yaw: f32 = 0.0;
// Base thrust value for all motors.
pub var base: f32 = 0.0;

const MAX_UPDATE_RATE = 400; // update will be throttled to this rate if needed, hz
const MAX_UPDATE_PERIOD = time.ms_per_s / MAX_UPDATE_RATE;

var fl = motor.Motor{ .pin = 6, .pw_min = 1030.0, .pw_max = 1450.0 }; // front left (CW)
var fr = motor.Motor{ .pin = 13, .pw_min = 1230.0, .pw_max = 1750.0 }; // front right (CCW)
var bl = motor.Motor{ .pin = 19, .pw_min = 1200.0, .pw_max = 1700.0 }; // back left (CCW)
var br = motor.Motor{ .pin = 26, .pw_min = 1230.0, .pw_max = 1730.0 }; // back right (CW)
var motors = [_]*motor.Motor{ &fl, &fr, &bl, &br };

// IMU offsets set by zeroAttitude()
var offsets = math3d.Vec3{ 0.0, 0.0, 0.0 };

// PID controllers for roll, pitch, and yaw
// TODO: tune params
var pid_roll = PID.Controller {
    .kp = 0.5,
    .ki = 0.0,
    .kd = 0.2,
    .tau = 0.1 * MAX_UPDATE_PERIOD,
    .lim_min = -5.0,
    .lim_max = 5.0,
};
var pid_pitch = PID.Controller {
    .kp = 0.5,
    .ki = 0.0,
    .kd = 0.2,
    .tau = 0.1 * MAX_UPDATE_PERIOD,
    .lim_min = -5.0,
    .lim_max = 5.0,
};
var pid_yaw = PID.Controller {
    .kp = 1.0,
    .ki = 0.0,
    .kd = 0.0,
    .tau = 0.1 * MAX_UPDATE_PERIOD,
    .lim_min = -5.0,
    .lim_max = 5.0,
};

var prev_update: i64 = 0; // Time of the previous call to update()

/// Apply `thrust` to all motors.
fn setThrust(thrust: f32) void {
    for (motors) |m|
        m.thrust = thrust;
}

/// Initialize all quadcopter motors.
/// This function blocks for a significant amount of time (~4s) during
/// initialization.
pub fn init() !void {
    try mpu.init(); // Init mpu first so dmp can get started

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

/// Zero the quadcopter's attitude.
/// This should only be done when the quadcopter is on a known level surface;
/// all future orientation calculations will be relative to this position.
/// 
/// It is recomended to call this function 10-40 seconds after the IMU has been
/// initialized to allow the DMP to stabilize.
/// 
/// Returns false if the current attitude could not be obtained.
pub fn zeroAttitude() !bool {
    const q = try mpu.get_quaternion() orelse return false;
    offsets = q.toEuler();
    return true;
}

/// Update the quadcopter motors.
/// This should be called at a regular interval to keep the drone in a stable pose.
pub fn update() !void {
    if (time.milliTimestamp() - prev_update < MAX_UPDATE_PERIOD)
        return;

    // If thrust is (basically) zero, don't bother with any logic
    if (base < 0.2) {
        setThrust(0.0);
        return;
    }

    var q = try mpu.get_quaternion() orelse return;
    const angles = q.toEuler() - offsets;

    pid_roll.update(@floatCast(roll), @floatCast(angles[0]));
    pid_pitch.update(@floatCast(pitch), @floatCast(angles[1]));
    pid_yaw.update(@floatCast(yaw), @floatCast(angles[2]));

    const roll_out = pid_roll.out;
    const pitch_out = pid_pitch.out;
    const yaw_out = pid_yaw.out;

    fl.thrust = @floatCast(base + roll_out + pitch_out + yaw_out);
    fr.thrust = @floatCast(base - roll_out + pitch_out - yaw_out);
    bl.thrust = @floatCast(base + roll_out - pitch_out - yaw_out);
    br.thrust = @floatCast(base - roll_out - pitch_out + yaw_out);

    if (std.math.isNan(fl.thrust) or std.math.isNan(fr.thrust) or std.math.isNan(bl.thrust) or std.math.isNan(br.thrust)) {
        log.err("NaN thrust values calculated", .{});
        drone.shutdown();
    }

    // Clamp thrusts to valid range
    for (motors) |m|
        m.thrust = std.math.clamp(m.thrust, 0.0, 100.0);

    prev_update = time.milliTimestamp();
}
