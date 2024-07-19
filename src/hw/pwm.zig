//! All PWM functions require pigpio to be initialized first.

const std = @import("std");
const testing = std.testing;

const pigpio = @import("../lib/pigpio.zig");

const DUTY_RANGE = 1 << 14;

/// Initialize a pin for PWM output at a given frequency (in hz).
pub fn init(pin: u32, freq: u32) !void {
    var res = try pigpio.sendCmd(.{
        .cmd = .PFS,
        .p1 = pin,
        .p2 = freq,
    }, null);
    try pigpio.checkRes(res);
    res = try pigpio.sendCmd(.{
        .cmd = .PRS,
        .p1 = pin,
        .p2 = DUTY_RANGE,
    }, null);
    try pigpio.checkRes(res);
}

/// Set the PWM duty cycle on a pin.
/// Valid duty cycles are 0-16384.
pub fn setDuty(pin: u32, duty: u16) !void {
    std.debug.assert(duty <= DUTY_RANGE);
    const res = try pigpio.sendCmd(.{
        .cmd = .PWM,
        .p1 = pin,
        .p2 = duty,
    }, null);
    try pigpio.checkRes(res);
}

/// Set the PWM duty cycle on a pin as a percentage.
/// Valid duty cycles are 0-1.
pub inline fn setDutyF(pin: u32, duty: f32) !void {
    std.debug.assert(duty >= 0.0 and duty <= 1.0);
    try setDuty(pin, @intFromFloat(duty * DUTY_RANGE));
}

/// Set the PWM pulsewidth (in μs) on a pin.
/// Valid pulsewidths are 500-2500μs.
pub fn setPulsewidth(pin: u32, pulsewidth: u32) !void {
    const res = try pigpio.sendCmd(.{
        .cmd = .SERVO,
        .p1 = pin,
        .p2 = pulsewidth,
    }, null);
    try pigpio.checkRes(res);
}

test "float to duty conversion" {
    for ([_]u16{0, 8192, 16384}, [_]f32{0.0, 0.5, 1.0}) |actual, f| {
        const duty: u16 = @intFromFloat(f * DUTY_RANGE);
        try testing.expect(actual == duty);
    }
} 
