const std = @import("std");

const gpio = @import("hw/gpio.zig");

const pigpio = @import("lib/pigpio.zig");

pub fn main() !void {
    try pigpio.init();
    defer pigpio.deinit();

    const leds = [_]u32{2, 3, 4, 47};
    for (leds) |led| {
        try gpio.init(led, .Output);
        try gpio.set(led, .Low);
    }
    while (true) {
        for (leds) |led|
            try gpio.toggle(led);
        std.time.sleep(std.time.ns_per_s * 1);
    }
}
