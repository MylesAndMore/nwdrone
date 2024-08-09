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
const base64 = std.base64.standard.Encoder;

pub const math = @import("../lib/math.zig");
pub const pixy = @cImport({ @cInclude("pixy.h"); });

pub const sockets = @import("../remote/sockets.zig");

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

const FRAME_WIDTH = 320;
const FRAME_HEIGHT = 200;
pub const Frame = [FRAME_WIDTH * FRAME_HEIGHT]u8;

// Chip (Pixy communication protocol) packet types
const CRP_UINT8 = @as(u8, 0x01);
const CRP_INT8 = CRP_UINT8;
const CRP_UINT16 = @as(u8, 0x02);
const CRP_INT16 = CRP_UINT16;
const CRP_END = @as(u8, 0x00);

var alloc: std.mem.Allocator = undefined;
var frame_data: sockets.SocketData = undefined; // SocketData used to send frames

/// Check the return value of a Pixy function and return the appropriate error.
fn check(res: c_int) PixyError!void {
    switch (res) {
        0 => {},
        pixy.PIXY_ERROR_USB_IO => return PixyError.UsbIo,
        pixy.PIXY_ERROR_USB_NOT_FOUND => return PixyError.UsbNotFound,
        pixy.PIXY_ERROR_USB_BUSY => return PixyError.UsbBusy,
        pixy.PIXY_ERROR_USB_NO_DEVICE => return PixyError.UsbNoDevice,
        pixy.PIXY_ERROR_INVALID_PARAMETER => return PixyError.InvalidParam,
        pixy.PIXY_ERROR_CHIRP => return PixyError.Chirp,
        pixy.PIXY_ERROR_INVALID_COMMAND => return PixyError.InvalidCommand,
        else => return PixyError.Unknown,
    }
}

/// Event dispatcher for the `frame` event.
fn frameEvent(send: sockets.SendFn) !void {
    frame_data.event = "frame";
    // Get a raw image frame from the Pixy
    var raw_frame: Frame = undefined;
    try getFrame(&raw_frame);
    // Yes, I am sending base64 encoded camera data over a websocket
    // No, you will not complain about it
    var encoded: [base64.calcSize(raw_frame.len)]u8 = undefined;
    _ = base64.encode(&encoded, &raw_frame);
    try frame_data.data.map.put(alloc, "raw", &encoded);
    try send(frame_data);
}

/// Initialize the Pixy camera.
pub fn init(allocator: std.mem.Allocator) !void {
    try check(pixy.pixy_init());
    // Retrieve firmware version to check comms
    var version_major: u16 = undefined;
    var version_minor: u16 = undefined;
    var version_build: u16 = undefined;
    try check(pixy.pixy_get_firmware_version(&version_major, &version_minor, &version_build));
    log.info("connected to Pixy version {}.{}.{}", .{ version_major, version_minor, version_build });
    try halt(); // Idle by default
    // Turn off LED by default
    // Send a few times, otherwise the LED won't stay on when commanded later
    // Why? Absolutely no idea
    for (0..5) |_|
        try setLed(0, 0, 0, 0.0);

    alloc = allocator;
    frame_data = try sockets.SocketData.init();
    try sockets.subscribe("frame", frameEvent, .Dispatch);
}

/// Deinitialize the Pixy camera.
pub fn deinit() void {
    sockets.unsubscribe("frame");
    frame_data.deinit(alloc);
    pixy.pixy_close();
    log.info("deinitialized Pixy", .{});
}

/// Halt the Pixy (stop any currently executing program).
pub fn halt() PixyError!void {
    var res: i32 = 0;
    try check(pixy.pixy_command("stop", pixy.END_OUT_ARGS, &res, pixy.END_IN_ARGS));
    if (res != 0)
        return PixyError.Chirp;
}

/// Set the RGB values of the Pixy's onboard LED.
pub fn setLed(r: u8, g: u8, b: u8, a: f32) PixyError!void {
    if (a < 0.0 or a > 1.0)
        return PixyError.InvalidParam;
    try check(pixy.pixy_led_set_RGB(r, g, b));
    try check(pixy.pixy_led_set_max_current(@intFromFloat(math.map(a, 0.0, 1.0, 0.0,  4000.0))));
}

/// Get a frame from the Pixy.
/// The Pixy must be `halt()`ed before calling this function.
pub fn getFrame(frame: *Frame) PixyError!void {
    var pixels: [*]u8 = undefined; // Pointer to frame data
    var res: i32 = 0; // Result of Chirp commands

    var fourcc: i32 = undefined; // ??
    var render_flags: i8 = undefined; // ??
    var width: u16 = undefined;
    var height: u16 = undefined;
    var num_pixels: u32 = undefined;
    try check(pixy.pixy_command("cam_getFrame",
                                CRP_INT8, @as(i8, 0x21), // M1R2
                                CRP_INT16, @as(i16, 0), // X offset
                                CRP_INT16, @as(i16, 0), // Y offset
                                CRP_INT16, @as(i16, FRAME_WIDTH), // Width
                                CRP_INT16, @as(i16, FRAME_HEIGHT), // Height
                                CRP_END,
                                &res, // Command return value
                                &fourcc, // Required?
                                &render_flags, // Required?
                                &width, // Actual returned frame width
                                &height, // Actual returned frame height
                                &num_pixels, // Actual returned number of pixels
                                &pixels, // Pointer to address of frame data
                                CRP_END));
    if (res != 0 or width != FRAME_WIDTH or height != FRAME_HEIGHT or num_pixels != frame.len)
        return PixyError.Chirp;

    // Frame data is stored by libpixyusb until another command is executed, so we should copy it out
    @memcpy(frame, pixels);
}

// More functions can be added here as needed, simply call into libpixyusb as needed.
// See http://charmedlabs.github.io/pixy/pixy_8h.html for the full API.
