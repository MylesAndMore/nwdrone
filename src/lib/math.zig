//! Math utilities.

/// Map a value `x` from range `in_min` to `in_max` to range `out_min` to `out_max`.
/// All inputs must be of the same type.
pub fn map(x: anytype, in_min: anytype, in_max: anytype, out_min: anytype, out_max: anytype) @TypeOf(x, in_min, in_max, out_min, out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}
