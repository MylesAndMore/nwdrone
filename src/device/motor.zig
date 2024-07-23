//! Provides motor (ESC) control.

const std = @import("std");
const log = std.log;
const Thread = std.Thread;
const time = std.time;

pub const pwm = @import("../hw/pwm.zig");

pub const safety = @import("../safety.zig");

const ESC_FREQ = 50; // Frequency of the ESC PWM signal (Hz)

// TODO: tune these
const MOTOR_IDLE_PW = 1000.0; // Pulsewidth at which the motor is idle/not moving (μs)
const MOTOR_MIN_PW = 1200.0; // Pulsewidth at which the motor starts spinning (μs)
const MOTOR_MAX_PW = 1700.0; // Pulsewidth at which the motor spins at full speed (μs)
const MIN_UPDATE_INTERVAL = 1000; // Minimum time between motor updates (μs)
const MOTOR_LERP_BY = 0.02; // Linear interpolation factor for thrust changes

/// Map a value `x` from range `in_min` to `in_max` to range `out_min` to `out_max`.
inline fn map(x: anytype, in_min: anytype, in_max: anytype, out_min: anytype, out_max: anytype) @TypeOf(x, in_min, in_max, out_min, out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

/// Update `motor` in an infinite loop, handling any errors.
/// This is intended to be spawned as a separate thread.
fn motorThread(motor: *Motor) void {
    while (true) {
        motor.update() catch |err| {
            log.err("failed to update motor ({})!", .{ err });
            motor.kill();
            safety.shutdown();
        };
        time.sleep(time.ns_per_us * MIN_UPDATE_INTERVAL); // Sleep until next update
    }
}

// A single motor, controlled by an ESC connected to a GPIO pin.
pub const Motor = struct {
    pin: u32, // GPIO pin (read-only after init)
    thrust: f32 = 0.0, // Motor thrust, 0.0 to 100.0 (read-write)
    // -- private --
    prev_target: f32 = 0.0, // Thrust value from the previous update
    prev_update: i64 = 0, // Time of the previous update
    sem: Thread.Semaphore = Thread.Semaphore{}, // Semaphore for async updates

    /// Initialize the motor.
    pub fn init(self: *@This()) !void {
        try pwm.init(self.pin, ESC_FREQ);
        try pwm.setPulsewidth(self.pin, MOTOR_IDLE_PW);
    }

    /// Deinitialize the motor.
    pub inline fn deinit(self: *@This()) void {
        self.kill();
        // PWM module has no deinit
    }

    /// Update the motor's outputt according to the current thrust value.
    /// This function should be called periodically to keep the motor's output fresh.
    pub fn update(self: *@This()) !void {
        // Throttle the update rate, so as to ensure lerp is predictable
        if (time.microTimestamp() - self.prev_update < MIN_UPDATE_INTERVAL)
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
    
    /// Start updating the motor asynchronously.
    /// This function will spawn a new thread to call `update` periodically.
    pub fn startUpdateAsync(self: *@This()) !void {
        self.sem.post();
        const thread = try Thread.spawn(.{}, motorThread, .{ self });
        thread.detach();
    }

    /// Stop updating the motor asynchronously.
    pub inline fn stopUpdateAsync(self: *@This()) void {
        self.sem.wait();
    }

    /// Forcefully and instantly "kill" the motor.
    /// 
    /// This sets the motor's corresponding speed controller line to zero,
    /// which might make it believe the controller has disconnected, which can
    /// make it beep a bit.
    pub fn kill(self: *@This()) void {
        self.stopUpdateAsync();
        pwm.setDuty(self.pin, 0) catch |err| {
            log.err("failed to kill motor ({})!", .{ err });
        };
    }
};
