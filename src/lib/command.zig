//! The command module provides a simple interface for running shell commands.

const std = @import("std");
const Child = std.process.Child;

/// Execute a shell command in the foreground.
/// This function will block until the command completes, and program IO will be inherited.
/// Returns true if the command exits successfully.
pub fn run(alloc: std.mem.Allocator, cmd: []const u8, opt_args: ?[]const []const u8) bool {
    var argv = std.ArrayList([]const u8).init(alloc);
    defer argv.deinit();
    argv.append(cmd) catch return false;
    if (opt_args) |args| {
        for (args) |arg|
            argv.append(arg) catch return false;
    }
    var proc = Child.init(argv.items, alloc);
    proc.spawn() catch return false;
    const exit = proc.wait() catch return false;
    switch (exit) {
        .Exited => |code| return code == 0,
        else => return false,
    }
}
