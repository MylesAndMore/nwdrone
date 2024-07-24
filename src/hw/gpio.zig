//! Simple GPIO binary read/write functionality.
//! All GPIO functions require pigpio to be initialized first.

const std = @import("std");

pub const pigpio = @import("../lib/pigpio.zig");

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
    _ = try pigpio.sendCmd(.{
        .cmd = .MODES,
        .p1 = pin,
        .p2 = switch (mode) {
            .Input, .InputPullUp, .InputPullDown => 0,
            .Output => 1,
        },
    }, null, null);
    _ = try pigpio.sendCmd(.{
        .cmd = .PUD,
        .p1 = pin,
        .p2 = switch (mode) {
            .InputPullUp => 2,
            .InputPullDown => 1,
            else => 0,
        },
    }, null, null);
    std.log.info("initialized GPIO pin {} as {}", .{ pin, mode });
}

/// Get the state of a GPIO pin.
pub fn get(pin: u32) !State {
    const res = try pigpio.sendCmd(.{
        .cmd = .READ,
        .p1 = pin,
        .p2 = 0,
    }, null, null);
    return switch (res.cmd.u.res) {
        0 => .Low,
        1 => .High,
        else => unreachable,
    };   
}

/// Set the state of a GPIO pin.
pub fn set(pin: u32, state: State) !void {
    _ = try pigpio.sendCmd(.{
        .cmd = .WRITE,
        .p1 = pin,
        .p2 = switch (state) {
            .Low => 0,
            .High => 1,
        },
    }, null, null);
}

/// Toggle the state of a GPIO pin.
pub inline fn toggle(pin: u32) !void {
    try set(pin, switch (try get(pin)) {
        .Low => .High,
        .High => .Low,
    });
}
