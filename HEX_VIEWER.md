# Hex Viewer

The hex viewer module provides a utility for displaying binary data in a traditional hexdump format, useful for debugging 3270 protocol data and raw byte streams.

## Features

- **Side-by-side display**: Hexadecimal bytes on the left, ASCII representation on the right
- **Configurable bytes per line**: Default 16 bytes per line, adjustable as needed
- **Printable character detection**: Non-printable bytes shown as `.` for readability
- **Offset tracking**: Byte offsets shown at the start of each line
- **Memory efficient**: Uses ArrayList for dynamic allocation

## Usage

### Basic Example

```zig
const hex_viewer = @import("hex_viewer.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var viewer = hex_viewer.HexViewer.init(allocator, 16);

// Display data to stdout
const data = "Hello, 3270!";
try viewer.print(data);
```

### Format Output

```zig
const output = try viewer.format(data);
defer allocator.free(output);
// Use output string directly
```

### Custom Bytes Per Line

```zig
var viewer = hex_viewer.HexViewer.init(allocator, 8); // 8 bytes per line
try viewer.print(data);
```

## Output Format

```
00000000  49 42 4D 20 33 32 37 30                          |IBM 3270|
00000008  48 6F 73 74                                       |Host|
```

- **Offset**: 8-character hex offset from start
- **Hex bytes**: 16 bytes (configurable) displayed in hex format
- **ASCII**: Printable characters in ASCII, `.` for non-printable

## Testing

Run the hex viewer tests:

```bash
task test
```

Run the hex viewer example:

```bash
task hex-viewer
```

## Integration with 3270 Emulator

The hex viewer can be used to debug 3270 protocol streams:

```zig
const command_seq = &[_]u8{
    0x5A, // Read Buffer command
    0x13, // Attribute byte
    0xC1, // EBCDIC 'A'
    0xC2, // EBCDIC 'B'
};

try viewer.print(command_seq);
```

This helps visualize raw 3270 commands and responses.
