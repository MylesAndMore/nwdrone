//! Import any files containing tests here.
//! Avoid importing files that contain C interop or external libraries,
//! as they can interfere with the test runner.

comptime {
    _ = @import("hw/i2c.zig");
    _ = @import("hw/pwm.zig");
    _ = @import("lib/math3d.zig");
    _ = @import("lib/pid.zig");
}
