//! Simple I2C master read/write functionality.
//! All I2C functions require pigpio to be initialized first.

const std = @import("std");
const log = std.log;
const mem = std.mem;

pub const pigpio = @import("../lib/pigpio.zig");

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
        const res = try pigpio.sendCmd(.{
            .cmd = .I2CO,
            .p1 = @intFromEnum(bus),
            .p2 = @as(u32, addr),
        }, null, null);
        self.handle = @intCast(res.cmd.u.res);
    }

    /// Deinitialize the I2C connection.
    pub fn deinit(self: *@This()) void {
        if (self.handle) |handle| {
            _ = pigpio.sendCmd(.{
                .cmd = .I2CC,
                .p1 = handle,
                .p2 = 0,
            }, null, null) catch |err| {
                log.warn("failed to close I2C handle {} ({})", .{ handle, err });
            };
        } else {
            log.warn("attempted to close nonexistant I2C handle", .{});
        }
    }

    /// Read `len` bytes from `reg`.
    /// The maximum number of bytes that can be read at one time is 32.
    pub fn read(self: *@This(), alloc: mem.Allocator, reg: u8, len: u32) ![]const u8 {
        if (len > 32)
            return error.TooManyBytes;
        const res = try pigpio.sendCmd(.{
            .cmd = .I2CRI,
            .p1 = self.handle orelse return error.BadHandle,
            .p2 = @as(u32, reg),
            .u = .{ .p3 = @sizeOf(@TypeOf(len)) }
        }, mem.asBytes(&len), alloc);
        if (res.cmd.u.ext_len != len)
            return error.CommunicationError;
        return res.ext.?;
    }

    /// Write `data` to `reg`.
    /// The maximum number of bytes that can be written at one time is 32.
    pub fn write(self: *@This(), reg: u8, data: []const u8) !void {
        if (data.len > 32)
            return error.TooManyBytes;
        _ = try pigpio.sendCmd(.{
            .cmd = .I2CWI,
            .p1 = self.handle orelse return error.BadHandle,
            .p2 = @as(u32, reg),
            .u = .{ .p3 = @intCast(data.len) }
        }, data, null);
    }
};
