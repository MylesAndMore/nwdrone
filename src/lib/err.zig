//! A generic error checking interface for C functions.
//! Can be used to return a Zig error when a C function fails.
//! This assumes that the C function returns a negative value on failure.

const std = @import("std");

const CError = error {
    FunctionFailed,
};

pub fn check(res: c_int) CError!c_int {
    if (res < 0) {
        std.log.warn("err.check() failed ({})", .{ res });
        return CError.FunctionFailed;
    }
    return res;
}
