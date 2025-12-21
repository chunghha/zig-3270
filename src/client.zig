/// TN3270 Network Client
/// Handles TCP connection to 3270 hosts and TN3270 protocol negotiation.
const std = @import("std");
const protocol = @import("protocol.zig");

/// TN3270 telnet option codes
pub const TelnetOption = enum(u8) {
    transmit_binary = 0,
    echo = 1,
    suppress_ga = 3,
    terminal_type = 24,
    end_of_record = 25,
    naws = 31,
};

/// TN3270 subnegotiation commands
pub const TelnetCommand = enum(u8) {
    se = 240, // Subnegotiation End
    nop = 241, // No Operation
    dm = 242, // Data Mark
    brk = 243, // Break
    ip = 244, // Interrupt Process
    ao = 245, // Abort Output
    ayt = 246, // Are You There
    ec = 247, // Erase Character
    el = 248, // Erase Line
    ga = 249, // Go Ahead
    sb = 250, // Subnegotiation Begin
    will = 251,
    wont = 252,
    do_cmd = 253,
    dont = 254,
    iac = 255, // Interpret As Command
};

/// Network client for TN3270
pub const Client = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    stream: ?std.net.Stream,
    connected: bool,
    read_buffer: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
    ) Client {
        return Client{
            .allocator = allocator,
            .host = host,
            .port = port,
            .stream = null,
            .connected = false,
            .read_buffer = &[_]u8{},
        };
    }

    /// Connect to the host
    pub fn connect(self: *Client) !void {
        // Try to parse as IP address first
        const address = std.net.Address.parseIp(self.host, self.port) catch |err| {
            std.debug.print("Note: Could not parse as IP address: {}\n", .{err});
            std.debug.print("Please provide an IP address (DNS resolution not yet supported).\n", .{});
            return error.InvalidAddress;
        };

        self.stream = try std.net.tcpConnectToAddress(address);
        self.connected = true;

        // Allocate read buffer
        self.read_buffer = try self.allocator.alloc(u8, 4096);

        // Perform TN3270 negotiation
        try self.negotiate();
    }

    /// Disconnect from host
    pub fn disconnect(self: *Client) void {
        if (self.stream) |stream| {
            stream.close();
        }
        self.connected = false;
        if (self.read_buffer.len > 0) {
            self.allocator.free(self.read_buffer);
        }
    }

    /// Send telnet negotiation sequence
    fn sendTelnetCommand(self: *Client, cmd: u8, option: u8) !void {
        const sequence = [_]u8{
            @intFromEnum(TelnetCommand.iac),
            cmd,
            option,
        };
        try self.stream.?.writeAll(&sequence);
    }

    /// Handle TN3270 negotiation
    fn negotiate(self: *Client) !void {
        // Request binary transmission
        try self.sendTelnetCommand(@intFromEnum(TelnetCommand.will), @intFromEnum(TelnetOption.transmit_binary));

        // Request suppress GA
        try self.sendTelnetCommand(@intFromEnum(TelnetCommand.will), @intFromEnum(TelnetOption.suppress_ga));

        // Request terminal type negotiation
        try self.sendTelnetCommand(@intFromEnum(TelnetCommand.will), @intFromEnum(TelnetOption.terminal_type));

        // Request end of record
        try self.sendTelnetCommand(@intFromEnum(TelnetCommand.will), @intFromEnum(TelnetOption.end_of_record));

        // Try to read negotiation response (optional - some servers don't send anything)
        // (disabled for now - can cause blocking)
        // _ = self.stream.?.read(self.read_buffer) catch {};
    }

    /// Read data from host
    pub fn read(self: *Client) ![]u8 {
        if (!self.connected) {
            return error.NotConnected;
        }

        const bytes_read = try self.stream.?.read(self.read_buffer);
        return self.read_buffer[0..bytes_read];
    }

    /// Send data to host
    pub fn send(self: *Client, data: []const u8) !void {
        if (!self.connected) {
            return error.NotConnected;
        }

        try self.stream.?.writeAll(data);
    }

    /// Send a 3270 command
    pub fn send3270Command(self: *Client, cmd: protocol.CommandCode, data: []const u8) !void {
        var buffer: [4096]u8 = undefined;
        buffer[0] = @intFromEnum(cmd);
        @memcpy(buffer[1 .. 1 + data.len], data);

        try self.send(buffer[0 .. 1 + data.len]);
    }
};

test "client initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const client = Client.init(allocator, "localhost", 3270);

    try std.testing.expectEqualStrings("localhost", client.host);
    try std.testing.expectEqual(@as(u16, 3270), client.port);
    try std.testing.expect(!client.connected);
}

test "telnet option enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(TelnetOption.transmit_binary));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(TelnetOption.echo));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(TelnetOption.suppress_ga));
    try std.testing.expectEqual(@as(u8, 24), @intFromEnum(TelnetOption.terminal_type));
}

test "telnet command enum values" {
    try std.testing.expectEqual(@as(u8, 255), @intFromEnum(TelnetCommand.iac));
    try std.testing.expectEqual(@as(u8, 251), @intFromEnum(TelnetCommand.will));
    try std.testing.expectEqual(@as(u8, 253), @intFromEnum(TelnetCommand.do_cmd));
}
