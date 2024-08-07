const std = @import("std");
const httpz = @import("httpz");
const fs = std.fs;
const log = std.log.scoped(.server);
const mem = std.mem;

pub const sockets = @import("sockets.zig");

const ADDRESS = "0.0.0.0"; // IPv4 address to bind to
const PORT = 80; // Port to bind to

var server: httpz.ServerCtx(void, void) = undefined;
var gb_alloc: mem.Allocator = undefined; // Global allocator

/// Static file handler.
fn staticFile(req: *httpz.Request, res: *httpz.Response) !void {
    // index.html edge case
    const path = if (mem.eql(u8, req.url.path, "/")) "/index.html" else req.url.path;
    // Static files should be found in the `dist` directory relative to the executable
    const file_path = try std.fmt.allocPrint(res.arena, "dist{s}", .{ path });
    var exe_dir = try std.fs.openDirAbsolute(try std.fs.selfExeDirPathAlloc(res.arena), .{});
    defer exe_dir.close();
    var file = exe_dir.openFile(file_path, .{}) catch |err| {
        const realpath = exe_dir.realpathAlloc(res.arena, file_path) catch |e| switch (e) {
            error.FileNotFound => file_path,
            else => return e,
        };
        if (err == error.FileNotFound) {
            log.warn("file not found: {s}", .{ realpath });
            res.status = 404;
            res.body = "Not Found";
            return;
        }
        log.err("failed to open file: {s} ({})", .{ realpath, err });
        return err;
    };
    defer file.close();
    res.content_type = httpz.ContentType.forFile(path);
    res.body = try file.readToEndAlloc(res.arena, 100_000);
}

/// Websocket upgrade handler.
fn ws(req: *httpz.Request, res: *httpz.Response) !void {
    if (!(try httpz.upgradeWebsocket(sockets.Handler, req, res, sockets.Context{ .alloc = gb_alloc }))) {
        res.status = 400;
        res.body = "Invalid websocket handshake";
        return;
    }
}

/// Start the webserver on a new thread.
pub fn start(alloc: mem.Allocator) !void {
    log.info("starting server on {s}:{}", .{ ADDRESS, PORT });
    gb_alloc = alloc;

    server = try httpz.Server().init(alloc, .{
        .address = ADDRESS,
        .port = PORT,
    });
    var router = server.router();

    router.get("/*", staticFile);
    router.get("/ws", ws);

    sockets.init(alloc);

    const thread = try server.listenInNewThread();
    thread.detach();
    log.info("server listening on thread: {}", .{ thread.getHandle() });
}

/// Stop the webserver.
/// This function will block until the server thread has stopped.
pub fn stop() void {
    sockets.deinit();
    server.stop();
    // Wait for the server listen() thread to finish
    std.time.sleep(std.time.ns_per_ms * 500);
    server.deinit();
    log.info("server stopped", .{});
}
