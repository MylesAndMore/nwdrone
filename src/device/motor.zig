//! Provides motor (ESC) control.

const std = @import("std");
const log = std.log.scoped(.motor);
const Thread = std.Thread;
const time = std.time;

pub const pwm = @import("../hw/pwm.zig");

pub const math = @import("../lib/math.zig");

pub const drone = @import("../drone.zig");

const MotorError = error{
    OutOfRange,
};

const ESC_FREQ = 50; // Frequency of the ESC PWM signal (Hz)

const MOTOR_IDLE_PW = 900.0; // Pulsewidth at which the motor is idle/not moving (μs)

const MIN_UPDATE_INTERVAL = 10; // Minimum time between motor updates (ms)
const MOTOR_LERP_BY = 0.1; // Linear interpolation factor for thrust changes

// A single motor, controlled by an ESC connected to a GPIO pin.
pub const Motor = struct {
    pin: u32, // GPIO pin (read-only after init)
    pw_min: f32, // Pulsewidth at which the motor starts spinning, μs (read-only after init)
    pw_max: f32, // Pulsewidth at which the motor spins at full speed, μs (read-only after init)
    thrust: f32 = 0.0, // Motor thrust, 0.0 to 100.0 (read-write)
    // -- private --
    prev_target: f32 = 0.0, // Thrust value from the previous update
    prev_update: i64 = 0, // Time of the previous update
    update_async: bool = false, // Whether the motor is updating asynchronously

    /// Initialize the motor.
    pub fn init(self: *const @This()) !void {
        try pwm.init(self.pin, ESC_FREQ);
        try pwm.setPulsewidth(self.pin, MOTOR_IDLE_PW);
        log.info("initialized motor on pin {}", .{ self.pin });
    }

    /// Deinitialize the motor.
    pub fn deinit(self: *@This()) void {
        self.kill();
        // PWM module has no deinit
        log.info("deinitialized motor on pin {}", .{ self.pin });
    }

    /// Update the motor's outputt according to the current thrust value.
    /// This function should be called periodically to keep the motor's output fresh.
    pub fn update(self: *@This()) !void {
        // Throttle the update rate, so as to ensure lerp is predictable
        if (time.milliTimestamp() - self.prev_update < MIN_UPDATE_INTERVAL)
            return;
        if (self.thrust < -0.2 or self.thrust > 100.0)
            return error.OutOfRange;
        // If (basically) zero thrust, bypass mapping and set directly to idle
        if (self.thrust < 0.2) {
            try pwm.setPulsewidth(self.pin, MOTOR_IDLE_PW);
            return;
        }
        // Perform linear interpolation between previous and current thrust to smooth out any rapid thrust changes
        const target = std.math.lerp(self.prev_target, self.thrust, MOTOR_LERP_BY);
        self.prev_target = target;
        // Map thrust to pulsewidth and set
        const pulsewidth = math.map(target, 0.0, 100.0, self.pw_min, self.pw_max);
        try pwm.setPulsewidth(self.pin, pulsewidth);
        self.prev_update = time.milliTimestamp();
    }
    
    /// Start updating the motor asynchronously.
    /// This function will spawn a new thread to call `update` periodically.
    pub fn startUpdateAsync(self: *@This()) !void {
        @atomicStore(bool, &self.update_async, true, .seq_cst);
        const thread = try Thread.spawn(.{}, motorThread, .{ self });
        thread.detach();
        log.info("started async motor.update() for motor {} on thread {}", .{ self.pin, thread.getHandle() });
    }

    /// Stop updating the motor asynchronously.
    pub fn stopUpdateAsync(self: *@This()) void {
        // This will kill the thread
        @atomicStore(bool, &self.update_async, false, .seq_cst);
        log.info("stopped async motor.update() for motor {}", .{ self.pin });
    }

    /// Forcefully and instantly "kill" the motor.
    /// 
    /// This sets the motor's corresponding speed controller line to zero,
    /// which might make it believe the controller has disconnected, which can
    /// make it beep a bit.
    pub fn kill(self: *@This()) void {
        self.stopUpdateAsync();
        // Wait a bit for the thread to stop to make sure the following
        // setDuty doesn't get overwritten by the thread
        // TODO: better way to do this?
        time.sleep(time.ns_per_ms * 5);
        pwm.setDuty(self.pin, 0) catch |err| {
            log.err("failed to kill motor! ({})", .{ err });
        };
    }
};

/// Update `motor` while its `update_async` field is `true`, handling any errors.
/// This is intended to be spawned as a separate thread.
fn motorThread(motor: *Motor) void {
    while (@atomicLoad(bool, &motor.update_async, .seq_cst)) {
        motor.update() catch |err| {
            log.err("failed to update motor! ({})", .{ err });
            motor.kill();
            drone.shutdown();
        };
        time.sleep(time.ns_per_ms * MIN_UPDATE_INTERVAL); // Sleep until next update
    }
}
