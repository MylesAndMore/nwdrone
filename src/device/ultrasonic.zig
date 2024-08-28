//! Measures distance using an ultrasonic sensor.

// !!! VERY IMPORTANT NOTE!!!
// This ultrasonic code does not work, and I haven't been able to figure out why.
// Equivalent code in C and Python work just fine. Even calling a C library from Zig doesn't work.
// I'm really not sure what's going on here.

const std = @import("std");
const log = std.log.scoped(.ultrasonic);
const time = std.time;

pub const gpio = @import("../hw/gpio.zig");

const UltrasonicError = error {
    Timeout,
};

const SPEED_OF_SOUND = 34300.0; // cm/s
const MAX_RESPONSE_WAIT_TIME = 20000; // Maximum amount of time to wait for a response from a sensor (μs)

/// Checks if it has been more than `MAX_RESPONSE_WAIT_TIME` μs since `start`.
inline fn timedOut(start: i64) bool {
    return time.microTimestamp() - start > MAX_RESPONSE_WAIT_TIME;
}

// A single instance of an HC-SR04 ultrasonic sensor.
pub const HC_SR04 = struct {
    dist: f32 = 0.0, // cm (read-only)
    trig: u32, // GPIO pin (read-only after init)
    echo: u32, // GPIO pin (read-only after init)
    max_measure_rate: u32 = 5, // Maximum rate at which measurements can be taken, Hz (read-only after init)
    max_measure_interval: u32 = 0, // Maximum interval between measurements, ms (read-only)
    last_update: i64 = 0, // Last time a measurement was taken (read-only)

    /// Initialize the sensor.
    pub fn init(self: *@This()) !void {
        self.max_measure_interval = time.ms_per_s / self.max_measure_rate;
        try gpio.init(self.trig, .Output);
        try gpio.set(self.trig, .Low);
        log.info("initialized hc-sr04 (t: {}, e: {})", .{ self.trig, self.echo });
    }

    /// Deinitialize the sensor.
    pub fn deinit(self: *const @This()) void {
        log.info("deinitialized hc-sr04 (t: {}, e: {})", .{ self.trig, self.echo });
    }
    
    /// Perform a distance measurement.
    /// Returns the measured distance in centimeters.
    /// This value can also be accessed via the `dist` field.
    /// 
    /// This function is blocking, but will never take more than a few thousand μs.
    pub fn measure(self: *@This()) !f32 {
        if (time.milliTimestamp() - self.last_update < self.max_measure_interval)
            return self.dist;

        try gpio.set(self.trig, .Low);
        time.sleep(time.ns_per_us * 2);
        // HC-SR04 requires a 10μs pulse to trigger a measurement
        try gpio.set(self.trig, .High);
        time.sleep(time.ns_per_us * 10);
        try gpio.set(self.trig, .Low);

        var start = time.microTimestamp();
        // Measure the length of the pulse sent back by the sensor
        while (try gpio.get(self.echo) == .Low and !timedOut(start)) {}
        if (timedOut(start))
            return error.Timeout;
        start = time.microTimestamp();
        while (try gpio.get(self.echo) == .High and !timedOut(start)) {}
        const end = time.microTimestamp();

        self.dist = HC_SR04.pulsewidthToCm(@as(u32, @intCast(end - start)));
        self.last_update = time.milliTimestamp();
        return self.dist;
    }

    /// Converts a pulsewidth (in μs) to a distance (in cm).
    fn pulsewidthToCm(pulsewidth: u32) f32 {
        return @as(f32, @floatFromInt(pulsewidth)) * comptime (SPEED_OF_SOUND / @as(f32, time.us_per_s) * 2.0);
    }
};

test "HC-SR04 pulsewidthToCm" {
    const pulsewidths  = [_]u32{ 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000 };
    const dists = [_]f32{ 6.9, 13.7, 20.55, 27.4, 34.25, 41.1, 47.95, 54.8, 61.65, 68.5 };
    for (pulsewidths, dists) |pulsewidth, dist|
        try std.testing.expectApproxEqRel(dist, HC_SR04.pulsewidthToCm(pulsewidth), 0.01);
}
