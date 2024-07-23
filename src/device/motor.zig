//! Provides motor (ESC) control.

const std = @import("std");
const log = std.log;

pub const pwm = @import("../hw/pwm.zig");

const ESC_FREQ = 50; // Frequency of the ESC PWM signal (Hz)

// TODO: tune these
const MOTOR_IDLE_PW = 1000.0; // Pulsewidth at which the motor is idle/not moving (μs)
const MOTOR_MIN_PW = 1200.0; // Pulsewidth at which the motor starts spinning (μs)
const MOTOR_MAX_PW = 2000.0; // Pulsewidth at which the motor spins at full speed (μs)
const MIN_UPDATE_INTERVAL = 1000; // Minimum time between motor updates (μs)
const MOTOR_LERP_BY = 0.015;

inline fn map(x: anytype, in_min: anytype, in_max: anytype, out_min: anytype, out_max: anytype) @TypeOf(x, in_min, in_max, out_min, out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

// TODO: update on another thread?

// A single motor, controlled by an ESC connected to a GPIO pin.
pub const Motor = struct {
    pin: u32, // GPIO pin (read-only after init)
    thrust: f32 = 0.0, // Motor thrust, 0.0 to 100.0 (read-write)
    // -- private --
    prev_target: f32 = 0.0, // Thrust value from the previous update
    prev_update: i64 = 0, // Time of the previous update

    /// Initialize the motor.
    pub fn init(self: *@This()) !void {
        try pwm.init(self.pin, ESC_FREQ);
        try pwm.setPulsewidth(self.pin, MOTOR_IDLE_PW);
    }

    /// Deinitialize the motor.
    pub fn deinit(self: *@This()) void {
        self.kill();
        // PWM module has no deinit
    }

    pub fn update(self: *@This()) !void {
        // Throttle update rate, so as to ensure lerp is predictable
        if (std.time.microTimestamp() - self.prev_update < MIN_UPDATE_INTERVAL)
            return;
        // If zero thrust, bypass mapping and set directly to idle
        if (self.thrust <= 0) {
            try pwm.setPulsewidth(self.pin, MOTOR_IDLE_PW);
            return;
        }
        // Perform linear interpolation between previous and current thrust to smooth out any rapid thrust changes
        const target = std.math.lerp(self.prev_target, self.thrust, MOTOR_LERP_BY);
        self.prev_target = target;
        // Map thrust to pulsewidth and set
        const pulsewidth = map(target, 0.0, 100.0, MOTOR_MIN_PW, MOTOR_MAX_PW);
        try pwm.setPulsewidth(self.pin, pulsewidth);
    }

    /// Forcefully and instantly "kill" the motor.
    /// 
    /// This sets the motor's corresponding speed controller line to zero,
    /// which might make it believe the controller has disconnected, which can
    /// make it beep a bit.
    pub fn kill(self: *@This()) void {
        pwm.setDuty(self.pin, 0) catch |err| {
            log.err("failed to kill motor ({})!", .{ err });
        };
    }
};
