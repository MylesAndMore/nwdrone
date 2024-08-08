//! Websocket connection handler module.
//! Coordinates communication between the clients and the rest of the app.

const std = @import("std");
const heap = std.heap;
const json = std.json;
const log = std.log.scoped(.sockets);
const mem = std.mem;
const testing = std.testing;
const httpz = @import("httpz");
const websocket = httpz.websocket;

// The type for data sent/received over the websocket.
// An equivalent type is defined in the client code (/www/src/helpers/socket.ts).
pub const SocketData = struct {
    // Event that the data applies to, such as `thrust`, `shutdown`, etc.
    event: []const u8,
    // Object containing string key-value pairs, for example {"status":"1", "client":"mom"} etc.
    data: json.ArrayHashMap([]const u8),

    /// Initialize a new instance of DataZ.
    pub fn init() !@This() {
        return @This() {
            .event = undefined,
            .data = json.ArrayHashMap([]const u8){ .map = std.StringArrayHashMapUnmanaged([]const u8){} },
        };
    }

    /// Deinitialize an instance of Data.
    /// The `alloc` passed in should be the same `Allocator` that was used to manage `dat`.
    pub fn deinit(self: *@This(), alloc: mem.Allocator) void {
        self.data.deinit(alloc);
    }
};

// Arbitrary context for the websocket handler.
pub const Context = struct {
    alloc: mem.Allocator,
};

// Callback type for subscribers to the websocket.
// The lifetime of `data` is not guaranteed to be longer than the callback
// invocation, so it should be copied if needed.
const Callback = *const fn(event: SocketData) void;

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
        log.info("rx {s}", .{ message.data });
        const parsed = json.parseFromSlice(SocketData, self.ctx.alloc, message.data, .{}) catch |err| {
            log.warn("failed to parse message '{s}' ({})", .{ message.data, err });
            return err;
        };
        defer parsed.deinit();
        notifySubscribers(parsed.value);
    }

    /// Write data to the websocket connection.
    pub fn write(self: *@This(), data: SocketData) !void {
        var buf = try self.conn.writeBuffer(.text);
        defer buf.deinit();
        try json.stringify(data, .{}, buf.writer());
        try buf.flush();
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
var subscribers: std.StringHashMap(Callback) = undefined; // Hashmap of event names to subscriber callbacks

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
pub fn send(data: SocketData) !void {
    for (handlers.items) |handler|
        try handler.write(data);
}

/// Register a callback to be called when data is received for a specific event.
/// Only one callback can be registered per event.
pub fn subscribe(event: []const u8, callback: Callback) !void {
    try subscribers.put(event, callback);
    log.info("subscriber registered for '{s}'", .{ event });
}

/// Unregister a callback for a specific event.
pub fn unsubscribe(event: []const u8) void {
    if (!subscribers.remove(event)) {
        log.warn("no subscriber to unregister for '{s}'", .{ event });
        return;
    }
    log.info("subscriber unregistered for '{s}'", .{ event });
}

/// Notify all relavent subscribers of new data.
fn notifySubscribers(data: SocketData) void {
    if (subscribers.get(data.event)) |callback|
        callback(data);
}

test "data serialize" {
    const alloc = testing.allocator;

    var parse = try SocketData.init();
    defer parse.deinit(alloc);
    parse.event = "test";
    try parse.data.map.put(alloc, "status", "1");
    try parse.data.map.put(alloc, "client", "mom");

    var actual = std.ArrayList(u8).init(alloc);
    defer actual.deinit();

    const expected = "{\"event\":\"test\",\"data\":{\"status\":\"1\",\"client\":\"mom\"}}";
    try json.stringify(parse, .{}, actual.writer());

    try testing.expectEqualSlices(u8, expected, actual.items);
}

test "data deserialize" {
    const alloc = testing.allocator;

    var expected = try SocketData.init();
    defer expected.deinit(alloc);
    expected.event = "test";
    try expected.data.map.put(alloc, "status", "1");
    try expected.data.map.put(alloc, "client", "mom");

    const serialized = "{\"event\":\"test\",\"data\":{\"status\":\"1\",\"client\":\"mom\"}}";
    const actual = try json.parseFromSlice(SocketData, alloc, serialized, .{});
    defer actual.deinit();

    try testing.expectEqualStrings(expected.event, actual.value.event);
    try testing.expectEqualStrings(expected.data.map.get("status").?, actual.value.data.map.get("status").?);
    try testing.expectEqualStrings(expected.data.map.get("client").?, actual.value.data.map.get("client").?);
}
