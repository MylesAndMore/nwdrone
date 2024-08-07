//! Websocket connection handler module.
//! Coordinates communication between the clients and the rest of the app.

const std = @import("std");
const json = std.json;
const log = std.log.scoped(.sockets);
const mem = std.mem;
const httpz = @import("httpz");
const websocket = httpz.websocket;

pub const quad = @import("../control/quad.zig");

// The type for data sent/received over the websocket.
// An equivalent type is defined in the client code (www/src/helpers/socket.ts).
pub const Data = struct {
    cmp: []const u8, // Component; component that the data applies to, such as `led`, `btn`, etc.
    dat: json.Value, // Data; array of key-value pairs, for example {"status":1},{"client":"mom"} etc.
    // dat: std.ArrayList(json.ArrayHashMap(any)),
};

// Arbitrary context for the websocket handler.
pub const Context = struct {
    alloc: mem.Allocator,
};

// Callback type for subscribers to the websocket.
const Callback = *const fn(data: Data) void;

// Websocket handler, responsible for processing messages sent over the websocket.
// httpz will create an instance of this handler for each websocket connection.
pub const Handler = struct {
    ctx: Context,
    conn: *websocket.Conn,

    /// Is run when a new websocket connection is established.
    pub fn init(conn: *websocket.Conn, ctx: Context) !@This() {
        log.info("new connection", .{});
        const self = @This(){
            .ctx = ctx,
            .conn = conn,
        };
        try handlers.append(self);
        return self;
    }

    /// Is run when a message is received over the websocket.
    pub fn handle(self: *const @This(), message: websocket.Message) !void {
        const parsed = try json.parseFromSlice(Data, self.ctx.alloc, message.data, .{});
        defer parsed.deinit();
        const received = parsed.value;

        notify_subscribers(received);

        if (mem.eql(u8, received.cmp, "thrust")) {
            var thrust: f32 = 0.0;
            const val = received.dat.array.items[0].object.get("value").?;
            switch (val) {
                .float => thrust = @floatCast(val.float),
                .integer => thrust = @floatFromInt(val.integer),
                else => {
                    log.err("invalid thrust value: {}", .{ val });
                },
            }
            quad.base = thrust;
        }
    }

    /// Write data to the websocket connection.
    // pub fn write(self: *@This(), data: Data) !void {
    pub fn write(self: *const @This(), data: []const u8) !void {
        // var wb = try self.conn.writeBuffer(.text);
        // defer wb.deinit();
        // try json.stringify(data, .{}, wb.writer());
        // try wb.flush();
        try self.conn.write(data);
    }

    /// Is run when the websocket connection is closed.
    pub fn close(_: *@This()) void {
        log.info("connection closed", .{});
    }
};

var handlers: std.ArrayList(Handler) = undefined; // List of websocket handlers
// To match the client-side implementation, this hashmap should technically
// contain an ArrayList of Callbacks and not just a single Callback,
// but I spent a few too many hours trying to get that to work and I'd rather
// focus on more useful things.
var subscribers: std.StringHashMap(Callback) = undefined; // Hashmap of component names to subscriber callbacks

/// Initialize the websocket backend.
pub fn init(alloc: mem.Allocator) void {
    log.info("initializing backend", .{});
    handlers = @TypeOf(handlers).init(alloc);
    subscribers = @TypeOf(subscribers).init(alloc);
}

/// Deinitialize the websocket backend.
pub fn deinit() void {
    log.info("deinitializing backend", .{});
    handlers.deinit();
    subscribers.deinit();
}

/// Send data to all open websocket connections.
// pub fn send(data: Data) !void {
pub fn send(data: []const u8) !void {
    for (handlers.items) |handler|
        try handler.write(data);
}

/// Register a callback to be called when data is received for a specific component.
/// Only one callback can be registered per component.
pub fn subscribe(component: []const u8, callback: Callback) !void {
    try subscribers.put(component, callback);
    log.info("subscriber registered for '{s}'", .{ component });
}

/// Unregister a callback for a specific component.
pub fn unsubscribe(component: []const u8) void {
    if (!subscribers.remove(component)) {
        log.warn("no subscriber to unregister for '{s}'", .{ component });
        return;
    }
    log.info("subscriber unregistered for '{s}'", .{ component });
}

/// Notify all relavent subscribers of new data.
fn notify_subscribers(data: Data) void {
    if (subscribers.get(data.cmp)) |callback|
        callback(data);
}
