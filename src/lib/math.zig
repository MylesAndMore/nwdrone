//! Math utilities.

/// Map a value `x` from range `in_min` to `in_max` to range `out_min` to `out_max`.
/// All inputs must be of the same type.
pub fn map(x: anytype, in_min: anytype, in_max: anytype, out_min: anytype, out_max: anytype) @TypeOf(x, in_min, in_max, out_min, out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

/// Interpolate a pixel in a Bayer pattern.
pub fn interpolateBayer(width: u32, x: u32, y: u32, pixel: [*c]u8, r: [*c]u32, g: [*c]u32, b: [*c]u32) void {
    if ((y & @as(u32, @bitCast(@as(i32, 1)))) != 0) {
        if ((x & @as(u32, @bitCast(@as(i32, 1)))) != 0) {
            r.* = @as(u32, @bitCast(@as(u32, pixel.*)));
            g.* = @as(u32, @bitCast((((@as(i32, @bitCast(@as(u32, (pixel - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*))) + @as(i32, @bitCast(@as(u32, (pixel + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) + @as(i32, @bitCast(@as(u32, (pixel + width).*)))) + @as(i32, @bitCast(@as(u32, (pixel - width).*)))) >> @intCast(2)));
            b.* = @as(u32, @bitCast((((@as(i32, @bitCast(@as(u32, ((pixel - width) - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*))) + @as(i32, @bitCast(@as(u32, ((pixel - width) + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) + @as(i32, @bitCast(@as(u32, ((pixel + width) - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) + @as(i32, @bitCast(@as(u32, ((pixel + width) + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) >> @intCast(2)));
        } else {
            r.* = @as(u32, @bitCast((@as(i32, @bitCast(@as(u32, (pixel - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*))) + @as(i32, @bitCast(@as(u32, (pixel + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) >> @intCast(1)));
            g.* = @as(u32, @bitCast(@as(u32, pixel.*)));
            b.* = @as(u32, @bitCast((@as(i32, @bitCast(@as(u32, (pixel - width).*))) + @as(i32, @bitCast(@as(u32, (pixel + width).*)))) >> @intCast(1)));
        }
    } else {
        if ((x & @as(u32, @bitCast(@as(i32, 1)))) != 0) {
            r.* = @as(u32, @bitCast((@as(i32, @bitCast(@as(u32, (pixel - width).*))) + @as(i32, @bitCast(@as(u32, (pixel + width).*)))) >> @intCast(1)));
            g.* = @as(u32, @bitCast(@as(u32, pixel.*)));
            b.* = @as(u32, @bitCast((@as(i32, @bitCast(@as(u32, (pixel - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*))) + @as(i32, @bitCast(@as(u32, (pixel + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) >> @intCast(1)));
        } else {
            r.* = @as(u32, @bitCast((((@as(i32, @bitCast(@as(u32, ((pixel - width) - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*))) + @as(i32, @bitCast(@as(u32, ((pixel - width) + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) + @as(i32, @bitCast(@as(u32, ((pixel + width) - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) + @as(i32, @bitCast(@as(u32, ((pixel + width) + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) >> @intCast(2)));
            g.* = @as(u32, @bitCast((((@as(i32, @bitCast(@as(u32, (pixel - @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*))) + @as(i32, @bitCast(@as(u32, (pixel + @as(usize, @bitCast(@as(isize, @intCast(@as(i32, 1)))))).*)))) + @as(i32, @bitCast(@as(u32, (pixel + width).*)))) + @as(i32, @bitCast(@as(u32, (pixel - width).*)))) >> @intCast(2)));
            b.* = @as(u32, @bitCast(@as(u32, pixel.*)));
        }
    }
}
