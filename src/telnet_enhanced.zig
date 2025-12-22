const std = @import("std");

/// Enhanced Telnet option negotiation
/// Implements RFC 854 Telnet Protocol with improved option handling
pub const TelnetOption = enum(u8) {
    transmit_binary = 0,
    echo = 1,
    suppress_go_ahead = 3,
    status = 5,
    timing_mark = 6,
    terminal_type = 24,
    window_size = 31,
    terminal_speed = 32,
    remote_flow_control = 33,
    linemode = 34,
    x_display_location = 35,
    environment = 36,
    _,
};

pub const TelnetCommand = enum(u8) {
    se = 240, // Subnegotiation end
    nop = 241, // No operation
    dm = 242, // Data mark
    brk = 243, // Break
    ip = 244, // Interrupt process
    ao = 245, // Abort output
    ayt = 246, // Are you there
    ec = 247, // Erase character
    el = 248, // Erase line
    ga = 249, // Go ahead
    sb = 250, // Subnegotiation begin
    will = 251, // Will do
    wont = 252, // Won't do
    do_cmd = 253, // Do
    dont = 254, // Don't
    iac = 255, // Interpret as command
};

/// Telnet negotiation state
pub const NegotiationState = enum {
    initial,
    sent_options,
    received_response,
    negotiated,
    failed,
};

/// Telnet protocol handler with enhanced negotiation
pub const TelnetNegotiator = struct {
    allocator: std.mem.Allocator,
    state: NegotiationState = .initial,
    remote_options: std.AutoHashMap(u8, bool),
    local_options: std.AutoHashMap(u8, bool),
    negotiation_timeout: u32 = 5000, // milliseconds
    max_retries: u32 = 3,
    retry_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) TelnetNegotiator {
        return TelnetNegotiator{
            .allocator = allocator,
            .remote_options = std.AutoHashMap(u8, bool).init(allocator),
            .local_options = std.AutoHashMap(u8, bool).init(allocator),
        };
    }

    pub fn deinit(self: *TelnetNegotiator) void {
        self.remote_options.deinit();
        self.local_options.deinit();
    }

    /// Build standard TN3270 negotiation sequence
    pub fn build_tn3270_negotiation(self: *TelnetNegotiator, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        // Request binary transmission
        try self.add_option_will(&buffer, @intFromEnum(TelnetOption.transmit_binary));

        // Request suppress go-ahead
        try self.add_option_will(&buffer, @intFromEnum(TelnetOption.suppress_go_ahead));

        // Request echo (for line editing)
        try self.add_option_dont(&buffer, @intFromEnum(TelnetOption.echo));

        // Request terminal type negotiation
        try self.add_option_will(&buffer, @intFromEnum(TelnetOption.terminal_type));

        // Send negotiation
        self.state = .sent_options;
        return buffer.toOwnedSlice();
    }

    /// Parse telnet response
    pub fn parse_response(self: *TelnetNegotiator, data: []const u8) !void {
        var i: usize = 0;
        while (i < data.len) {
            if (data[i] != @intFromEnum(TelnetCommand.iac)) {
                i += 1;
                continue;
            }

            if (i + 2 >= data.len) break;

            const cmd = data[i + 1];
            const opt = data[i + 2];

            switch (cmd) {
                @intFromEnum(TelnetCommand.will) => {
                    try self.remote_options.put(opt, true);
                },
                @intFromEnum(TelnetCommand.wont) => {
                    try self.remote_options.put(opt, false);
                },
                @intFromEnum(TelnetCommand.do_cmd) => {
                    try self.local_options.put(opt, true);
                },
                @intFromEnum(TelnetCommand.dont) => {
                    try self.local_options.put(opt, false);
                },
                else => {},
            }

            i += 3;
        }

        self.state = .negotiated;
    }

    /// Check if negotiation succeeded
    pub fn is_negotiated(self: *TelnetNegotiator) bool {
        return self.state == .negotiated and
            self.remote_options.contains(@intFromEnum(TelnetOption.transmit_binary));
    }

    /// Get negotiation status
    pub fn status(self: *TelnetNegotiator) NegotiationStatus {
        return NegotiationStatus{
            .state = self.state,
            .remote_options_count = self.remote_options.count(),
            .local_options_count = self.local_options.count(),
            .succeeded = self.is_negotiated(),
        };
    }

    fn add_option_will(self: *TelnetNegotiator, buffer: *std.ArrayList(u8), option: u8) !void {
        try buffer.append(@intFromEnum(TelnetCommand.iac));
        try buffer.append(@intFromEnum(TelnetCommand.will));
        try buffer.append(option);
        try self.local_options.put(option, true);
    }

    fn add_option_wont(self: *TelnetNegotiator, buffer: *std.ArrayList(u8), option: u8) !void {
        try buffer.append(@intFromEnum(TelnetCommand.iac));
        try buffer.append(@intFromEnum(TelnetCommand.wont));
        try buffer.append(option);
        try self.local_options.put(option, false);
    }

    fn add_option_do(self: *TelnetNegotiator, buffer: *std.ArrayList(u8), option: u8) !void {
        try buffer.append(@intFromEnum(TelnetCommand.iac));
        try buffer.append(@intFromEnum(TelnetCommand.do_cmd));
        try buffer.append(option);
        try self.remote_options.put(option, true);
    }

    fn add_option_dont(self: *TelnetNegotiator, buffer: *std.ArrayList(u8), option: u8) !void {
        try buffer.append(@intFromEnum(TelnetCommand.iac));
        try buffer.append(@intFromEnum(TelnetCommand.dont));
        try buffer.append(option);
        try self.remote_options.put(option, false);
    }
};

pub const NegotiationStatus = struct {
    state: NegotiationState,
    remote_options_count: usize,
    local_options_count: usize,
    succeeded: bool,
};

/// Handle server rejection gracefully
pub const RejectionHandler = struct {
    allocator: std.mem.Allocator,
    rejection_count: u32 = 0,
    max_rejections: u32 = 5,
    fallback_options: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) RejectionHandler {
        return RejectionHandler{
            .allocator = allocator,
            .fallback_options = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *RejectionHandler) void {
        self.fallback_options.deinit();
    }

    /// Handle option rejection and suggest fallback
    pub fn handle_rejection(self: *RejectionHandler, rejected_option: u8) !?u8 {
        self.rejection_count += 1;

        if (self.rejection_count > self.max_rejections) {
            return error.TooManyRejections;
        }

        // Map rejected option to fallback
        return switch (rejected_option) {
            @intFromEnum(TelnetOption.terminal_type) => @intFromEnum(TelnetOption.suppress_go_ahead),
            @intFromEnum(TelnetOption.window_size) => @intFromEnum(TelnetOption.terminal_type),
            else => null,
        };
    }

    /// Reset rejection counter after successful negotiation
    pub fn reset(self: *RejectionHandler) void {
        self.rejection_count = 0;
    }

    /// Check if we should attempt renegotiation
    pub fn should_renegotiate(self: *RejectionHandler) bool {
        return self.rejection_count > 0 and self.rejection_count <= self.max_rejections;
    }
};

// Tests
test "telnet negotiation: build tn3270 sequence" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var negotiator = TelnetNegotiator.init(allocator);
    defer negotiator.deinit();

    const sequence = try negotiator.build_tn3270_negotiation(allocator);
    defer allocator.free(sequence);

    try std.testing.expect(sequence.len > 0);
    try std.testing.expectEqual(@intFromEnum(TelnetCommand.iac), sequence[0]);
}

test "telnet negotiation: parse response" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var negotiator = TelnetNegotiator.init(allocator);
    defer negotiator.deinit();

    // Mock response
    const response = [_]u8{
        @intFromEnum(TelnetCommand.iac),
        @intFromEnum(TelnetCommand.will),
        @intFromEnum(TelnetOption.transmit_binary),
    };

    try negotiator.parse_response(&response);

    try std.testing.expectEqual(NegotiationState.negotiated, negotiator.state);
}

test "telnet negotiation: status" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var negotiator = TelnetNegotiator.init(allocator);
    defer negotiator.deinit();

    const status = negotiator.status();

    try std.testing.expectEqual(NegotiationState.initial, status.state);
    try std.testing.expectEqual(false, status.succeeded);
}

test "rejection handler: handle rejection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var handler = RejectionHandler.init(allocator);
    defer handler.deinit();

    const fallback = try handler.handle_rejection(@intFromEnum(TelnetOption.terminal_type));

    try std.testing.expect(fallback != null);
    try std.testing.expectEqual(@intFromEnum(TelnetOption.suppress_go_ahead), fallback.?);
}

test "rejection handler: too many rejections" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var handler = RejectionHandler.init(allocator);
    defer handler.deinit();

    handler.max_rejections = 2;

    _ = try handler.handle_rejection(@intFromEnum(TelnetOption.terminal_type));
    _ = try handler.handle_rejection(@intFromEnum(TelnetOption.terminal_type));

    const result = handler.handle_rejection(@intFromEnum(TelnetOption.terminal_type));
    try std.testing.expectError(error.TooManyRejections, result);
}
