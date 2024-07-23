//! Measures distance using an ultrasonic sensor.

const std = @import("std");
const log = std.log;
const time = std.time;

pub const gpio = @import("../hw/gpio.zig");

const UltrasonicError = error {
    Timeout,
};

const SPEED_OF_SOUND = 34300; // cm/s
const MAX_RESPONSE_WAIT_TIME = 1000; // Maximum amount of time to wait for a response from a sensor (μs)

/// Checks if it has been more than `MAX_RESPONSE_WAIT_TIME` μs since `start`.
inline fn timedOut(start: i64) bool {
    return time.microTimestamp() - start > MAX_RESPONSE_WAIT_TIME;
}

// A single instance of an HC-SR04 ultrasonic sensor.
pub const HC_SR04 = struct {
    dist: f32 = 0.0, // cm (read-only)
    trig: u32, // GPIO pin (read-only after init)
    echo: u32, // GPIO pin (read-only after init)

    /// Initialize the sensor.
    pub fn init(self: *@This()) !void {
        try gpio.init(self.trig, .Output);
        try gpio.init(self.echo, .Input);
        try gpio.set(self.trig, .Low);
    }

    /// Deinitialize the sensor.
    pub fn deinit(self: *@This()) void {
        gpio.deinit(self.trig) catch |err| {
            log.warn("failed to deinit trig pin ({})", .{ err });
        };
        gpio.deinit(self.echo) catch |err| {
            log.warn("failed to deinit echo pin ({})", .{ err });
        };
    }

    /// Perform a distance measurement.
    /// Returns the measured distance in centimeters.
    /// This value can also be accessed via the `dist` field.
    /// 
    /// This function is blocking, but it should not take more than a few milliseconds.
    pub fn measure(self: *@This()) !f32 {
        // HC-SR04 requires a 10μs pulse to trigger a measurement
        try gpio.set(self.trig, .High);
        time.sleep(time.ns_per_us * 10);
        try gpio.set(self.trig, .Low);

        const measure_start = time.microTimestamp();
        // Measure the length of the pulse sent back by the sensor
        while (try gpio.get(self.echo) == .Low or timedOut(measure_start)) {}
        if (timedOut(measure_start))
            return error.Timeout;
        const pulse_start = time.microTimestamp();
        while (try gpio.get(self.echo) == .High or timedOut(pulse_start)) {}
        if (timedOut(pulse_start))
            return error.Timeout;
        const pulse_end = time.microTimestamp();

        // Multiple time by speed to get distance (divide by 2 to account for round trip)
        self.dist = @as(f32, @floatFromInt(pulse_end - pulse_start)) * (comptime SPEED_OF_SOUND / 2.0);
        return self.dist;
    }
};
