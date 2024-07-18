const pigpio = @import("../lib/pigpio.zig");

pub const PinMode = enum {
    Input,
    Output,
    InputPullUp,
    InputPullDown,
};

pub const PinState = enum {
    Low,
    High,
};

// All GPIO functions require pigpio to be initialized first.

/// Initialize a GPIO pin with the specified mode.
pub fn init(pin: u32, mode: PinMode) !void {
    // Initialize pin
    var res = try pigpio.sendCmd(.{
        .cmd = 0, // MODES
        .p1 = pin,
        .p2 = switch (mode) {
            .Output => 1,
            else => 0,
        },
    }, null);
    try pigpio.checkRes(res);
    // Set pulls as needed
    res = try pigpio.sendCmd(.{
        .cmd = 2, // PUD
        .p1 = pin,
        .p2 = switch (mode) {
            .InputPullUp => 2,
            .InputPullDown => 1,
            else => 0,
        },
    }, null);
    try pigpio.checkRes(res);
}

/// Get the state of a GPIO pin.
pub fn get(pin: u32) !PinState {
    const res = try pigpio.sendCmd(.{
        .cmd = 3, // READ
        .p1 = pin,
        .p2 = 0,
    }, null);
    return switch (res.u.res) {
        0 => PinState.Low,
        1 => PinState.High,
        else => unreachable,
    };   
}

/// Set the state of a GPIO pin.
pub fn set(pin: u32, state: PinState) !void {
    const res = try pigpio.sendCmd(.{
        .cmd = 4, // WRITE
        .p1 = pin,
        .p2 = switch (state) {
            .Low => 0,
            .High => 1,
        },
    }, null);
    try pigpio.checkRes(res);
}

/// Toggle the state of a GPIO pin.
pub inline fn toggle(pin: u32) !void {
    try set(pin, switch (try get(pin)) {
        .Low => .High,
        .High => .Low,
    });
}
