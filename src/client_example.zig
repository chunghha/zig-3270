/// Example: Connecting to a 3270 host
/// Shows how to use the client module to connect and interact with a host
const std = @import("std");
const client_mod = @import("client.zig");
const protocol = @import("protocol.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("3270 Terminal Client Example\n", .{});
    std.debug.print("============================\n\n", .{});

    // Example 1: Basic connection setup
    std.debug.print("Example 1: Client Initialization\n", .{});
    std.debug.print("─────────────────────────────────\n", .{});

    var client = client_mod.Client.init(allocator, "mainframe.example.com", 3270);
    std.debug.print("✓ Created client for {}:{}\n\n", .{ client.host, client.port });

    // Example 2: Telnet option codes
    std.debug.print("Example 2: TN3270 Protocol Options\n", .{});
    std.debug.print("─────────────────────────────────\n", .{});

    std.debug.print("Transmit Binary: {}\n", .{@intFromEnum(client_mod.TelnetOption.transmit_binary)});
    std.debug.print("Suppress GA: {}\n", .{@intFromEnum(client_mod.TelnetOption.suppress_ga)});
    std.debug.print("Terminal Type: {}\n", .{@intFromEnum(client_mod.TelnetOption.terminal_type)});
    std.debug.print("End of Record: {}\n\n", .{@intFromEnum(client_mod.TelnetOption.end_of_record)});

    // Example 3: Telnet command codes
    std.debug.print("Example 3: Telnet Command Codes\n", .{});
    std.debug.print("─────────────────────────────────\n", .{});

    std.debug.print("IAC (Interpret As Command): {}\n", .{@intFromEnum(client_mod.TelnetCommand.iac)});
    std.debug.print("WILL: {}\n", .{@intFromEnum(client_mod.TelnetCommand.will)});
    std.debug.print("DO: {}\n", .{@intFromEnum(client_mod.TelnetCommand.do_cmd)});
    std.debug.print("SB (Subnegotiation Begin): {}\n", .{@intFromEnum(client_mod.TelnetCommand.sb)});
    std.debug.print("SE (Subnegotiation End): {}\n\n", .{@intFromEnum(client_mod.TelnetCommand.se)});

    // Example 4: 3270 Protocol Commands
    std.debug.print("Example 4: 3270 Command Codes\n", .{});
    std.debug.print("─────────────────────────────────\n", .{});

    std.debug.print("Write: 0x{X:0>2}\n", .{@intFromEnum(protocol.CommandCode.write)});
    std.debug.print("Erase Write: 0x{X:0>2}\n", .{@intFromEnum(protocol.CommandCode.erase_write)});
    std.debug.print("Read Buffer: 0x{X:0>2}\n", .{@intFromEnum(protocol.CommandCode.read_buffer)});
    std.debug.print("Read Modified: 0x{X:0>2}\n\n", .{@intFromEnum(protocol.CommandCode.read_modified)});

    // Example 5: Connection workflow (disabled without real host)
    std.debug.print("Example 5: Connection Workflow\n", .{});
    std.debug.print("─────────────────────────────────\n", .{});
    std.debug.print("To connect to a real host:\n", .{});
    std.debug.print("  1. Create client: client = Client.init(alloc, host, port)\n", .{});
    std.debug.print("  2. Connect: try client.connect()\n", .{});
    std.debug.print("  3. Send commands: try client.send3270Command(cmd, data)\n", .{});
    std.debug.print("  4. Read responses: try client.read()\n", .{});
    std.debug.print("  5. Disconnect: client.disconnect()\n\n", .{});

    // Example 6: 3270 Address encoding
    std.debug.print("Example 6: 3270 Address Encoding\n", .{});
    std.debug.print("─────────────────────────────────\n", .{});

    const addr1 = protocol.Address{ .row = 0, .col = 0 };
    const bytes1 = addr1.to_bytes();
    std.debug.print("Row 0, Col 0 -> Bytes: 0x{X:0>2}{X:0>2}\n", .{ bytes1[0], bytes1[1] });

    const addr2 = protocol.Address{ .row = 5, .col = 20 };
    const bytes2 = addr2.to_bytes();
    std.debug.print("Row 5, Col 20 -> Bytes: 0x{X:0>2}{X:0>2}\n", .{ bytes2[0], bytes2[1] });

    const decoded = protocol.Address.from_bytes(bytes2);
    std.debug.print("Decoded back -> Row {}, Col {}\n\n", .{ decoded.row, decoded.col });

    std.debug.print("+==========================================+\n", .{});
    std.debug.print("|  Ready to connect to 3270 host          |\n", .{});
    std.debug.print("|  See src/client.zig for implementation  |\n", .{});
    std.debug.print("+==========================================+\n", .{});
}

pub fn exampleConnectToHost() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // This example shows the connection flow (disabled without a real host)
    var client = client_mod.Client.init(allocator, "mainframe.example.com", 3270);

    // Uncomment to connect to a real host:
    // try client.connect();
    // defer client.disconnect();
    //
    // // Send initial command
    // try client.send3270Command(.erase_write, "");
    //
    // // Read response
    // const response = try client.read();
    // std.debug.print("Received {} bytes\n", .{response.len});
}
