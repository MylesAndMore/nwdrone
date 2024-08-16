//! Websocket connection handler module.
//! Coordinates communication between the clients and the rest of the app.

const std = @import("std");
const heap = std.heap;
const json = std.json;
const log = std.log.scoped(.sockets);
const mem = std.mem;
const testing = std.testing;
const time = std.time;
const httpz = @import("httpz");
const websocket = httpz.websocket;

const MIN_SOCKET_UPDATE_RATE = 2; // Minimum rate at which to update the websocket, in Hz
const MIN_SOCKET_UPDATE_INTERVAL = time.ms_per_s / MIN_SOCKET_UPDATE_RATE;

// The type for data sent/received over the websocket.
// An equivalent type is defined in the client code (/www/src/helpers/socket.ts).
pub const SocketData = struct {
    // Event that the data applies to, such as `thrust`, `shutdown`, etc.
    event: []const u8,
    // Object containing string key-value pairs, for example {"status":"1", "client":"mom"} etc.
    data: json.ArrayHashMap([]const u8),

    /// Initialize a new instance of SocketData.
    pub fn init() !@This() {
        return @This() {
            .event = undefined,
            .data = json.ArrayHashMap([]const u8){ .map = std.StringArrayHashMapUnmanaged([]const u8){} },
        };
    }

    /// Deinitialize an instance of SocketData.
    /// The `alloc` passed in should be the same `Allocator` that was used to manage `dat`.
    pub fn deinit(self: *@This(), alloc: mem.Allocator) void {
        self.data.deinit(alloc);
    }
};

// Type of event to subscribe to.
pub const EventType = enum {
    Receive,
    Dispatch,
};

// Callback type for receivers to the websocket.
// The lifetime of `data` is not guaranteed to be longer than the callback
// invocation, so it should be copied if needed.
pub const ReceiveCallback = *const fn(event: SocketData) anyerror!void;
// Callback type for dispatchers to the websocket.
pub const DispatchCallback = *const fn(send: SendFn) anyerror!void;
// Function type for sending data over the websocket.
pub const SendFn = *const fn(data: SocketData) anyerror!void;

// Arbitrary context for the websocket handler.
pub const Context = struct {
    alloc: mem.Allocator,
};

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
        const parsed = json.parseFromSlice(SocketData, self.ctx.alloc, message.data, .{}) catch |err| {
            log.warn("failed to parse message '{s}' ({})", .{ message.data, err });
            return err;
        };
        defer parsed.deinit();
        notify_receivers(parsed.value);
    }

    /// Write data to the websocket connection.
    pub fn write(self: *@This(), data: SocketData) !void {
        var buf = try self.conn.writeBuffer(.text);
        defer buf.deinit();
        try json.stringify(data, .{}, buf.writer());
        try buf.flush();
    }

    /// Is run when the websocket connection is closed.
    pub fn close(self: *@This()) void {
        // Remove this handler from the list of handlers
        for (handlers.items, 0..) |handler, i| {
            if (std.meta.eql(handler, self.*)) {
                _ = handlers.swapRemove(i);
                log.info("connection closed", .{});
                return;
            }
        }
        log.warn("failed to close connection", .{});
    }
};

var handlers: std.ArrayList(Handler) = undefined; // List of websocket handlers
// To match the client-side implementation, this hashmap should technically
// contain an ArrayList of *Callbacks and not just a single *Callback,
// but I spent a few too many hours trying to get that to work and I'd rather
// focus on more useful things.
var receivers: std.StringHashMap(ReceiveCallback) = undefined; 
var dispatchers: std.StringArrayHashMap(DispatchCallback) = undefined;
var last_send: i64 = 0; // Last time data was sent (via update())

/// Initialize the websocket backend.
pub fn init(alloc: mem.Allocator) void {
    log.info("initializing backend", .{});
    handlers = @TypeOf(handlers).init(alloc);
    receivers = @TypeOf(receivers).init(alloc);
    dispatchers = @TypeOf(dispatchers).init(alloc);
}

/// Deinitialize the websocket backend.
pub fn deinit() void {
    log.info("deinitializing backend", .{});
    handlers.deinit();
    receivers.deinit();
    dispatchers.deinit();
}

/// Register a callback to be called when data is received/dispatch is needed
/// for a specific event.
/// Only one callback can be registered per event.
pub fn subscribe(event: []const u8, comptime callback: anytype, comptime on: EventType) !void {
    switch (on) {
        .Receive => {
            try receivers.put(event, callback);
            log.info("receiver registered for event '{s}'", .{ event });
        },
        .Dispatch => {
            try dispatchers.put(event, callback);
            log.info("dispatcher registered for event '{s}'", .{ event });
        },
    }
}

/// Unregister a callback for a specific event.
pub fn unsubscribe(event: []const u8) void {
    if (receivers.remove(event) or dispatchers.swapRemove(event)) {
        log.info("event '{s}' unregistered", .{ event });
        return;
    }
    log.warn("nothing to unregister for event '{s}'", .{ event });
}

/// Update the websocket backend.
/// This function will invoke, if necessary, all registered dispatchers
/// which may block for a significant period of time.
pub fn update() void {
    if (time.milliTimestamp() - last_send < MIN_SOCKET_UPDATE_INTERVAL)
        return;

    for (dispatchers.values()) |callback| {
        callback(send) catch |err| {
            log.warn("unhandled exception in dispatch callback: {}", .{ err });
            continue;
        };
    }
    last_send = time.milliTimestamp();
}
// If you were wondering, update() could easily be on another thread.
// It's not because I'm too lazy to implement thread safety in all the modules
// that issue dispatches.
// The CPU usage is also very high if I thread this for some reason.

/// Send data to all open websocket connections.
fn send(data: SocketData) !void {
    for (0..handlers.items.len) |i|
        try handlers.items[i].write(data);
}

/// Notify all relavent receivers of new data.
fn notify_receivers(data: SocketData) void {
    if (receivers.get(data.event)) |callback| {
        callback(data) catch |err| {
            log.warn("unhandled exception in receive callback: {}", .{ err });
        };
    }
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
