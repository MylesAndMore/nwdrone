//! Server module, handling basic HTTP and Websocket requests.

const std = @import("std");
const httpz = @import("httpz");
const fs = std.fs;
const log = std.log.scoped(.server);
const mem = std.mem;

pub const sockets = @import("sockets.zig");

const ADDRESS = "0.0.0.0"; // IPv4 address to bind to
const PORT = 80; // Port to bind to

var alloc: mem.Allocator = undefined;
var server: httpz.ServerCtx(void, void) = undefined;

/// Static file handler.
fn staticFile(req: *httpz.Request, res: *httpz.Response) !void {
    // index.html edge case
    var path = if (mem.eql(u8, req.url.path, "/")) "/index.html" else req.url.path;
    var retry = true;

    while (retry) {
        retry = false;
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
                if (mem.containsAtLeast(u8, path, 1, ".")) {
                    // Path has a dot, so it's probably a file we don't have
                    log.warn("file not found: {s}", .{ realpath });
                    res.status = 404;
                    res.body = "Not Found";
                    return;
                } else {
                    // Path does not contain a dot
                    // It's probably a routed page, so we can silently serve the index
                    log.info("redirecting request from '{s}' to '/'", .{ path });
                    path = "/index.html";
                    retry = true;
                    continue;
                }
            }
            log.err("failed to open file: {s} ({})", .{ realpath, err });
            return err;
        };
        defer file.close();
        res.content_type = httpz.ContentType.forFile(path);
        res.body = try file.readToEndAlloc(res.arena, 1_000_000);
    }
}

/// Websocket upgrade handler.
fn ws(req: *httpz.Request, res: *httpz.Response) !void {
    if (!(try httpz.upgradeWebsocket(sockets.Handler, req, res, sockets.Context{ .alloc = alloc }))) {
        res.status = 400;
        res.body = "Invalid websocket handshake";
        return;
    }
}

/// Start the webserver on a new thread.
pub fn start(allocator: mem.Allocator) !void {
    log.info("starting server on {s}:{}", .{ ADDRESS, PORT });
    alloc = allocator;

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
