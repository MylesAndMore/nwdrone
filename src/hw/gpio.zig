//! Simple GPIO binary read/write functionality.
//! All GPIO functions require pigpio to be initialized first.

const std = @import("std");
const log = std.log.scoped(.gpio);

pub const pigpio = @cImport({ @cInclude("pigpio.h"); });
pub const err = @import("../lib/err.zig");

pub const Mode = enum {
    Input,
    Output,
    InputPullUp,
    InputPullDown,
};

pub const State = enum {
    Low,
    High,
};

/// Initialize a GPIO pin with the specified mode.
pub fn init(pin: u32, mode: Mode) !void {
    _ = try err.check(pigpio.gpioSetMode(pin, switch (mode) {
        .Input, .InputPullUp, .InputPullDown => pigpio.PI_INPUT,
        .Output => pigpio.PI_OUTPUT,
    }));
    _ = try err.check(pigpio.gpioSetPullUpDown(pin, switch (mode) {
        .InputPullUp => pigpio.PI_PUD_UP,
        .InputPullDown => pigpio.PI_PUD_DOWN,
        else => pigpio.PI_PUD_OFF,
    }));
    log.info("initialized GPIO pin {} as {}", .{ pin, mode });
}

/// Get the state of a GPIO pin.
pub fn get(pin: u32) !State {
    const res = try err.check(pigpio.gpioRead(pin));
    return switch (res) {
        0 => .Low,
        1 => .High,
        else => unreachable,
    };   
}

/// Set the state of a GPIO pin.
pub fn set(pin: u32, state: State) !void {
    _ = try err.check(pigpio.gpioWrite(pin, switch (state) {
        .Low => 0,
        .High => 1,
    }));
}

/// Toggle the state of a GPIO pin.
pub fn toggle(pin: u32) !void {
    try set(pin, switch (try get(pin)) {
        .Low => .High,
        .High => .Low,
    });
}
