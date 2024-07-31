//! 3D math utilities.

const std = @import("std");
const math = std.math;
const time = std.time;

pub const Vec3 = @Vector(3, f32);

pub const Quaternion = struct {
    w: f32 = 1.0,
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    /// Return the current quaternion as its Euler angle representation.
    /// The returned angles are in degrees.
    /// The order of the angles is roll, pitch, yaw.
    /// It does not matter if the quaternion is normalized.
    pub fn to_euler(self: *const @This()) Vec3 {
        // http://www.euclideanspace.com/maths/geometry/rotations/conversions/quaternionToEuler/
        const sqw = self.w*self.w;
        const sqx = self.x*self.x;
        const sqy = self.y*self.y;
        const sqz = self.z*self.z;

        const unit = sqx + sqy + sqz + sqw; // If normalized = one, otherwise = correction factor
        const cond = self.x*self.y + self.z*self.w;

        var roll: f32 = 0.0;
        var pitch: f32 = 0.0;
        var yaw: f32 = 0.0;
        if (cond > 0.499*unit) { // singularity at north pole
            roll = 2 * math.atan2(self.x,self.w);
            yaw = math.pi/2.0;
            pitch = 0;
        } else if (cond < -0.499*unit) { // singularity at south pole
            roll = -2 * math.atan2(self.x,self.w);
            yaw = -math.pi/2.0;
            pitch = 0;
        } else {
            roll = math.atan2(2*self.y*self.w-2*self.x*self.z , sqx - sqy - sqz + sqw);
            yaw = math.asin(2*cond/unit);
            pitch = math.atan2(2*self.x*self.w-2*self.y*self.z , -sqx + sqy - sqz + sqw);
        }

        return (Vec3{ roll, pitch, yaw } * @as(Vec3, @splat(180.0 / math.pi))); // Convert to degrees
    }

    /// Normalize the quaternion.
    pub fn normalize(self: *@This()) void {
        const norm = 1 / @sqrt(self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z);
        self.w *= norm;
        self.x *= norm;
        self.y *= norm;
        self.z *= norm;
    }
};

// Implementation of Madgwick's IMU and AHRS algorithms.
// See: http://www.x-io.co.uk/open-source-imu-and-ahrs-algorithms/
//
// From the x-io website "Open-source resources available on this website are
// provided under the GNU General Public Licence unless an alternative licence
// is provided in source."
pub const Madgwick = struct {
    q: Quaternion = .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 }, // Quaternion (read-only)
    beta: f32 = 0.1, // Filter gain (read-only after init)
    freq: f32 = 100.0, // Sample frequency (read-only after init)
    // -- private --
    inv_freq: f32 = 0.0, // Inverse sample frequency
    prev_update: i64 = 0, // Time of the previous call to update()

    /// Initialize the filter.
    /// Must be called before calling update().
    pub fn init(self: *@This()) void {
        self.inv_freq = 1.0 / self.freq;
    }

    /// Update the filter with new sensor data.
    pub fn update(self: *@This(), accel: Vec3, gyro: Vec3) void {
        if (time.milliTimestamp() - self.prev_update < @as(i64, @intFromFloat(self.inv_freq)) * time.ms_per_s)
            return;
        var recipNorm: f32 = 0.0;
        var s0: f32, var s1: f32, var s2: f32, var s3: f32 = .{ 0.0, 0.0, 0.0, 0.0 };
        var qDot1: f32, var qDot2: f32, var qDot3: f32, var qDot4: f32 = .{ 0.0, 0.0, 0.0, 0.0 };
        var _2q0: f32, var _2q1: f32, var _2q2: f32, var _2q3: f32 = .{ 0.0, 0.0, 0.0, 0.0 };
        var _4q0: f32, var _4q1: f32, var _4q2: f32 = .{ 0.0, 0.0, 0.0 };
        var _8q1: f32, var _8q2: f32 = .{ 0.0, 0.0 };
        var q0q0: f32, var q1q1: f32, var q2q2: f32, var q3q3: f32 = .{ 0.0, 0.0, 0.0, 0.0 };

        // Rate of change of quaternion from gyroscope
        qDot1 = 0.5 * (-self.q.x * gyro[0] - self.q.y * gyro[1] - self.q.z * gyro[2]);
        qDot2 = 0.5 * (self.q.w * gyro[0] + self.q.y * gyro[2] - self.q.z * gyro[1]);
        qDot3 = 0.5 * (self.q.w * gyro[1] - self.q.x * gyro[2] + self.q.z * gyro[0]);
        qDot4 = 0.5 * (self.q.w * gyro[2] + self.q.x * gyro[1] - self.q.y * gyro[0]);

        // Compute feedback only if accelerometer measurement valid (avoids NaN in accelerometer normalisation)
        if (!((accel[0] == 0.0) and (accel[1] == 0.0) and (accel[2] == 0.0))) {
            // Normalise accelerometer measurement
            recipNorm = 1 / @sqrt(accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]);
            var acc_norm = accel;
            acc_norm[0] *= recipNorm;
            acc_norm[1] *= recipNorm;
            acc_norm[2] *= recipNorm;

            // Auxiliary variables to avoid repeated arithmetic
            _2q0 = 2.0 * self.q.w;
            _2q1 = 2.0 * self.q.x;
            _2q2 = 2.0 * self.q.y;
            _2q3 = 2.0 * self.q.z;
            _4q0 = 4.0 * self.q.w;
            _4q1 = 4.0 * self.q.x;
            _4q2 = 4.0 * self.q.y;
            _8q1 = 8.0 * self.q.x;
            _8q2 = 8.0 * self.q.y;
            q0q0 = self.q.w * self.q.w;
            q1q1 = self.q.x * self.q.x;
            q2q2 = self.q.y * self.q.y;
            q3q3 = self.q.z * self.q.z;

            // Gradient decent algorithm corrective step
            s0 = _4q0 * q2q2 + _2q2 * acc_norm[0] + _4q0 * q1q1 - _2q1 * acc_norm[1];
            s1 = _4q1 * q3q3 - _2q3 * acc_norm[0] + 4.0 * q0q0 * self.q.x - _2q0 * acc_norm[1] - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * acc_norm[2];
            s2 = 4.0 * q0q0 * self.q.y + _2q0 * acc_norm[0] + _4q2 * q3q3 - _2q3 * acc_norm[1] - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * acc_norm[2];
            s3 = 4.0 * q1q1 * self.q.z - _2q1 * acc_norm[0] + 4.0 * q2q2 * self.q.z - _2q2 * acc_norm[1];
            recipNorm = 1 / @sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3); // normalise step magnitude
            s0 *= recipNorm;
            s1 *= recipNorm;
            s2 *= recipNorm;
            s3 *= recipNorm;

            // Apply feedback step
            qDot1 -= self.beta * s0;
            qDot2 -= self.beta * s1;
            qDot3 -= self.beta * s2;
            qDot4 -= self.beta * s3;
        }

        // Integrate rate of change of quaternion to yield quaternion
        self.q.w += qDot1 * self.inv_freq;
        self.q.x += qDot2 * self.inv_freq;
        self.q.y += qDot3 * self.inv_freq;
        self.q.z += qDot4 * self.inv_freq;

        // Normalise quaternion
        self.q.normalize();
    }
};

test "quaternion to euler" {
    const quaternions = [_]Quaternion {
        .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .w = 0.7071068, .x = 0.0, .y = 0.0, .z = 0.7071068 },
        .{ .w = 0.7071068, .x = 0.0, .y = 0.7071068, .z = 0.0 },
        .{ .w = 0.7071068, .x = 0.7071068, .y = 0.0, .z = 0.0 },
    };
    const eulers = [_]Vec3 {
        .{ 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 90.0 },
        .{ 90.0, 0.0, 0.0 },
        .{ 0.0, 90.0, 0.0 },
    };
    for (quaternions, eulers) |quaternion, euler| {
        const q_euler = quaternion.to_euler();
        for (0..2) |i|
            try std.testing.expectApproxEqAbs(euler[i], q_euler[i], 0.01);
    }
}
