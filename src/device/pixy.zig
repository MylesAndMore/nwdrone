//! Pixy camera driver, mostly a thin Zig wrapper around the
//! [libpixyusb C API](http://charmedlabs.github.io/pixy/pixy_8h.html).

// This file is part of Pixy CMUcam5 or "Pixy" for short
//
// All Pixy source code is provided under the terms of the
// GNU General Public License v2 (http://www.gnu.org/licenses/gpl-2.0.html).
// Those wishing to use Pixy source code, software and/or
// technologies under different licensing terms should contact us at
// cmucam@cs.cmu.edu. Such licensing terms are available for
// all portions of the Pixy codebase presented here.

const std = @import("std");
const log = std.log.scoped(.pixy);

const pixy = @cImport({
    @cInclude("pixy.h");
});

const PixyError = error {
    UsbIo,
    UsbNotFound,
    UsbBusy,
    UsbNoDevice,
    InvalidParam,
    Chirp,
    InvalidCommand,
    Unknown,
};

/// Check the return value of a Pixy function and return the appropriate error.
fn check(res: c_int) PixyError!void {
    switch (res) {
        0 => {},
        pixy.PIXY_ERROR_USB_IO => return error.UsbIo,
        pixy.PIXY_ERROR_USB_NOT_FOUND => return error.UsbNotFound,
        pixy.PIXY_ERROR_USB_BUSY => return error.UsbBusy,
        pixy.PIXY_ERROR_USB_NO_DEVICE => return error.UsbNoDevice,
        pixy.PIXY_ERROR_INVALID_PARAMETER => return error.InvalidParam,
        pixy.PIXY_ERROR_CHIRP => return error.Chirp,
        pixy.PIXY_ERROR_INVALID_COMMAND => return error.InvalidCommand,
        else => return error.Unknown,
    }
}

/// Initialize the Pixy camera.
pub fn init() PixyError!void {
    try check(pixy.pixy_init());
    // Retrieve firmware version to check comms
    var version_major: u16 = undefined;
    var version_minor: u16 = undefined;
    var version_build: u16 = undefined;
    try check(pixy.pixy_get_firmware_version(&version_major, &version_minor, &version_build));
    log.info("connected to Pixy version {}.{}.{}", .{ version_major, version_minor, version_build });
}

/// Deinitialize the Pixy camera.
pub fn deinit() void {
    pixy.pixy_close();
    log.info("deinitialized Pixy", .{});
}

/// Set the RGB value of the Pixy's omboard LED.
pub fn setLed(r: u8, g: u8, b: u8) PixyError!void {
    try check(pixy.pixy_led_set_RGB(r, g, b));
}

// More functions can be added here as needed, simply call into libpixyusb as needed.
// See http://charmedlabs.github.io/pixy/pixy_8h.html for the full API.
