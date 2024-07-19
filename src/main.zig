const std = @import("std");

const pigpio = @import("lib/pigpio.zig");

pub fn main() !void {
    try pigpio.init();
    defer pigpio.deinit();
}
