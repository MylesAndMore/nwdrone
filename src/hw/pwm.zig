//! Simple PWM (write) functionality.
//! This PWM is done through software, so there are no limitations on which pins can be used.
//! All PWM functions require pigpio to be initialized first.

const std = @import("std");
const testing = std.testing;

pub const pigpio = @cImport({ @cInclude("pigpio.h"); });
pub const err = @import("../lib/err.zig");

const PWMError = error {
    BadDuty,
};

const DUTY_RANGE = 1 << 14;

/// Initialize a pin for PWM output at a given frequency (in hz).
pub fn init(pin: u32, freq: u32) !void {
    _ = try err.check(pigpio.gpioSetPWMfrequency(pin, freq));
    _ = try err.check(pigpio.gpioSetPWMrange(pin, DUTY_RANGE));
    std.log.info("initialized pin {} for PWM output at {}hz", .{ pin, freq });
}

/// Set the PWM duty cycle on a pin.
/// Valid duty cycles are 0-16384.
pub fn setDuty(pin: u32, duty: u16) !void {
    if (duty > DUTY_RANGE)
        return error.BadDuty;
    _ = try err.check(pigpio.gpioPWM(pin, duty));
}

/// Set the PWM duty cycle on a pin as a percentage.
/// Valid duty cycles are 0-1.
pub fn setDutyF(pin: u32, duty: f32) !void {
    if (duty < 0.0 or duty > 1.0)
        return error.BadDuty;
    try setDuty(pin, @intFromFloat(duty * DUTY_RANGE));
}

/// Set the PWM pulsewidth (in μs) on a pin.
pub fn setPulsewidth(pin: u32, pulsewidth: f32) !void {
    const freq = try err.check(pigpio.gpioGetPWMfrequency(pin));
    const duty: f32 = pulsewidth / @as(f32, @floatFromInt(@divExact(std.time.us_per_s, freq)));
    try setDutyF(pin, duty);
}

test "float to duty conversion" {
    for ([_]u16{0, 8192, 16384}, [_]f32{0.0, 0.5, 1.0}) |actual, f| {
        const duty: u16 = @intFromFloat(f * DUTY_RANGE);
        try testing.expect(actual == duty);
    }
} 
