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
const mem = std.mem;
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

pub const Block = pixy.Block;

pub const MAX_BLOCKS = 100; // Maximum number of blocks to return at once
pub const FRAME_WIDTH = 320;
pub const FRAME_HEIGHT = 200;
pub const HALF_FRAME_WIDTH = FRAME_WIDTH / 2;
pub const HALF_FRAME_HEIGHT = FRAME_HEIGHT / 2;
pub const Frame = [FRAME_WIDTH * FRAME_HEIGHT]u8;

// Chip (Pixy communication protocol) packet types
const CRP_UINT8: u8 = 0x01;
const CRP_INT8 = CRP_UINT8;
const CRP_UINT16: u8 = 0x02;
const CRP_INT16 = CRP_UINT16;
const CRP_UINT32: u8 = 0x04;
const CRP_INT32 = CRP_UINT32;

var alloc: mem.Allocator = undefined;
var frame_data: sockets.SocketData = undefined; // SocketData used to send frames

/// Check the return value of a Pixy function and return the appropriate error.
fn check(res: c_int) PixyError!c_int {
    if (res >= 0)
        return res;
    switch (res) {
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
    // var frame: [FRAME_WIDTH * FRAME_HEIGHT * 4]u8 = undefined;
    // for (0..FRAME_HEIGHT) |y| {
    //     for (0..FRAME_WIDTH) |x| {
    //         var r: u32 = undefined;
    //         var g: u32 = undefined;
    //         var b: u32 = undefined;
    //         math.interpolateBayer(FRAME_WIDTH, x, y, &raw_frame[FRAME_WIDTH * y + x], &r, &g, &b);
    //         frame[(FRAME_WIDTH * y + x) * 3] = @truncate(r);
    //         frame[(FRAME_WIDTH * y + x) * 3 + 1] = @truncate(g);
    //         frame[(FRAME_WIDTH * y + x) * 3 + 2] = @truncate(b);
    //         frame[(FRAME_WIDTH * y + x) * 3 + 3] = 255;
    //     }
    // }
    // Yes, I am sending base64 encoded camera data over a websocket
    // No, you will not complain about it
    var encoded: [base64.calcSize(raw_frame.len)]u8 = undefined;
    _ = base64.encode(&encoded, &raw_frame);
    try frame_data.data.map.put(alloc, "raw", &encoded);
    // Get any blocks detected by the Pixy
    var buf: [MAX_BLOCKS]Block = undefined;
    const blocks = try getBlocks(&buf);
    var blocks_str = std.ArrayList(u8).init(alloc);
    defer blocks_str.deinit();
    try std.json.stringify(blocks, .{}, blocks_str.writer());
    try frame_data.data.map.put(alloc, "blocks", blocks_str.items);
    try send(frame_data);
}

/// Initialize the Pixy camera.
pub fn init(allocator: mem.Allocator) !void {
    _ = try check(pixy.pixy_init());
    // Retrieve firmware version to check comms
    var version_major: u16 = undefined;
    var version_minor: u16 = undefined;
    var version_build: u16 = undefined;
    var uid: u32 = undefined;
    _ = try check(pixy.pixy_get_firmware_version(&version_major, &version_minor, &version_build));
    uid = @bitCast(pixy.pixy_command("getUID", pixy.END_OUT_ARGS, pixy.END_IN_ARGS));
    log.info("connected to Pixy version {}.{}.{}, UID {}", .{ version_major, version_minor, version_build, uid });
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

/// Run a specified program with an argument.
pub fn run(prog: u8, arg: u32) !void {
    var res: i32 = 0;
    _ = try check(pixy.pixy_command("runprogArg", CRP_UINT8, prog, CRP_UINT32, arg, pixy.END_OUT_ARGS, &res, pixy.END_IN_ARGS));
    if (res != 0)
        return PixyError.Chirp;
}

/// Halt the Pixy (stop any currently executing program).
pub fn halt() PixyError!void {
    var res: i32 = 0;
    _ = try check(pixy.pixy_command("stop", pixy.END_OUT_ARGS, &res, pixy.END_IN_ARGS));
    if (res != 0)
        return PixyError.Chirp;
}

/// Set the RGB values of the Pixy's onboard LED.
pub fn setLed(r: u8, g: u8, b: u8, a: f32) PixyError!void {
    if (a < 0.0 or a > 1.0)
        return PixyError.InvalidParam;
    _ = try check(pixy.pixy_led_set_RGB(r, g, b));
    _ = try check(pixy.pixy_led_set_max_current(@intFromFloat(math.map(a, 0.0, 1.0, 0.0, 4000.0))));
}

/// Get any blocks currently detected by the Pixy.
/// The Pixy must be running a program for blocks to be generated.
/// 
/// See [the documentation](https://docs.pixycam.com/wiki/doku.php?id=wiki:v1:teach_pixy_an_object_2)
/// for how to create a block.
pub fn getBlocks(blocks: *[MAX_BLOCKS]Block) PixyError![]Block {
    const num_blocks = try check(pixy.pixy_get_blocks(MAX_BLOCKS, blocks));
    return blocks[0..@intCast(num_blocks)];
}

/// Get a frame from the Pixy.
pub fn getFrame(frame: *Frame) PixyError!void {
    var pixels: [*]u8 = undefined; // Pointer to frame data
    var res: i32 = 0; // Result of Chirp commands

    var fourcc: i32 = undefined; // ??
    var render_flags: i8 = undefined; // ??
    var width: u16 = undefined;
    var height: u16 = undefined;
    var num_pixels: u32 = undefined;
    _ = try check(pixy.pixy_command("cam_getFrame",
                                CRP_INT8, @as(i8, 0x21), // M1R2
                                CRP_INT16, @as(i16, 0), // X offset
                                CRP_INT16, @as(i16, 0), // Y offset
                                CRP_INT16, @as(i16, FRAME_WIDTH), // Width
                                CRP_INT16, @as(i16, FRAME_HEIGHT), // Height
                                pixy.END_OUT_ARGS,
                                &res, // Command return value
                                &fourcc, // Required?
                                &render_flags, // Required?
                                &width, // Actual returned frame width
                                &height, // Actual returned frame height
                                &num_pixels, // Actual returned number of pixels
                                &pixels, // Pointer to address of frame data
                                pixy.END_IN_ARGS));
    if (res != 0 or width != FRAME_WIDTH or height != FRAME_HEIGHT or num_pixels != frame.len)
        return PixyError.Chirp;

    // Frame data is stored by libpixyusb until another command is executed, so we should copy it out
    @memcpy(frame, pixels);
}

// More functions can be added here as needed, simply call into libpixyusb as needed.
// See http://charmedlabs.github.io/pixy/pixy_8h.html for the full API.
