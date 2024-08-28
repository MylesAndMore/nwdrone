//! PID controller library, inspired by pms64 and drbitboy's
//! [C library](https://github.com/drbitboy/PID).

const std = @import("std");
const testing = std.testing;

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
        if (self.prev_time == 0)
            self.prev_time = std.time.microTimestamp();
        const time = @as(f64, @floatFromInt(std.time.microTimestamp() - self.prev_time)) / @as(f64, std.time.us_per_s);
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
        var out = proportional + self.integrator + self.differentiator;
        if (out > self.lim_max) {
            // Anti-wind-up for over-saturated output
            if (self.ki != 0.0)
                self.integrator += self.lim_max - out;
            out = self.lim_max;
        } else if (out < self.lim_min) {
            // Anti-wind-up for under-saturated output
            if (self.ki != 0.0)
                self.integrator += self.lim_min - out;
            out = self.lim_min;
        }

        // Store output, error, measurement, and time for later use
        self.out = out;
        self.prev_error = err;
        self.prev_measurement = measurement;
        self.prev_time = std.time.microTimestamp();
    }
};

/// Update a PID controller num `times` (testing helper).
fn updateXTimes(pid: *Controller, setpoint: f64, measurement: f64, times: usize) void {
    for (0..times) |i| {
        pid.update(setpoint, measurement);
        std.time.sleep(std.time.ns_per_ms * 2);
        _ = i;
    }
}

test "kp term" {
    var pid = Controller {
        .kp = 0.1,
        .ki = 0.0,
        .kd = 0.0,
        .tau = 1.0,
        .lim_min = -1.0,
        .lim_max = 1.0,
    };
    updateXTimes(&pid, 0.0, 0.0, 50);
    try testing.expectApproxEqRel(0.0, pid.out, 0.01);
    updateXTimes(&pid, 0.0, 1.0, 50);
    try testing.expectApproxEqRel(-0.1, pid.out, 0.01);
    updateXTimes(&pid, 0.0, -1.0, 50);
    try testing.expectApproxEqRel(0.1, pid.out, 0.01);
}

test "kp term with limiting" {
    var pid = Controller {
        .kp = 0.5,
        .ki = 0.0,
        .kd = 0.0,
        .tau = 1.0,
        .lim_min = -1.0,
        .lim_max = 1.0,
    };
    updateXTimes(&pid, 0.0, 0.0, 50);
    try testing.expectApproxEqRel(0.0, pid.out, 0.01);
    updateXTimes(&pid, 0.0, 5.0, 50);
    try testing.expectApproxEqRel(-1.0, pid.out, 0.01);
    updateXTimes(&pid, 0.0, -5.0, 50);
    try testing.expectApproxEqRel(1.0, pid.out, 0.01);
}
