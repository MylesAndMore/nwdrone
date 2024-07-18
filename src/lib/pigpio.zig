const std = @import("std");
const posix = std.posix;
const testing = std.testing;

// See https://abyz.me.uk/rpi/pigpio/sif.html for protocol information

const PigpioError = error {
    SendFailed,
    RecvFailed,
    InvalidResponse,
    CommandError,
};

// pigpio command structure
// extern to be able to interface with pigpiod, which is written in C
pub const cmdCmd_t = extern struct {
    cmd: u32,
    p1: u32,
    p2: u32,
    u: extern union {
        p3: u32,
        ext_len: u32,
        res: u32,
    } = .{ .p3 = 0 },
};

const PIGPIO_ADDR: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }; // ::1, IPV6 loopback
const PIGPIO_PORT: u16 = 8888; // pigpiod default port

var pigpiod: posix.socket_t = undefined;

/// Initialize connection to pigpiod.
/// Should be called before any other pigpio functions.
pub fn init() !void {
    pigpiod = try posix.socket(posix.AF.INET6, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    const addr: posix.sockaddr.in6 = .{
        .addr = PIGPIO_ADDR,
        .port = std.mem.nativeToBig(u16, PIGPIO_PORT),
        .flowinfo = 0,
        .scope_id = 0
    };
    try posix.connect(pigpiod, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
}

/// Close connection to pigpiod.
/// Should be called after all pigpio functions.
pub fn deinit() void {
    posix.close(pigpiod);
}

/// Send a command to pigpiod and wait for a response.
/// This function also performs some basic error checking, but more detailed
/// error checking should be done by the caller (using checkRes, for example)
/// where appropriate, such as commands that return a status rather than a
/// response.
pub fn sendCmd(cmd: cmdCmd_t, ext: ?[]const u8) !cmdCmd_t {
    // Convert command to byte array and send to pigpiod
    if (try posix.send(pigpiod, std.mem.asBytes(&cmd), 0) != @sizeOf(cmdCmd_t))
        return error.SendFailed;
    // If the command specifies any extensions, send them as well
    if (cmd.u.ext_len > 0) {
        if (try posix.send(pigpiod, ext.?, 0) != cmd.u.ext_len)
            return error.SendFailed;
    }

    // Create a buffer and receive the response
    var res_raw: [@sizeOf(cmdCmd_t)]u8 = undefined;
    if (try posix.recv(pigpiod, &res_raw, posix.MSG.WAITALL) != res_raw.len)
        return error.RecvFailed;
    // TODO: should be able to handle receiving extensions
    // Convert the response bytes back to a cmdCmd_t
    var res: cmdCmd_t = undefined;
    // FIXME: this is very unsafe but the only way I could get it to work, fix if time?
    _ = std.zig.c_builtins.__builtin_memcpy(&res, &res_raw, res_raw.len);

    // According to command format, cmd, p1, and p2 should match the sent command
    if (res.cmd != cmd.cmd or res.p1 != cmd.p1 or res.p2 != cmd.p2)
        return error.InvalidResponse;
    return res;
}

/// Checks the response of a command and returns an error where appropriate.
pub fn checkRes(res: cmdCmd_t) !void {
    if (res.u.res < 0)
        return error.CommandError;
}

test "network byte order" {
    try testing.expect(std.mem.nativeToBig(u16, 8888) == 47138);
}

test "cmdCmd_t alignment" {
    const size = @sizeOf(cmdCmd_t);
    const alignment = @alignOf(cmdCmd_t);
    // Should match the C struct size and alignment for communication with pigpiod
    try testing.expect(size == 16);
    try testing.expect(alignment == 4);
}
