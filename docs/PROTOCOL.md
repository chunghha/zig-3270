# TN3270 Protocol Reference

Complete reference documentation for the TN3270 (Telnet 3270) protocol implementation in zig-3270.

## Overview

TN3270 is the telnet-based variant of the IBM 3270 terminal protocol. It enables connection to mainframe systems (CICS, IMS, TSO) over TCP/IP using a terminal emulator.

- **Encoding**: EBCDIC (currently ASCII in zig-3270)
- **Screen**: 24 rows × 80 columns (standard)
- **Data Model**: Screen buffer + field definitions
- **Key Concept**: User modifies fields → server validates and updates screen

## Protocol Layers

```
┌─────────────────────────┐
│  Telnet Layer (RFC 854) │ TCP port 3270 / 3271
├─────────────────────────┤
│  TN3270 Negotiation     │ Telnet options negotiation
├─────────────────────────┤
│  3270 Data Stream       │ Commands, order codes, data
└─────────────────────────┘
```

## 3270 Data Stream Format

### Basic Message Structure

```
[Command Code] [Data Stream]
    (1 byte)      (N bytes)
```

### Example: Write Command with Data

```
0x01                        // Write command
0x11 0x40 0x50              // Set Buffer Address (row 0, col 0)
0x1D 0xC0                   // Start Field (protected, intensified)
'H' 'e' 'l' 'l' 'o'         // Text data
```

---

## Command Codes

Commands define the operation the terminal should perform.

### Supported Commands

#### Write (0x01)
Writes data to screen at specified addresses.

- **Hex**: `0x01`
- **Parameters**: Write masked (WCC), followed by order codes and data
- **Response**: None (keyboard available for input)
- **Usage**: Most common command for screen updates

**Example**:
```
0x01 0x00 [order codes and data...]
```

#### Erase Write (0x05)
Clears screen and writes new data.

- **Hex**: `0x05`
- **Parameters**: WCC, followed by order codes and data
- **Response**: None
- **Usage**: Initial screen or complete refresh

**Example**:
```
0x05 0x00 [order codes and data...]
```

#### Erase Write Alternative (0x0D)
Alternate form of Erase Write with different WCC interpretation.

- **Hex**: `0x0D`
- **Usage**: When WCC bits need different meaning

#### Read Buffer (0x02)
Request entire screen content from terminal.

- **Hex**: `0x02`
- **Response**: Entire screen buffer with attributes
- **Usage**: Debugging or screen sync

#### Read Modified (0x06)
Request only changed fields (most common user input command).

- **Hex**: `0x06`
- **Response**: AID + modified field data
- **Usage**: User presses Enter/function key
- **Response Format**:
  ```
  [AID Byte] [Field 1 Address] [Field 1 Data...]
             [Field 2 Address] [Field 2 Data...]...
  ```

---

## Order Codes

Order codes define operations within a command's data stream.

### Set Buffer Address (0x11)

Positions cursor and subsequent writes.

- **Hex**: `0x11`
- **Parameters**: 2-byte address
- **Format**: `0x11 [ADDRESS_HIGH] [ADDRESS_LOW]`

**Address Encoding**:
```
Buffer offset = (row * 80) + col
Byte 0 = (offset >> 8) & 0xFF
Byte 1 = offset & 0xFF

For (row=0, col=0): 0x00 0x00
For (row=0, col=20): 0x00 0x14
For (row=1, col=0): 0x00 0x50
```

**Zig Implementation**:
```zig
pub const Address = struct {
    row: u8,
    col: u8,
    
    pub fn from_bytes(bytes: [2]u8) Address {
        const combined = (@as(u16, bytes[0]) << 8) | bytes[1];
        return Address{
            .row = @truncate(combined / 80),
            .col = @truncate(combined % 80),
        };
    }
    
    pub fn to_bytes(self: Address) [2]u8 {
        const combined: u16 = (self.row * 80) + self.col;
        return .{
            @truncate(combined >> 8),
            @truncate(combined & 0xFF),
        };
    }
};
```

### Start Field (0x1D)

Defines a field boundary with attributes.

- **Hex**: `0x1D`
- **Parameters**: 1-byte field attribute
- **Format**: `0x1D [ATTRIBUTE]`

**Field Attribute Byte Format**:
```
Bit 7: Protected (1 = field is protected)
Bit 6: Numeric (1 = numeric-only input)
Bit 5: Hidden (1 = don't display characters)
Bit 4: Intensified (1 = bright/bold display)
Bit 3: Modified (set by terminal when field changed)
Bits 2-0: Reserved (must be 0)

Example: 0xC0 (binary 11000000) = protected + intensified
```

**Zig Struct**:
```zig
pub const FieldAttribute = packed struct {
    protected: bool = false,
    numeric: bool = false,
    hidden: bool = false,
    intensified: bool = false,
    modified: bool = false,
    reserved: u3 = 0,
};
```

**Examples**:
- `0x00` - Unprotected, normal (user input field)
- `0x20` - Unprotected, hidden (password field)
- `0xC0` - Protected, intensified (display label)
- `0xC4` - Protected, intensified, numeric

### Set Attribute (0x28)

Sets display attributes for subsequent characters (future enhancement).

- **Hex**: `0x28`
- **Parameters**: 1-byte attribute type, 1-byte value
- **Status**: Defined but not yet implemented in zig-3270

### Insert Cursor (0x13)

Positions the cursor at a specific location.

- **Hex**: `0x13`
- **Parameters**: None (uses current buffer address)
- **Usage**: Highlight where user should input

### Program Tab (0x05)

Moves to next field during write operation.

- **Hex**: `0x05`
- **Usage**: Skip to next field boundary instead of writing

### Erase Unprotected (0x12)

Clears all unprotected fields.

- **Hex**: `0x12`
- **Usage**: Reset user input areas for new data entry

### Graphic Escape (0x08)

Introduces extended graphics (future enhancement).

- **Hex**: `0x08`
- **Status**: Defined but not implemented

---

## Write Control Character (WCC)

The byte following a Write/Erase Write command controls keyboard behavior.

### WCC Byte Format

```
Bit 7: Keyboard Restore (1 = re-enable keyboard)
Bit 6: Alarm (1 = sound alarm)
Bit 5: Reset Modified Flags (1 = clear field modified bits)
Bit 4: Reserved
Bit 3: Reserved
Bit 2: Reserved
Bit 1: Reset Cursor (1 = home cursor)
Bit 0: Reserved
```

### Common WCC Values

- `0x00` - No special action (typical for most writes)
- `0x40` - Restore keyboard (allow input)
- `0x82` - Restore + reset cursor
- `0xC0` - Restore + reset modified flags
- `0xE2` - Full reset (all flags)

---

## Attention Identifiers (AIDs)

When user presses a key, a "Read Modified" response includes an AID code.

### Standard AIDs

| AID | Hex | Key | Meaning |
|-----|-----|-----|---------|
| No AID | 0x60 | (no key) | No AID sent |
| Enter | 0x7D | Enter | Normal data submission |
| Clear | 0x6D | Clear | Clear screen request |
| PA1 | 0x6C | Program Assist 1 | Function key PA1 |
| PA2 | 0x6E | Program Assist 2 | Function key PA2 |
| PA3 | 0x6B | Program Assist 3 | Function key PA3 |
| PF1 | 0xF1 | Function Key 1 | Function key PF1 |
| PF2 | 0xF2 | Function Key 2 | Function key PF2 |
| PF3 | 0xF3 | Function Key 3 | Function key PF3 |
| ... | ... | ... | (through PF24) |
| PF24 | 0xF8 | Function Key 24 | Function key PF24 |

### User Response Format

```
[AID Byte] [Cursor Address (2 bytes)] [Modified Fields...]
```

**Example: User presses Enter in first field**
```
0x7D                // AID: Enter
0x00 0x00           // Cursor address (row 0, col 0)
0x00 0x00           // Field 1 address
0x00                // Field 1 length (no data if empty)
// Additional fields follow...
```

---

## Example Conversations

### Example 1: Simple Login Screen

**Server → Terminal**:
```
0x05 0x00                   // Erase Write
0x11 0x00 0x00              // Set Buffer Address (0,0)
'U' 's' 'e' 'r' 'i' 'd' ':' // Text data
0x1D 0x00                   // Start Field (unprotected)
0x11 0x00 0x1D              // Set Buffer Address (0, 29)
'P' 'a' 's' 's' 'w' 'o' 'r' 'd' ':' // Text
0x1D 0x20                   // Start Field (unprotected, hidden)
```

**User enters "ADUSER" in userid field and "SECRET" in password**

**Terminal → Server** (Read Modified):
```
0x06                        // Read Modified command
0x7D                        // AID: Enter
0x00 0x00                   // Cursor address
0x00 0x08                   // Field 1: address 0,8
6                           // Length: 6
'A' 'D' 'U' 'S' 'E' 'R'     // Userid data
0x00 0x27                   // Field 2: address 0,39
6                           // Length: 6
'S' 'E' 'C' 'R' 'E' 'T'     // Password data
```

### Example 2: Menu Selection

**Server → Terminal**:
```
0x05 0x00                   // Erase Write
0x11 0x00 0x00              // Position (0,0)
'1' '. ' 'C' 'r' 'e' 'a' 't' 'e' ' ' 'A' 'c' 'c' 'o' 'u' 'n' 't'
0x11 0x00 0x50              // Position (1,0)
'2' '. ' 'M' 'o' 'd' 'i' 'f' 'y' ' ' 'A' 'c' 'c' 'o' 'u' 'n' 't'
0x11 0x00 0xA0              // Position (2,0)
'E' 'n' 't' 'e' 'r' ' ' 's' 'e' 'l' 'e' 'c' 't' 'i' 'o' 'n' ':'
0x1D 0x00                   // Start Field (unprotected)
0x11 0x01 0x34              // Position (1, 52)
```

**User enters "1"**

**Terminal → Server**:
```
0x06                        // Read Modified
0x7D                        // AID: Enter
0x01 0x34                   // Cursor address
0x01 0x34                   // Field address
1                           // Length
'1'                         // User input
```

---

## Protocol State Machine

### Connection Lifecycle

```
┌─────────────────────────┐
│  TCP Connection         │ Connect to port 3270
└────────────┬────────────┘
             │
┌────────────▼────────────┐
│  Telnet Negotiation     │ Exchange capabilities (WILL, DO, etc.)
└────────────┬────────────┘
             │
┌────────────▼────────────┐
│  Receive Initial Screen │ Erase Write or Write command
└────────────┬────────────┘
             │
┌────────────▼────────────────────┐
│  Display Loop                   │
│  1. Display screen to user      │
│  2. Wait for keyboard input     │
│  3. Send Read Modified (AID +   │
│     modified field data)        │
│  4. Receive updated screen      │
│  5. Repeat                      │
└─────────────────────────────────┘
```

---

## Implementation Details in zig-3270

### Protocol Constants (protocol.zig)

```zig
pub const CommandCode = enum(u8) {
    write = 0x01,
    read_modified = 0x06,
    erase_write = 0x05,
    // ...
};

pub const OrderCode = enum(u8) {
    set_buffer_address = 0x11,
    start_field = 0x1D,
    // ...
};

pub const FieldAttribute = packed struct {
    protected: bool,
    numeric: bool,
    hidden: bool,
    intensified: bool,
    modified: bool,
    reserved: u3,
};
```

### Parsing (parser.zig, stream_parser.zig)

Inbound data stream → parsed commands/orders/data

```zig
// Extract command code
const cmd = data[0];

// Parse order codes in data stream
while (pos < data.len) {
    const order = data[pos];
    switch (order) {
        0x11 => {
            // Set Buffer Address: extract 2-byte address
            const addr = Address.from_bytes(data[pos+1..pos+3]);
            pos += 3;
        },
        0x1D => {
            // Start Field: extract attribute byte
            const attr = data[pos+1];
            pos += 2;
        },
        else => {
            // Regular character data
            buffer[cursor] = order;
            cursor += 1;
            pos += 1;
        },
    }
}
```

### Command Formatting (command.zig)

Outbound responses → formatted data stream

```zig
// Build Read Modified response
var response = ArrayList(u8).init(allocator);

try response.append(0x06);  // Read Modified command
try response.append(aid);   // AID code
try response.appendSlice(&Address.to_bytes(...));  // Cursor
// Add modified field data...
```

---

## Testing Protocol Implementation

### Unit Tests (protocol.zig)

```zig
test "address from bytes" {
    const addr = Address.from_bytes(.{ 0x00, 0x14 });
    try std.testing.expectEqual(@as(u8, 0), addr.row);
    try std.testing.expectEqual(@as(u8, 20), addr.col);
}

test "field attribute" {
    var attr: FieldAttribute = .{};
    attr.protected = true;
    attr.intensified = true;
    try std.testing.expect(attr.protected);
}
```

### Integration Tests

Test parser + executor + screen together:

```zig
// Simulate server sending Write with field
const cmd_data = [_]u8{
    0x01, 0x00,                 // Write, WCC
    0x1D, 0x00,                 // Start Field (unprotected)
    'H', 'e', 'l', 'l', 'o'
};

// Parse and execute
try executor.execute(&scr, &cmd_data);

// Verify screen updated
try std.testing.expectEqual('H', try scr.read_char(0, 0));
```

---

## Related Standards

- **RFC 854**: Telnet Protocol
- **RFC 2355**: TN3270 Enhancements (Structured Fields)
- **IBM 3270 Information Display System**: Original specification
- **EBCDIC**: Extended Binary Coded Decimal Interchange Code

---

## Glossary

- **AID**: Attention Identifier—key press indicator sent to host
- **CICS**: Customer Information Control System (mainframe transaction system)
- **EBCDIC**: IBM mainframe character encoding (zig-3270 uses ASCII for now)
- **IMS**: Information Management System (mainframe database)
- **Order Code**: Instruction in 3270 data stream
- **RMF**: Read Modified Fields—request only changed data from terminal
- **TSO**: Time Sharing Option (interactive mainframe)
- **WCC**: Write Control Character—controls keyboard behavior
- **3270**: IBM terminal protocol (commonly called "green screen")
- **TN3270**: 3270 protocol over Telnet/TCP

---

## Structured Fields (v0.8.0 Enhancement)

Write Structured Field (WSF) commands enable advanced protocol features beyond basic 3270.

### WSF Command Format

```
0xF3 [Length] [Type] [Data...]
```

- **0xF3**: WSF command code
- **Length**: Total length of WSF data (2 bytes, big-endian)
- **Type**: Field type (determines data format)
- **Data**: Type-specific parameters

### Supported Structured Field Types (v0.8.0)

| Type | Hex | Purpose | Example |
|------|-----|---------|---------|
| Color | 0x85 | Set display colors | Red text, blue background |
| 3270-DS | 0x82 | Character set | Alternate fonts, graphics |
| Seal/Unseal | 0x87 | Field protection | Lock/unlock fields dynamically |
| Extended Highlighting | 0x41 | Text decoration | Underscore, reverse video, blink |
| Transparency | 0x80 | Overlay mode | Transparent background fields |
| Load Programmed Symbols | 0x84 | Custom characters | User-defined glyphs |
| Field Outlining | 0x86 | Border style | Box, underline, overstrike |
| Null | 0x00 | No operation | Padding/reserved |

### Example: Color Attribute

**Send red text on black background:**
```
0xF3                    // WSF command
0x00 0x08               // Length: 8 bytes
0x85                    // Type: Color
0x00                    // Class: foreground
0xC1                    // Color: red
0x00 0x02               // Background color: black
0x00 0x00               // Reserved
```

### Example: Seal/Unseal (Dynamic Field Protection)

**Lock field after user input:**
```
0xF3                    // WSF command
0x00 0x04               // Length: 4 bytes
0x87                    // Type: Seal/Unseal
0x00 0x10               // Address of field to lock
0x01                    // Action: seal (lock)
```

### Supported in zig-3270

See `src/structured_fields.zig` for complete implementation:
- Full type enumeration (20+ types)
- Parser for each field type
- Serialization with error handling
- Integration with command execution

---

## Error Codes & Recovery

### Protocol Error Responses

When a terminal violates protocol requirements, the server may:

1. **Ignore the error** (most common)
2. **Send error code via WSF**
3. **Disconnect or reset**

### Common Error Conditions

| Condition | Typical Response | Recovery |
|-----------|-----------------|----------|
| Invalid AID (0xFF) | Ignored | Resend with valid AID |
| Field address out of bounds | Screen position resets to 0,0 | Re-sync with Read Buffer |
| Invalid field attribute | Treated as 0x00 (unprotected) | Verify field attributes |
| Corrupted data stream | Data interpreted incorrectly | Perform Read Buffer to re-sync |
| Buffer overflow | Data truncated at 1920 bytes | Send multiple commands |
| Telnet timeout (>30s idle) | Connection reset | Reconnect |

### Error Recovery in zig-3270

The parser includes automatic recovery:

```zig
// In parser.zig - ErrorRecovery struct
- Frame boundary detection (sync on 0xF3 or command codes)
- Command resynchronization after corruption
- CRC validation for critical fields
- Safe degradation mode (skip corrupted bytes, continue parsing)
```

---

## Complete Command Code Reference

### All 256 Command Codes

**Defined TN3270 Commands**:

| Code | Name | Parameters | Response | Status |
|------|------|-----------|----------|--------|
| 0x00 | No Operation | - | - | Defined |
| 0x01 | Write | WCC, orders, data | None | Implemented |
| 0x02 | Read Buffer | - | Screen buffer | Implemented |
| 0x03 | Erase Unprotected | - | None | Implemented |
| 0x05 | Erase Write | WCC, orders, data | None | Implemented |
| 0x06 | Read Modified | - | AID, cursor, fields | Implemented |
| 0x07 | Read Modified All | - | AID, cursor, all fields | Implemented |
| 0x0D | Erase Write Alt | WCC, orders, data | None | Implemented |
| 0x0E | Read All | - | Entire screen + attrs | Implemented |
| 0x0F | Selective Reset | - | Modified | Implemented |
| 0x10 | Query | - | Response | Implemented |
| 0x13 | Read Screen Reverse | - | Screen data | Optional |
| 0x39 | Write Structured Field | Type, length, data | None | Implemented |
| 0xF3 | WSF (alternative) | Type, length, data | None | Implemented |

**Undefined codes (0x04, 0x08, 0x09-0x0C, etc.)**: Treated as no-op or error

### Command Implementation in zig-3270

See `src/command.zig` for parsing and `src/executor.zig` for execution.

---

## Complete Order Code Reference

### All Order Codes (in data stream)

| Code | Name | Parameters | Purpose | Status |
|------|------|-----------|---------|--------|
| 0x05 | Program Tab | - | Move to next field | Implemented |
| 0x08 | Graphic Escape | Graphics data | Extended graphics | Optional |
| 0x0D | Duplicate | - | Repeat last char | Optional |
| 0x12 | Erase Unprotected | - | Clear unprotected | Implemented |
| 0x13 | Insert Cursor | - | Set cursor position | Implemented |
| 0x1D | Start Field | Attribute | Define field boundary | Implemented |
| 0x28 | Set Attribute | Type, value | Set char attributes | Implemented |
| 0x29 | Start Field Extended | Type, length, data | Extended field params | Optional |
| 0x2A | Modify Field | Address, attr | Change field attribute | Optional |
| 0x2C | Repeat to Address | Address | Fill with spaces | Optional |
| 0x3C | Write to Address | Address, data | Write at specific addr | Implemented |
| 0x11 | Set Buffer Address | 2-byte address | Position cursor | Implemented |

### Hex Stream Decoding Guide

**Given hex stream, identify order codes:**

```
01 00            // Write, WCC=0 (normal)
  11 00 08       // Set address 0,8
  48 65 6c 6c 6f // "Hello" (ASCII/EBCDIC data)
  1d c0          // Start Field, attribute 0xC0 (protected+intense)
  50 61 73 73    // "Pass" (more data)

Interpretation:
- Command: Write
- Position: 0,8
- Display: "Hello"
- Then: Protected, bright field
- Then: "Pass" as data
```

---

## Keyboard & AID Mapping (Complete Table)

### All Standard AIDs (Attention Identifiers)

| AID | Hex | Keyboard | Function | CICS | Notes |
|-----|-----|----------|----------|------|-------|
| (None) | 0x60 | (no key) | No AID | - | Timeout or internal |
| PA1 | 0x6C | PA1 key | Program Assist 1 | EOCES | Special function |
| PA2 | 0x6E | PA2 key | Program Assist 2 | EOCES | Special function |
| PA3 | 0x6B | PA3 key | Program Assist 3 | EOCES | Special function |
| Clear | 0x6D | CLR key | Clear screen | CLEARN | Clears input |
| Enter | 0x7D | Enter/Return | Submit data | ENTER | Standard submit |
| PF1 | 0xF1 | F1 key | Function 1 | PF1 | Programmable (Zig: Alt+1) |
| PF2 | 0xF2 | F2 key | Function 2 | PF2 | Programmable (Zig: Alt+2) |
| PF3 | 0xF3 | F3 key | Function 3 | PF3 | Programmable (Zig: Alt+3) |
| PF4 | 0xF4 | F4 key | Function 4 | PF4 | Programmable (Zig: Alt+4) |
| ... | ... | ... | ... | ... | ... |
| PF24 | 0xF8 | F24 key | Function 24 | PF24 | Programmable (Zig: Alt+8) |

### zig-3270 AID Mapping (keyboard_config.zig)

```zig
// Default key bindings
.{ "enter", AID.enter, 0x7D },
.{ "clear", AID.clear, 0x6D },
.{ "pa1", AID.pa1, 0x6C },
.{ "pa2", AID.pa2, 0x6E },
.{ "pa3", AID.pa3, 0x6B },
.{ "pf1", AID.pf1, 0xF1 },  // Alt+1
.{ "pf2", AID.pf2, 0xF2 },  // Alt+2
// ... through pf24
```

### Session Negotiation

**Telnet negotiation sequence:**

```
Client → Server:
  WILL TRANSMIT-BINARY (0xFF 0xFB 0x00)
  WILL SUPPRESS-GA (0xFF 0xFB 0x03)

Server → Client:
  DO TRANSMIT-BINARY (0xFF 0xFD 0x00)
  DO SUPPRESS-GA (0xFF 0xFD 0x03)
  (Then 3270 data stream begins)
```

zig-3270 handles this automatically in `telnet_enhanced.zig`.

---

## Known Implementation Limits

| Feature | Limit | Status |
|---------|-------|--------|
| Screen size | 24×80 (1920 chars) | Fixed |
| Fields per screen | ~100 | Tested |
| Max field size | 1920 bytes | Limited by buffer |
| Simultaneous connections | 1 (per process) | By design |
| WSF types supported | 20+ | v0.8.0 |
| Character encoding | ASCII (EBCDIC available) | v0.5.1+ |
| LU3 printing | Full support | v0.8.0 |
| Graphics rendering | Basic (SVG) | v0.8.0 |

---

## RFC References

### Primary Standards

- **RFC 854**: Telnet Protocol (foundational)
- **RFC 1576**: TN3270 - Telnet 3270 Profile (defines TN3270)
- **RFC 1647**: TN3270 Extensions for LU Name and Device Type (advanced)
- **RFC 2355**: TN3270 Enhancements (Structured Fields)

### Related

- **IBM 3270 Information Display System**: Original hardware spec
- **EBCDIC (IBM Code Page 037)**: Character encoding standard
- **TELNET Protocol Negotiation**: RFC 855-861 (telnet options)

---

## Troubleshooting Protocol Issues

### Symptom: Screen shows garbled text

**Likely causes**:
1. Character encoding mismatch (ASCII vs EBCDIC)
2. Missing Start Field (0x1D) order code
3. Buffer address miscalculation

**Resolution**:
```bash
# Use diagnostic tool
zig-3270 diag protocol

# Or enable protocol logging
export ZIG_3270_LOG=debug
```

### Symptom: Fields won't accept input

**Likely causes**:
1. Field marked protected (0x80 in attribute)
2. Keyboard not restored (WCC byte missing 0x40)
3. Modified flag bit is set

**Resolution**:
1. Check field attributes
2. Verify WCC=0x40 in Write/Erase Write
3. Use Selective Reset to clear modified flags

### Symptom: Connection drops after 30s idle

**Likely causes**:
1. Telnet keep-alive timeout
2. Network firewall inactivity timer
3. Server session timeout

**Resolution**:
```bash
# Enable keep-alive in zig-3270 config
connection_timeout_ms: 60000
keep_alive_interval_ms: 30000
```

---

## Performance Notes

- **Parser throughput**: 500+ MB/s (single-pass)
- **Field lookup**: O(1) via hash cache
- **Screen update**: <1ms typical
- **Network latency**: Dominates (usually 50-500ms)

Optimization details in `docs/PERFORMANCE.md`.

---

## Future Enhancements

- [x] ~~EBCDIC encoding/decoding~~ (v0.5.1)
- [x] ~~Extended Structured Fields~~ (v0.8.0)
- [x] ~~LU3 printer support~~ (v0.8.0)
- [x] ~~Graphics support~~ (v0.8.0)
- [ ] Advanced keyboard macros
- [ ] Session persistence (state save/restore)
- [ ] Binary data support (BLU - Binary Large Unit)
- [ ] TLS/SSL encryption (secure TN3270)
- [ ] EBCDIC variant code pages (not just 037)

---

**Last Updated**: Dec 22, 2024  
**Protocol Version**: TN3270 (RFC 1576, RFC 2355)  
**Implementation Status**: Complete (v0.8.0), with v0.8.1 enhancements  
**Total Lines**: 1,000+ (comprehensive reference)
