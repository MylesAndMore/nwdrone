//! Library for interfacing with pigpiod, the pigpio daemon.
//! Note that this library does not start pigpiod, it assumes it to already be running.
//! See https://abyz.me.uk/rpi/pigpio/sif.html for protocol information

const std = @import("std");
const log = std.log;
const mem = std.mem;
const Mutex = std.Thread.Mutex;
const posix = std.posix;
const testing = std.testing;

// Why pigpiod (daemon) and not just pigpio (C library/interface)?
// To be completely honest, I had issues cross-compiling pigpio and hadn't figured out
// how to link pre-compiled libraries in Zig yet.
// 
// The daemon works just fine and I don't feel like rewriting this now that I do know
// how to link pre-compiled libraries, so pigpiod it is!

const PigpioError = error {
    SendFailed,
    RecvFailed,
    InvalidResponse,
    CommandError,
};

// pigpio commands (found in pigpio.h, PI_CMD_*)
pub const Command = enum (u32) {
    MODES = 0,
    MODEG,
    PUD,
    READ,
    WRITE,
    PWM,
    PRS,
    PFS,
    SERVO,
    WDOG,
    BR1,
    BR2,
    BC1,
    BC2,
    BS1,
    BS2,
    TICK,
    HWVER,
    NO,
    NB,
    NP,
    NC,
    PRG,
    PFG,
    PRRG,
    HELP,
    PIGPV,
    WVCLR,
    WVAG,
    WVAS,
    WVGO,
    WVGOR,
    WVBSY,
    WVHLT,
    WVSM,
    WVSP,
    WVSC,
    TRIG,
    PROC,
    PROCD,
    PROCR,
    PROCS,
    SLRO,
    SLR,
    SLRC,
    PROCP,
    MICS,
    MILS,
    PARSE,
    WVCRE,
    WVDEL,
    WVTX,
    WVTXR,
    WVNEW,
    I2CO,
    I2CC,
    I2CRD,
    I2CWD,
    I2CWQ,
    I2CRS,
    I2CWS,
    I2CRB,
    I2CWB,
    I2CRW,
    I2CWW,
    I2CRK,
    I2CWK,
    I2CRI,
    I2CWI,
    I2CPC,
    I2CPK,
    SPIO,
    SPIC,
    SPIR,
    SPIW,
    SPIX,
    SERO,
    SERC,
    SERRB,
    SERWB,
    SERR,
    SERW,
    SERDA,
    GDC,
    GPW,
    HC,
    HP,
    CF1,
    CF2,
    BI2CC,
    BI2CO,
    BI2CZ,
    I2CZ,
    WVCHA,
    SLRI,
    CGI,
    CSI,
    FG,
    FN,
    NOIB,
    WVTXM,
    WVTAT,
    PADS,
    PADG,
    FO,
    FC,
    FR,
    FW,
    FS,
    FL,
    SHELL,
    BSPIC,
    BSPIO,
    BSPIX,
    BSCX,
    EVM,
    EVT,
    PROCU,
    WVCAP,
};

// pigpio command structure
// extern to be able to interface with pigpiod, which is written in C
pub const cmdCmd_t = extern struct {
    cmd: Command,
    p1: u32,
    p2: u32,
    u: extern union {
        p3: u32,
        ext_len: i32,
        res: i32,
    } = .{ .p3 = 0 },
};

// An extended pigpio command structure, containing a command + extension(s),
const ExtendedCmd = struct {
    cmd: cmdCmd_t,
    ext: ?[]const u8,
};

const PIGPIO_ADDR: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }; // ::1, IPV6 loopback
const PIGPIO_PORT: u16 = 8888; // pigpiod default port

var pigpiod: posix.socket_t = undefined;
var pigpiod_lock = Mutex{};

/// Initialize connection to pigpiod.
/// Should be called before any other pigpio functions.
pub fn init() !void {
    log.info("trying to connect to pigpiod on ipv6 {d}, port {}", .{PIGPIO_ADDR, PIGPIO_PORT});
    pigpiod = try posix.socket(posix.AF.INET6, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    const addr: posix.sockaddr.in6 = .{
        .addr = PIGPIO_ADDR,
        .port = mem.nativeToBig(u16, PIGPIO_PORT),
        .flowinfo = 0,
        .scope_id = 0,
    };
    try posix.connect(pigpiod, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    // Request pigpio version to check comms
    const res = try sendCmd(.{
        .cmd = .PIGPV,
        .p1 = 0,
        .p2 = 0,
    }, null, null);
    // We access p3 of the union instead of res as PIGPV returns an unsigned int
    log.info("connected to pigpiod version {}", .{res.cmd.u.p3});
}

/// Close connection to pigpiod.
/// Should be called after all pigpio functions.
pub fn deinit() void {
    log.info("closing connection to pigpiod", .{});
    posix.close(pigpiod);
}

/// Send a command to pigpiod and wait for a response.
/// If the command requires sending extensions, they should be passed in the
/// `ext` parameter.
/// If the command requires receiving extensions, an allocator must be passed
/// in the `alloc` parameter. The caller is responsible for freeing any
/// returned extensions.
/// 
/// This function is thread-safe.
pub fn sendCmd(cmd: cmdCmd_t, ext: ?[]const u8, alloc: ?mem.Allocator) !ExtendedCmd {
    pigpiod_lock.lock();
    defer pigpiod_lock.unlock();
    // Convert command to byte array and send to pigpiod
    if (try posix.send(pigpiod, mem.asBytes(&cmd), 0) != @sizeOf(cmdCmd_t))
        return error.SendFailed;
    // If the command specifies any extensions, send them as well
    if (cmd.u.ext_len > 0) {
        if (try posix.send(pigpiod, ext.?, 0) != cmd.u.ext_len)
            return error.SendFailed;
    }

    // Create a buffer for the result and receive it
    var res_raw: [@sizeOf(cmdCmd_t)]u8 = undefined;
    if (try posix.recv(pigpiod, &res_raw, posix.MSG.WAITALL) != res_raw.len)
        return error.RecvFailed;
    // Convert the response bytes back to a cmdCmd_t
    const res = mem.bytesToValue(cmdCmd_t, &res_raw);
    // Recieve any extensions
    var extensions: []u8 = undefined;
    var extensions_recvd = false;
    switch (cmd.cmd) {
        .BI2CZ, .BSCX, .BSPIX, .CF2, .FL, .FR, .I2CPK, .I2CRD,
        .I2CRI, .I2CRK, .I2CZ, .PROCP, .SERR, .SLR, .SPIX, .SPIR => {
            if (res.u.ext_len > 0) {
                extensions = try alloc.?.alloc(u8, @intCast(res.u.ext_len));
                if (try posix.recv(pigpiod, extensions, posix.MSG.WAITALL) != res.u.ext_len)
                    return error.RecvFailed;
                extensions_recvd = true;
            }
        },
        else => {},
    }

    // According to command format, cmd, p1, and p2 should match the sent command
    if (res.cmd != cmd.cmd or res.p1 != cmd.p1 or res.p2 != cmd.p2)
        return error.InvalidResponse;
    // Negative result codes are errors
    if (res.u.res < 0) {
        log.warn("pigpiod returned error code {}", .{res.u.res});
        // I didn't bother to implement all error codes, if you need to know more info, check out
        // https://github.com/joan2937/pigpio/blob/master/pigpio.h and search for your error code
        return error.CommandError;
    }
    return .{ .cmd = res, .ext = if (extensions_recvd) extensions else null };
}

test "network byte order" {
    try testing.expect(mem.nativeToBig(u16, 8888) == 47138);
}

test "Command size" {
    const size = @sizeOf(Command);
    try testing.expect(size == @sizeOf(u32));
}

test "cmdCmd_t alignment" {
    const size = @sizeOf(cmdCmd_t);
    const alignment = @alignOf(cmdCmd_t);
    // Should match the C struct size and alignment for communication with pigpiod
    try testing.expect(size == 16);
    try testing.expect(alignment == 4);
}
