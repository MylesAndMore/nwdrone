//! PID controller library, inspired by pms64 and drbitboy's
//! [C library](https://github.com/drbitboy/PID).

const std = @import("std");

pub const Controller = struct {
    kp: f64, // kP gain (read-only after init)
    ki: f64, // kI gain (read-only after init)
    kd: f64, // kD gain (read-only after init)
    tau: f64, // Derivative low-pass filter time constant (read-only after init)
    lim_min: f64, // Output lower limit (read-only after init)
    lim_max: f64, // Output upper limit (read-only after init)
    out: f64 = 0.0, // Controller output (read-only)
    // -- private --
    integrator: f64 = 0.0,
    differentiator: f64 = 0.0,
    prev_error: f64 = 0.0,
    prev_measurement: f64 = 0.0,
    prev_time: i64 = 0,

    pub fn update(self: *@This(), setpoint: f64, measurement: f64) void {
        const time: f64 = @floatFromInt(std.time.timestamp() - self.prev_time); // Time
        const err = setpoint - measurement; // Error signal
        // Compute PID components
        const proportional = self.kp * err; // Proportional
        self.integrator = self.integrator + 0.5 * self.ki * time * (err + self.prev_error); // Integral
        // Derivative (band-limited differentiator)
        // Derivative on measurement, therefore minus sign in front of equation
        self.differentiator = -(2.0 * self.kd * (measurement - self.prev_measurement)
                              + (2.0 * self.tau - time) * self.differentiator)
                              / (2.0 * self.tau + time);

        // Compute output and apply limits
        self.out = proportional + self.integrator + self.differentiator;
        if (self.out > self.lim_max) {
            // Anti-wind-up for over-saturated output
            self.integrator += self.lim_max - self.out;
            self.out = self.lim_max;
        } else if (self.out < self.lim_min) {
            // Anti-wind-up for under-saturated output
            self.integrator += self.lim_min - self.out;
            self.out = self.lim_min;
        }

        // Store error, measurement, and time for later use
        self.prev_error = err;
        self.prev_measurement = measurement;
        self.prev_time = std.time.timestamp();
    }
};
