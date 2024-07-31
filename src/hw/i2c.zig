//! Simple I2C master read/write functionality.
//! All I2C functions require pigpio to be initialized first.

const std = @import("std");
const log = std.log;
const testing = std.testing;

pub const pigpio = @cImport({ @cInclude("pigpio.h"); });
pub const err = @import("../lib/err.zig");

const I2CError = error {
    BadHandle,
    TooManyBytes,
    CommunicationError,
};

pub const Bus = enum (u1) {
    I2C0 = 0, // I2C0 is disabled by default and must be enabled in /boot/firmware/config.txt
    I2C1,
};

// A single instance of an I2C device.
pub const Device = struct {
    // -- private --
    handle: ?u32 = null, // Handle to access this I2C device through pigpio
    
    /// Initialize an I2C connection on the specified bus to the specified address.
    /// The Pi has 2 I2C buses, I2C0 and I2C1 (see pins [here](https://pinout.xyz/)).
    /// The address is a typical 7-bit I2C address (0x00-0x7F).
    /// 
    /// Frequency must be configured in the kernel (/boot/firmware/config.txt), see
    /// [this gist](https://gist.github.com/ribasco/c22ab6b791e681800df47dd0a46c7c3a)
    /// for more info: 
    pub fn init(self: *@This(), addr: u7, bus: Bus) !void {
        const res = try err.check(pigpio.i2cOpen(@intFromEnum(bus), @as(u32, addr), 0));
        self.handle = @intCast(res);
        log.info("initialized i2c device at {} with address 0x{X:0>2} (handle {})", .{ bus, addr, self.handle.? });
    }

    /// Deinitialize the I2C connection.
    pub fn deinit(self: *@This()) void {
        if (self.handle) |handle| {
            err.check(pigpio.i2cClose(handle)) catch |e| {
                log.warn("failed to close i2c handle {} ({})", .{ handle, e });
            };
            log.info("closed i2c handle {}", .{ handle });
            self.handle = null;
        } else {
            log.warn("attempted to close nonexistant i2c handle", .{});
        }
    }

    /// Read bytes from `reg` into `dest`.
    /// The amount of bytes read is determined by the length of slice `dest`.
    /// The maximum number of bytes that can be read at one time is 32.
    pub fn read(self: *const @This(), reg: u8, dest: []u8) !void {
        if (dest.len > 32)
            return error.TooManyBytes;
        const res = try err.check(pigpio.i2cReadI2CBlockData(self.handle orelse return error.BadHandle, @as(u32, reg), dest.ptr, dest.len));
        if (res != dest.len)
            return error.CommunicationError;
    }

    /// Read `len` bytes from `reg` into a newly allocated slice.
    /// The maximum number of bytes that can be read at one time is 32.
    pub fn readAlloc(self: *const @This(), alloc: std.mem.Allocator, reg: u8, len: u32) ![]u8 {
        const dest = try alloc.alloc(u8, len);
        try self.read(reg, &dest, len);
        return dest;
    }

    /// Read a single byte from `reg`.
    pub inline fn readByte(self: *const @This(), reg: u8) !u8 {
        var dest: [1]u8 = undefined;
        try self.read(reg, dest[0..]);
        return dest[0];
    }

    /// Write `data` to `reg`.
    /// The maximum number of bytes that can be written at one time is 32.
    pub fn write(self: *const @This(), reg: u8, data: []const u8) !void {
        if (data.len > 32)
            return error.TooManyBytes;
        _ = try err.check(pigpio.i2cWriteI2CBlockData(self.handle orelse return error.BadHandle, @as(u32, reg), @constCast(data.ptr), data.len));
    }

    /// Write a single byte to `reg`.
    pub inline fn writeByte(self: *const @This(), reg: u8, data: u8) !void {
        try self.write(reg, &[_]u8{ data });
    }

    /// Write a single bit at offset `bit` in `reg` to `data`.
    pub fn writeBit(self: *const @This(), reg: u8, bit: u3, data: u1) !void {
        var b = try self.readByte(reg);
        b = if (data != 0) (b | (@as(u8, 1) << bit)) else (b & ~(@as(u8, 1) << bit));
        try self.write(reg, &[_]u8{ b });
    }

    /// Write `data` to `reg` as a series of 16-bit words.
    pub fn writeWords(self: *const @This(), reg: u8, data: []const u16) !void {
        if (data.len > 16)
            return error.TooManyBytes;
        var buf: [32]u8 = undefined;
        for (data, 0..) |word, i| {
            buf[i * 2] = @truncate(word >> 8);
            buf[i * 2 + 1] = @truncate(word);
        }
        try self.write(reg, buf[0..data.len * 2]);
    }
};

test "write_bit bitwise" {
    const bit: u3 = 3;
    const data: u1 = 1;

    var b: u8 = 0xC0;
    b = if (data != 0) (b | (@as(u8, 1) << bit)) else (b & ~(@as(u8, 1) << bit));

    try testing.expect(b == 0xC8);
}

test "write_words interleaved" {
    const words = [_]u16{ 0x1234, 0x5678, 0x9ABC, 0xDEF0 };
    const bytes = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0 };
    var buf: [32]u8 = undefined;
    for (words, 0..) |word, i| {
        buf[i * 2] = @truncate(word >> 8);
        buf[i * 2 + 1] = @truncate(word);
    }

    try testing.expectEqualSlices(u8, buf[0..8], bytes[0..]);
}
