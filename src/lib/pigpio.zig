const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const testing = std.testing;

// See https://abyz.me.uk/rpi/pigpio/sif.html for protocol information

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
        ext_len: u32,
        res: i32,
    } = .{ .p3 = 0 },
};

// An extended pigpio command structure, containing a command, extension(s),
// and an allocator (used to allocate/free extensions).
const ExtendedCmd = struct {
    cmd: cmdCmd_t,
    ext: *?[]u8,
    alloc: mem.Allocator,
};

const PIGPIO_ADDR: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }; // ::1, IPV6 loopback
const PIGPIO_PORT: u16 = 8888; // pigpiod default port

var pigpiod: posix.socket_t = undefined;
var allocator: mem.Allocator = undefined;

/// Initialize connection to pigpiod.
/// Should be called before any other pigpio functions.
pub fn init() !void {
    pigpiod = try posix.socket(posix.AF.INET6, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    const addr: posix.sockaddr.in6 = .{
        .addr = PIGPIO_ADDR,
        .port = mem.nativeToBig(u16, PIGPIO_PORT),
        .flowinfo = 0,
        .scope_id = 0,
    };
    try posix.connect(pigpiod, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    // Also initialize a gpa for extensions
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();
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
pub fn sendCmd(cmd: cmdCmd_t, ext: ?[]const u8) !ExtendedCmd {
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
    var extensions: ?[]u8 = null;
    switch (cmd.cmd) {
        .BI2CZ, .BSCX, .BSPIX, .CF2, .FL, .FR, .I2CPK, .I2CRD,
        .I2CRI, .I2CRK, .I2CZ, .PROCP, .SERR, .SLR, .SPIX, .SPIR => {
            if (res.u.ext_len > 0) {
                extensions = try allocator.alloc(u8, res.u.ext_len);
                if (try posix.recv(pigpiod, extensions.?, posix.MSG.WAITALL) != res.u.ext_len)
                    return error.RecvFailed;
            }
        },
        else => {},
    }

    // According to command format, cmd, p1, and p2 should match the sent command
    if (res.cmd != cmd.cmd or res.p1 != cmd.p1 or res.p2 != cmd.p2)
        return error.InvalidResponse;
    return .{ .cmd = res, .ext = &extensions, .alloc = allocator };
}

/// Checks the response of a command and returns an error where appropriate.
pub inline fn checkRes(res: ExtendedCmd) !void {
    if (res.cmd.u.res < 0)
        return error.CommandError;
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
