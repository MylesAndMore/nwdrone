//! Handles quad motor control between all four motors.

const std = @import("std");
const fmt = std.fmt;
const log = std.log.scoped(.quad);
const math = std.math;
const time = std.time;

pub const motor = @import("../device/motor.zig");
pub const mpu = @import("../device/mpu6050.zig");

pub const math3d = @import("../lib/math3d.zig");
pub const PID = @import("../lib/pid.zig");

pub const sockets = @import("../remote/sockets.zig");

pub const drone = @import("../drone.zig");

// Quadcopter's attitude, relative to the inertial frame, in degrees (read-write).
pub var roll: f32 = 0.0;
pub var pitch: f32 = 0.0;
pub var yaw: f32 = 0.0;
// Base thrust value for all motors, 0-100% (read-write).
pub var base: f32 = 0.0;
// Euler angles of the quadcopter (read-only).
pub var angles = math3d.Vec3{ 0.0, 0.0, 0.0 };

const MAX_UPDATE_RATE = 200; // update will be throttled to this rate if needed, hz
const MAX_UPDATE_PERIOD = time.ms_per_s / MAX_UPDATE_RATE;

var alloc: std.mem.Allocator = undefined;
var orient_data: sockets.SocketData = undefined; // SocketData used to send orientation data

var fl = motor.Motor{ .pin = 6, .pw_min = 1030.0, .pw_max = 1450.0 }; // front left (CW)
var fr = motor.Motor{ .pin = 13, .pw_min = 1230.0, .pw_max = 1750.0 }; // front right (CCW)
var bl = motor.Motor{ .pin = 19, .pw_min = 1200.0, .pw_max = 1700.0 }; // back left (CCW)
var br = motor.Motor{ .pin = 26, .pw_min = 1230.0, .pw_max = 1730.0 }; // back right (CW)
var motors = [_]*motor.Motor{ &fl, &fr, &bl, &br };

var offsets = math3d.Vec3{ 0.0, 0.0, 0.0 }; // Angle offsets set by zeroAttitude()

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

/// Event dispatcher for the `orient` event.
fn orientEvent(send: sockets.SendFn) !void {
    const FmtStr = [fmt.format_float.min_buffer_size]u8;
    const FmtOpts: fmt.format_float.FormatOptions = .{ .mode = .decimal, .precision = 2 };

    orient_data.event = "orient";

    var r_buf: FmtStr = undefined;
    var p_buf: FmtStr = undefined;
    var y_buf: FmtStr = undefined;
    try orient_data.data.map.put(alloc, "roll", try fmt.formatFloat(&r_buf, angles[0], FmtOpts));
    try orient_data.data.map.put(alloc, "pitch", try fmt.formatFloat(&p_buf, angles[1], FmtOpts));
    try orient_data.data.map.put(alloc, "yaw", try fmt.formatFloat(&y_buf, angles[2], FmtOpts));

    try send(orient_data);
}

/// Initialize all quadcopter motors.
/// This function blocks for a significant amount of time (~4s) during
/// initialization.
pub fn init(allocator: std.mem.Allocator) !void {
    try mpu.init(); // Init mpu first so dmp can get started

    for (motors) |m|
        try m.init();
    // Wait for controllers to do their...beeping
    time.sleep(time.ns_per_s * 4);
    for (motors) |m|
        try m.startUpdateAsync();
    log.info("all motors initialized and updating", .{});

    alloc = allocator;
    orient_data = try sockets.SocketData.init();
    try sockets.subscribe("orient", orientEvent, .Dispatch);
}

/// Deinitialize all quadcopter motors.
pub fn deinit() void {
    sockets.unsubscribe("orient");
    orient_data.deinit(alloc);
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
    const q = try mpu.getQuaternion() orelse return false;
    offsets = q.toEuler();
    return true;
}

/// Update the quadcopter motors.
/// This should be called at a regular interval to keep the drone in a stable pose.
pub fn update() !void {
    if (time.milliTimestamp() - prev_update < MAX_UPDATE_PERIOD)
        return;

    var q = try mpu.getQuaternion() orelse return;
    angles = q.toEuler() - offsets;

    // If thrust is (basically) zero, don't bother with any logic
    if (base <= 0.0) {
        setThrust(0.0);
        return;
    }

    pid_roll.update(@floatCast(roll), @floatCast(angles[0]));
    pid_pitch.update(@floatCast(pitch), @floatCast(angles[1]));
    pid_yaw.update(@floatCast(yaw), @floatCast(angles[2]));

    const roll_out = pid_roll.out;
    const pitch_out = pid_pitch.out;
    const yaw_out = pid_yaw.out;

    var thrusts = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    thrusts[0] = @floatCast(base + roll_out + pitch_out + yaw_out);
    thrusts[1] = @floatCast(base - roll_out + pitch_out - yaw_out);
    thrusts[2] = @floatCast(base + roll_out - pitch_out - yaw_out);
    thrusts[3] = @floatCast(base - roll_out - pitch_out + yaw_out);
    for (motors, &thrusts) |m, *thrust| {
        if (math.isNan(thrust.*)) {
            log.err("NaN thrust value calculated {}", .{thrust.*});
            drone.shutdown();
        }
        thrust.* = math.clamp(thrust.*, 0.0, 100.0);
        m.thrust = thrust.*;
    }

    prev_update = time.milliTimestamp();
}
