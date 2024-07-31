//! Provides an interface to an MPU6050 accelerometer/gyroscope.
//! Based on [i2cdevlib's MPU6050 library](https://github.com/jrowberg/i2cdevlib/tree/master/RP2040/MPU6050).

const std = @import("std");
const log = std.log;
const time = std.time;

pub const i2c = @import("../hw/i2c.zig");

pub const math3d = @import("../lib/math3d.zig");

const MPUError = error {
    DeviceMismatch,
    VerificationFailed,
};

const I2C_BUS: i2c.Bus = .I2C0; // Pi i2c bus to use for MPU6050 communication

const DMP_FIRMWARE = @embedFile("../lib/dmp_firmware_6-12.bin"); // MPU6050 DMP firmware binary
const DMP_MEMORY_CHUNK_SIZE = 16; // Size of memory chunks to write to device
const DMP_PACKET_SIZE = 28; // Size of DMP FIFO packets

// MPU6050 i2c info
const I2C_ADDR = 0x68;
const DEVICE_ID = 0x68;
// MPU6050 registers
const REG_XA_OFFS = 0x06;
const REG_YA_OFFS = 0x08;
const REG_ZA_OFFS = 0x0A;
const REG_XG_OFFS = 0x13;
const REG_YG_OFFS = 0x15;
const REG_ZG_OFFS = 0x17;
const REG_SELF_TEST_X = 0x0D;
const REG_SELF_TEST_Y = 0x0E;
const REG_SELF_TEST_Z = 0x0F;
const REG_SELF_TEST_A = 0x10;
const REG_SMPLRT_DIV = 0x19;
const REG_CONFIG = 0x1A;
const REG_GYRO_CONFIG = 0x1B;
const REG_ACCEL_CONFIG = 0x1C;
const REG_FIFO_EN = 0x23;
const REG_I2C_MST_CTRL = 0x24;
const REG_I2C_SLV0_ADDR = 0x25;
const REG_I2C_SLV0_REG = 0x26;
const REG_I2C_SLV0_CTRL = 0x27;
const REG_I2C_SLV1_ADDR = 0x28;
const REG_I2C_SLV1_REG = 0x29;
const REG_I2C_SLV1_CTRL = 0x2A;
const REG_I2C_SLV2_ADDR = 0x2B;
const REG_I2C_SLV2_REG = 0x2C;
const REG_I2C_SLV2_CTRL = 0x2D;
const REG_I2C_SLV3_ADDR = 0x2E;
const REG_I2C_SLV3_REG = 0x2F;
const REG_I2C_SLV3_CTRL = 0x30;
const REG_I2C_SLV4_ADDR = 0x31;
const REG_I2C_SLV4_REG = 0x32;
const REG_I2C_SLV4_DO = 0x33;
const REG_I2C_SLV4_CTRL = 0x34;
const REG_I2C_SLV4_DI = 0x35;
const REG_I2C_MST_STATUS =0x36;
const REG_INT_PIN_CFG = 0x37;
const REG_INT_ENABLE = 0x38;
const REG_INT_STATUS = 0x3A;
const REG_ACCEL_XOUT_H = 0x3B;
const REG_ACCEL_XOUT_L = 0x3C;
const REG_ACCEL_YOUT_H = 0x3D;
const REG_ACCEL_YOUT_L = 0x3E;
const REG_ACCEL_ZOUT_H = 0x3F;
const REG_ACCEL_ZOUT_L = 0x40;
const REG_TEMP_OUT_H = 0x41;
const REG_TEMP_OUT_L = 0x42;
const REG_GYRO_XOUT_H = 0x43;
const REG_GYRO_XOUT_L = 0x44;
const REG_GYRO_YOUT_H = 0x45;
const REG_GYRO_YOUT_L = 0x46;
const REG_GYRO_ZOUT_H = 0x47;
const REG_GYRO_ZOUT_L = 0x48;
const REG_I2C_MST_DELAY_CT = 0x67;
const REG_SIGNAL_PATH_RES = 0x68;
const REG_USER_CTRL = 0x6A;
const REG_PWR_MGMT_1 = 0x6B;
const REG_PWR_MGMT_2 = 0x6C;
const REG_BANK_SEL = 0x6D;
const REG_MEM_START_ADDR = 0x6E;
const REG_MEM_R_W = 0x6F;
const REG_DMP_CFG_1 = 0x70;
const REG_DMP_CFG_2 = 0x71;
const REG_FIFO_COUNTH = 0x72;
const REG_FIFO_COUNTL = 0x73;
const REG_FIFO_R_W = 0x74;
const REG_WHO_AM_I = 0x75;

const ACCEL_OFFSETS = [3]i16{ -2104, -1097, 4942 }; // x, y, z
const GYRO_OFFSETS = [3]i16{ 25, -55, 36 }; // x, y, z

var mpu6050: i2c.Device = .{};

/// Initialize and configure the MPU6050 device.
pub fn init() !void {
    try mpu6050.init(I2C_ADDR, I2C_BUS);
    const who_am_i = try mpu6050.readByte(REG_WHO_AM_I);
    if (who_am_i != DEVICE_ID) {
        log.warn("MPU6050 device ID mismatch: expected 0x{X:2}, got 0x{X:2}", .{ DEVICE_ID, who_am_i });
        return error.DeviceMismatch;
    }
    try configure();
    try set_accel_offsets(ACCEL_OFFSETS);
    try set_gyro_offsets(GYRO_OFFSETS);
    try set_dmp_enabled(true);
    log.info("mpu6050 ready", .{});
}

/// Deinitialize the MPU6050 device.
pub fn deinit() void {
    mpu6050.deinit();
    log.info("mpu6050 deinitialized", .{});
}

/// Get the current quaternion from the device.
/// This function will return null if no packet is currently available.
pub fn get_quaternion() !?math3d.Quaternion {
    if (try get_fifo_count() < DMP_PACKET_SIZE)
        return null; // No packet available
    if (try get_fifo_count() == 1024) {
        try clear_fifo(); // Overflow
        return null;
    }

    var packet: [DMP_PACKET_SIZE]u8 = undefined;
    try get_fifo_bytes(packet[0..]);

    return math3d.Quaternion {
        .w = @as(f32, @floatFromInt((@as(i16, packet[0]) << 8) | packet[1])) / 16384.0,
        .x = @as(f32, @floatFromInt((@as(i16, packet[4]) << 8) | packet[5])) / 16384.0,
        .y = @as(f32, @floatFromInt((@as(i16, packet[8]) << 8) | packet[9])) / 16384.0,
        .z = @as(f32, @floatFromInt((@as(i16, packet[12]) << 8) | packet[13])) / 16384.0,
    };
}

/// Configure the device.
/// This sets up registers and loads the DMP firmware.
fn configure() !void {
    // write_bits(REG_PWR_MGMT_1, 2, 3, 0x01);
    try mpu6050.writeByte(REG_PWR_MGMT_1, 0x41); // Set clock source to PLL with X axis gyroscope reference
    // write_bits(REG_GYRO_CONFIG, 4, 2, 0x00);
    try mpu6050.writeByte(REG_GYRO_CONFIG, 0x00); // Set gyro FSR to 250dps
    // write_bits(REG_ACCEL_CONFIG, 4, 2, 0x00);
    try mpu6050.writeByte(REG_ACCEL_CONFIG, 0x00); // Set accel FSR to 2g
    // write_bit(REG_PWR_MGMT_1, 6, 0);
    try mpu6050.writeByte(REG_PWR_MGMT_1, 0x01); // Wake up device
    // DMP initialization process
    // write_bit(REG_PWR_MGMT_1, 7, 1);
    try mpu6050.writeByte(REG_PWR_MGMT_1, 0x81); // Reset device and wait for it to come back up
    time.sleep(time.ns_per_ms * 100);
    // write_bits(REG_USER_CTRL, 2, 3, 0b111);
	try mpu6050.writeByte(REG_USER_CTRL, 0x07); // Full SIGNAL_PATH_RESET with another 100ms delay
    time.sleep(time.ns_per_ms * 100);
    try mpu6050.writeByte(REG_PWR_MGMT_1, 0x01); // Clock source select PLL with X axis gyroscope reference
    try mpu6050.writeByte(REG_INT_ENABLE, 0x00); // Disable all interrupts
    try mpu6050.writeByte(REG_FIFO_EN, 0x00); // Disable FIFO (use DMP's FIFO instead)
    try mpu6050.writeByte(REG_ACCEL_CONFIG, 0x00); // Set accel FSR to 2G
	try mpu6050.writeByte(REG_INT_PIN_CFG, 0x80); // Set interrupt pin active low and clear on any read
    try mpu6050.writeByte(REG_PWR_MGMT_1, 0x01); // Clock source select (again?)
	try mpu6050.writeByte(REG_SMPLRT_DIV, 0x04); // Set sample rate to 200Hz ( Sample Rate = Gyroscope Output Rate / (1 + SMPLRT_DIV))
	try mpu6050.writeByte(REG_CONFIG, 0x01); // Set DLPF to 188Hz
	try write_memory_block(DMP_FIRMWARE[0..], true); // Load DMP firmware
    try mpu6050.writeWords(REG_DMP_CFG_1, &[_]u16{0x0400}); // Set DMP program start address
    try mpu6050.writeByte(REG_GYRO_CONFIG, 0x18); // Set gyro FSR to 2000dps
    try mpu6050.writeByte(REG_USER_CTRL, 0xC0); // Enable and reset FIFO
    try mpu6050.writeByte(REG_INT_ENABLE, 0x02); // Enable DMP interrupt (RAW_DMP_INT_EN)
    try mpu6050.writeBit(REG_USER_CTRL, 2, 1); // Reset FIFO again
    try set_dmp_enabled(false);
}

/// Set the currently active memory bank.
inline fn set_memory_bank(bank: u8) !void {
    try mpu6050.writeByte(REG_BANK_SEL, bank & 0x1F);
}

/// Set the memory start address for reading and writing.
inline fn set_memory_start_address(addr: u8) !void {
    try mpu6050.writeByte(REG_MEM_START_ADDR, addr);
}

/// Write a block of memory `data` to the device, optionally verifying the write.
fn write_memory_block(data: []const u8, verify: bool) !void {
    // Prepare to write memory blocks
    var bank: u8 = 0;
    var address: u8 = 0;
    try set_memory_bank(bank);
    try set_memory_start_address(address);

    var chunk_size: u8 = 0;
    var i: u16 = 0;
    while (i < data.len) {
        // Determine correct chunk size according to bank position and data size
        chunk_size = DMP_MEMORY_CHUNK_SIZE;
        // Make sure we don't go past the data size
        if (i + chunk_size > data.len)
            chunk_size = @as(u8, @intCast(data.len - i));
        // Make sure this chunk doesn't go past the bank boundary (256 bytes)
        if (chunk_size > @as(u9, 256) - address)
            chunk_size = @as(u8, @intCast(@as(u9, 256) - address));
        
        // Slice the data into chunks and write them to the device
        try mpu6050.write(REG_MEM_R_W, data[i..i + chunk_size]);
        // Verify if needed
        if (verify) {
            try set_memory_bank(bank);
            try set_memory_start_address(address);
            var verify_buf: [DMP_MEMORY_CHUNK_SIZE]u8 = undefined;
            try mpu6050.read(REG_MEM_R_W, verify_buf[0..]);
            if (!std.mem.eql(u8, verify_buf[0..chunk_size], data[i..i + chunk_size]))
                return error.VerificationFailed;
        }

        // Move to the next chunk
        i += chunk_size;
        address = address +% chunk_size;

        // If not done, update bank and address and continue
        if (i < data.len) {
            if (address == 0)
                bank += 1;
            try set_memory_bank(bank);
            try set_memory_start_address(address);
        }
    }
}

/// Set the accelerometer offsets.
fn set_accel_offsets(offsets: [3]i16) !void {
    // write_word(REG_XA_OFFS, @bitCast(offsets[0]));
    // write_word(REG_YA_OFFS, @bitCast(offsets[1]));
    // write_word(REG_ZA_OFFS, @bitCast(offsets[2]));
    try mpu6050.writeWords(REG_XA_OFFS, &[_]u16{ @bitCast(offsets[0]), @bitCast(offsets[1]), @bitCast(offsets[2]) });
}

/// Set the gyroscope offsets.
fn set_gyro_offsets(offsets: [3]i16) !void {
    // write_word(REG_XG_OFFS, @bitCast(offsets[0]));
    // write_word(REG_YG_OFFS, @bitCast(offsets[1]));
    // write_word(REG_ZG_OFFS, @bitCast(offsets[2]));
    try mpu6050.writeWords(REG_XG_OFFS, &[_]u16{ @bitCast(offsets[0]), @bitCast(offsets[1]), @bitCast(offsets[2]) });
}

/// Enable or disable the DMP.
inline fn set_dmp_enabled(enabled: bool) !void {
    try mpu6050.writeBit(REG_USER_CTRL, 7, @intFromBool(enabled));
}

/// Get the current number of bytes in the FIFO buffer.
fn get_fifo_count() !u16 {
    var count: [2]u8 = undefined;
    try mpu6050.read(REG_FIFO_COUNTH, count[0..]);
    return ((@as(u16, count[0])) << 8) | count[1];
}

/// Discard all data in the FIFO buffer.
inline fn clear_fifo() !void {
    try mpu6050.writeBit(REG_USER_CTRL, 2, 1);
}

/// Get bytes from the FIFO buffer.
/// The amount of bytes read is determined by the length of slice `dest`.
inline fn get_fifo_bytes(dest: []u8) !void {
    try mpu6050.read(REG_FIFO_R_W, dest);
}
