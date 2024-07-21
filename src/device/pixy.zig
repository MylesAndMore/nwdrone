//! Pixy camera driver, mostly a thin Zig wrapper around the libpixyusb C API.

const std = @import("std");
const log = std.log;

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
    var version_major: c_ushort = undefined;
    var version_minor: c_ushort = undefined;
    var version_build: c_ushort = undefined;
    try check(pixy.pixy_get_firmware_version(&version_major, &version_minor, &version_build));
    log.info("connected to Pixy version {}.{}.{}", .{ version_major, version_minor, version_build });
}

/// Deinitialize the Pixy camera.
pub fn deinit() void {
    pixy.pixy_close();
}

/// Set the RGB value of the Pixy's omboard LED.
pub fn setLed(r: u8, g: u8, b: u8) PixyError!void {
    try check(pixy.pixy_led_set_RGB(r, g, b));
}

// More functions can be added here as needed, simply call into libpixyusb as needed.
// See lib/pixyusb/include/pixy.h for the full API.
