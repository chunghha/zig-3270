//! C Foreign Function Interface (FFI) for zig-3270
//!
//! This module provides C-compatible bindings for the core TN3270 protocol,
//! client, and screen functionality. It allows C and other languages via ctypes
//! to use zig-3270 as a library.
//!
//! All exported functions follow C calling conventions and memory safety rules:
//! - Returned pointers are valid until freed with corresponding free function
//! - String lifetimes are documented for each function
//! - Error codes are returned as i32 with 0 = success

const std = @import("std");
const protocol = @import("protocol.zig");
const client = @import("client.zig");
const screen = @import("screen.zig");
const field = @import("field.zig");
const ebcdic = @import("ebcdic.zig");
const parser = @import("parser.zig");

// ============================================================================
// Error Codes (for C compatibility)
// ============================================================================

pub const ERROR_SUCCESS = 0;
pub const ERROR_INVALID_ARG = 1;
pub const ERROR_OUT_OF_MEMORY = 2;
pub const ERROR_CONNECTION_FAILED = 3;
pub const ERROR_PARSE_ERROR = 4;
pub const ERROR_INVALID_STATE = 5;
pub const ERROR_TIMEOUT = 6;
pub const ERROR_FIELD_NOT_FOUND = 7;

// ============================================================================
// Opaque Types (Hide implementation from C)
// ============================================================================

pub opaque type TN3270Client {
    inner: *client.Client,
};

pub opaque type TN3270Screen {
    inner: *screen.Screen,
};

pub opaque type TN3270FieldManager {
    inner: *field.FieldManager,
};

pub opaque type TN3270Parser {
    inner: *parser.Parser,
};

pub opaque type TN3270String {
    data: [*]u8,
    len: usize,
};

// ============================================================================
// Protocol Types (C-compatible structs)
// ============================================================================

/// C-compatible representation of screen address
pub const TN3270Address = extern struct {
    row: u8,
    col: u8,
};

/// C-compatible representation of field attribute
pub const TN3270FieldAttr = extern struct {
    protected: u1,
    numeric: u1,
    hidden: u1,
    intensity: u1,
    reserved: u4,
};

/// C-compatible representation of command code
pub const TN3270CommandCode = extern enum(u8) {
    WriteStructuredField = 0x01,
    EraseWrite = 0x05,
    EraseWriteAlternate = 0x0d,
    Write = 0x01,
    EraseAllUnprotected = 0x0f,
    ReadBuffer = 0x02,
    ReadModified = 0x06,
    ReadModifiedAll = 0x6e,
    SearchForString = 0x34,
    SelectiveEraseWrite = 0x80,
    EraseWrite3270 = 0x05,
    _,
};

/// C-compatible screen position
pub const TN3270Position = extern struct {
    offset: u16,
};

// ============================================================================
// Memory Management
// ============================================================================

var c_allocator: std.mem.Allocator = undefined;
var c_allocator_initialized: bool = false;

fn init_c_allocator() void {
    if (!c_allocator_initialized) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        c_allocator = gpa.allocator();
        c_allocator_initialized = true;
    }
}

/// Allocate memory (C-compatible)
pub export fn zig3270_malloc(size: usize) ?[*]u8 {
    init_c_allocator();
    const bytes = c_allocator.allocWithOptions(u8, size, @alignOf(u8), null) catch return null;
    return bytes.ptr;
}

/// Free memory (C-compatible)
pub export fn zig3270_free(ptr: ?[*]u8, size: usize) void {
    if (ptr) |p| {
        c_allocator.free(p[0..size]);
    }
}

// ============================================================================
// String Management (C-compatible)
// ============================================================================

/// Create a C string from Zig slice
pub fn make_c_string(allocator: std.mem.Allocator, slice: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, slice.len + 1);
    @memcpy(result[0..slice.len], slice);
    result[slice.len] = 0;
    return result;
}

/// Free a C string
pub export fn zig3270_string_free(str: ?[*:0]u8) void {
    if (str) |s| {
        const len = std.mem.len(s);
        c_allocator.free(s[0 .. len + 1]);
    }
}

// ============================================================================
// Protocol Functions
// ============================================================================

/// Convert EBCDIC byte to ASCII
pub export fn zig3270_ebcdic_decode_byte(ebcdic_byte: u8) u8 {
    return ebcdic.decode_byte(ebcdic_byte);
}

/// Convert ASCII byte to EBCDIC
pub export fn zig3270_ebcdic_encode_byte(ascii_byte: u8) i32 {
    return ebcdic.encode_byte(ascii_byte) catch -1;
}

/// Decode EBCDIC buffer to ASCII
pub export fn zig3270_ebcdic_decode(
    ebcdic_buf: [*]const u8,
    ebcdic_len: usize,
    ascii_buf: [*]u8,
    ascii_len: usize,
) i32 {
    init_c_allocator();
    const ebcdic_slice = ebcdic_buf[0..ebcdic_len];
    const ascii_slice = ascii_buf[0..ascii_len];
    const result = ebcdic.decode(ebcdic_slice, ascii_slice) catch return ERROR_INVALID_ARG;
    return @intCast(result);
}

/// Encode ASCII buffer to EBCDIC
pub export fn zig3270_ebcdic_encode(
    ascii_buf: [*]const u8,
    ascii_len: usize,
    ebcdic_buf: [*]u8,
    ebcdic_len: usize,
) i32 {
    init_c_allocator();
    const ascii_slice = ascii_buf[0..ascii_len];
    const ebcdic_slice = ebcdic_buf[0..ebcdic_len];
    const result = ebcdic.encode(ascii_slice, ebcdic_slice) catch return ERROR_INVALID_ARG;
    return @intCast(result);
}

// ============================================================================
// Client Functions
// ============================================================================

/// Create a new TN3270 client
pub export fn zig3270_client_new(
    host: [*:0]const u8,
    port: u16,
) i32 {
    init_c_allocator();
    _ = host;
    _ = port;
    // TODO: Implement when client.zig is refactored for FFI
    return ERROR_SUCCESS;
}

/// Free a TN3270 client
pub export fn zig3270_client_free(client_ptr: ?*TN3270Client) void {
    if (client_ptr) |c| {
        init_c_allocator();
        c_allocator.destroy(c);
    }
}

/// Connect to a mainframe
pub export fn zig3270_client_connect(client_ptr: *TN3270Client) i32 {
    _ = client_ptr;
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Disconnect from mainframe
pub export fn zig3270_client_disconnect(client_ptr: *TN3270Client) i32 {
    _ = client_ptr;
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Send a command to the mainframe
pub export fn zig3270_client_send_command(
    client_ptr: *TN3270Client,
    command: [*]const u8,
    command_len: usize,
) i32 {
    _ = client_ptr;
    _ = command;
    _ = command_len;
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Read response from mainframe (blocking)
pub export fn zig3270_client_read_response(
    client_ptr: *TN3270Client,
    buffer: [*]u8,
    buffer_len: usize,
    timeout_ms: u32,
) i32 {
    _ = client_ptr;
    _ = buffer;
    _ = buffer_len;
    _ = timeout_ms;
    // TODO: Implement
    return ERROR_SUCCESS;
}

// ============================================================================
// Screen Functions
// ============================================================================

/// Create a new screen
pub export fn zig3270_screen_new() i32 {
    init_c_allocator();
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Free a screen
pub export fn zig3270_screen_free(screen_ptr: ?*TN3270Screen) void {
    if (screen_ptr) |s| {
        init_c_allocator();
        c_allocator.destroy(s);
    }
}

/// Clear screen
pub export fn zig3270_screen_clear(screen_ptr: *TN3270Screen) i32 {
    _ = screen_ptr;
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Write text to screen at position
pub export fn zig3270_screen_write(
    screen_ptr: *TN3270Screen,
    row: u8,
    col: u8,
    text: [*]const u8,
    text_len: usize,
) i32 {
    _ = screen_ptr;
    _ = row;
    _ = col;
    _ = text;
    _ = text_len;
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Read text from screen at position
pub export fn zig3270_screen_read(
    screen_ptr: *TN3270Screen,
    row: u8,
    col: u8,
    buffer: [*]u8,
    buffer_len: usize,
) i32 {
    _ = screen_ptr;
    _ = row;
    _ = col;
    _ = buffer;
    _ = buffer_len;
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Get screen as string (allocates memory)
pub export fn zig3270_screen_to_string(screen_ptr: *TN3270Screen) ?[*:0]u8 {
    _ = screen_ptr;
    init_c_allocator();
    // TODO: Implement
    return null;
}

/// Get current cursor position
pub export fn zig3270_screen_get_cursor(screen_ptr: *TN3270Screen, addr: *TN3270Address) i32 {
    _ = screen_ptr;
    _ = addr;
    // TODO: Implement
    return ERROR_SUCCESS;
}

// ============================================================================
// Field Functions
// ============================================================================

/// Create a new field manager
pub export fn zig3270_fields_new() i32 {
    init_c_allocator();
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Free field manager
pub export fn zig3270_fields_free(fields_ptr: ?*TN3270FieldManager) void {
    if (fields_ptr) |f| {
        init_c_allocator();
        c_allocator.destroy(f);
    }
}

/// Add a field
pub export fn zig3270_fields_add(
    fields_ptr: *TN3270FieldManager,
    offset: u16,
    length: u16,
    attr: TN3270FieldAttr,
) i32 {
    _ = fields_ptr;
    _ = offset;
    _ = length;
    _ = attr;
    // TODO: Implement
    return ERROR_SUCCESS;
}

/// Get field count
pub export fn zig3270_fields_count(fields_ptr: *TN3270FieldManager) u32 {
    _ = fields_ptr;
    // TODO: Implement
    return 0;
}

/// Get field by index
pub export fn zig3270_fields_get(
    fields_ptr: *TN3270FieldManager,
    index: u32,
    offset: *u16,
    length: *u16,
) i32 {
    _ = fields_ptr;
    _ = index;
    _ = offset;
    _ = length;
    // TODO: Implement
    return ERROR_SUCCESS;
}

// ============================================================================
// Version & Info
// ============================================================================

pub export fn zig3270_version() [*:0]const u8 {
    return "0.11.1-beta";
}

pub export fn zig3270_protocol_version() [*:0]const u8 {
    return "TN3270E";
}

// ============================================================================
// Tests
// ============================================================================

test "ebcdic C bindings" {
    init_c_allocator();

    // Test decode_byte
    const ebcdic_a: u8 = 0xc1;
    const ascii_a = zig3270_ebcdic_decode_byte(ebcdic_a);
    try std.testing.expectEqual(@as(u8, 'A'), ascii_a);

    // Test encode_byte
    const enc_result = zig3270_ebcdic_encode_byte('A');
    try std.testing.expectEqual(@as(i32, 0xc1), enc_result);
}

test "buffer encoding C bindings" {
    init_c_allocator();

    // Test decode buffer
    const ebcdic_buf: []const u8 = &[_]u8{ 0xc1, 0xc2, 0xc3 }; // ABC
    var ascii_buf: [3]u8 = undefined;

    const decoded = zig3270_ebcdic_decode(
        ebcdic_buf.ptr,
        ebcdic_buf.len,
        &ascii_buf,
        ascii_buf.len,
    );

    try std.testing.expectEqual(@as(i32, 3), decoded);
    try std.testing.expectEqualSlices(u8, "ABC", &ascii_buf);
}

test "memory allocation C bindings" {
    init_c_allocator();

    // Test malloc
    const ptr = zig3270_malloc(100);
    try std.testing.expect(ptr != null);

    // Test free
    if (ptr) |p| {
        zig3270_free(p, 100);
    }
}

test "version functions" {
    const version = zig3270_version();
    try std.testing.expect(version != null);

    const proto = zig3270_protocol_version();
    try std.testing.expect(proto != null);
}
