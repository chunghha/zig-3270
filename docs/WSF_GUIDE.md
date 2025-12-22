# Structured Field Extensions (WSF) Guide

## Overview

Write Structured Field (WSF) support provides advanced 3270 terminal capabilities for data formatting, colors, fonts, and image support.

## Features

### 1. Data Stream Attributes

Control character appearance and behavior:

```zig
const attr = DataStreamAttribute{
    .attribute_type = .foreground_color,
    .value = 0x05, // Color code
};

var buffer: [2]u8 = undefined;
const len = try attr.to_buffer(&buffer);
```

**Available Attributes:**
- `default` (0x00) - Reset to defaults
- `foreground_color` (0x01) - Text color
- `background_color` (0x02) - Background color
- `intensity` (0x03) - Bright/dim text
- `blink` (0x04) - Blinking text
- `reverse` (0x05) - Reverse video
- `underline` (0x06) - Underlined text

### 2. Font Specifications

Define and negotiate font parameters:

```zig
const font = FontSpec{
    .font_id = 0x01,
    .code_page = 0x0437, // Code page 437
    .height = 16,
    .width = 8,
};
```

**Fields:**
- `font_id` - Font identifier
- `code_page` - Character encoding (e.g., 0x0437 for IBM437)
- `height` - Font height in pixels/points
- `width` - Font width in pixels/points

### 3. Color Palettes

Define custom color palettes with RGB entries:

```zig
var palette = ColorPalette.init(allocator, 0x01);
defer palette.deinit();

try palette.add_entry(0x00, 0xFF, 0xFF, 0xFF); // White
try palette.add_entry(0x01, 0x00, 0x00, 0x00); // Black
try palette.add_entry(0x02, 0xFF, 0x00, 0x00); // Red
```

**Color Entries:**
- `color_id` - Color reference ID
- `r`, `g`, `b` - RGB components (0-255)

### 4. Image Specifications

Support for embedded images and graphics:

```zig
const image = ImageSpec{
    .image_id = 0x01,
    .format = .rgb,
    .width = 640,
    .height = 480,
    .data_length = 921600, // 640×480×3 bytes
};
```

**Formats:**
- `monochrome` (0x00) - Single-bit images
- `rgb` (0x01) - Full RGB color
- `indexed` (0x02) - Palette-indexed images

## Structured Field Parsing

### Single Field Parsing

```zig
var allocator = std.mem.Allocator;
var parser = StructuredFieldParser.init(allocator);

var buffer: [6]u8 = .{ 0x0B, 0x00, 0x06, 0x01, 0x02, 0x03 };
const field = try parser.parse_field(&buffer);

if (field) |f| {
    if (f == .color_pair) {
        std.debug.print("Pair ID: {}\n", .{f.color_pair.pair_id});
    }
}
```

### Multiple Field Parsing

```zig
const fields = try parser.parse_fields(buffer);
defer {
    for (fields.items) |*f| {
        f.deinit(allocator);
    }
    fields.deinit();
}

for (fields.items) |field| {
    switch (field) {
        .color_pair => |pair| std.debug.print("Color pair {}\n", .{pair.pair_id}),
        .font => |font| std.debug.print("Font {}\n", .{font.font_id}),
        else => {},
    }
}
```

## Integration with Commands

WSF commands are sent as part of Write and Write-Erase commands:

```zig
// Create an erase command with WSF field
const cmd = Command{
    .erase_write = .{
        .keyboard_restore = false,
        .structured_fields = true, // Enable WSF parsing
    },
};
```

## Error Handling

WSF parsing can fail with the following errors:

- `IncompleteField` - Not enough data for complete field
- `InvalidColorPair` - Malformed color pair definition
- `InvalidExtendedAttribute` - Invalid attribute type
- `InvalidValidationRule` - Unknown validation rule
- `InvalidSealUnseal` - Invalid seal/unseal operation
- `InvalidTransparency` - Invalid transparency mode
- `InvalidCharacterSet` - Unknown character set

```zig
if (try parser.parse_field(buffer)) |field| {
    // Process field
} else {
    std.debug.print("Failed to parse WSF field\n", .{});
}
```

## Performance Considerations

1. **Buffer Allocation**: Use stack-allocated buffers for fields < 256 bytes
2. **Parser Reuse**: Create parser once, use for multiple fields
3. **Field Deallocation**: Call `deinit()` on unknown fields to prevent leaks
4. **Stream Processing**: Parse fields incrementally for large data streams

## Compatibility

WSF support is compatible with:
- TN3270 protocol specification
- TN3270E extended features
- IBM 3270 display terminals
- Most modern TN3270 applications

## Examples

### Display with Custom Colors

```zig
// Define color palette
var palette = ColorPalette.init(allocator, 0x01);
try palette.add_entry(0x00, 0xFF, 0xFF, 0xFF); // White
try palette.add_entry(0x01, 0xFF, 0x00, 0x00); // Red

// Create colored text attribute
const attr = DataStreamAttribute{
    .attribute_type = .foreground_color,
    .value = 0x01, // Reference color 1 (red)
};
```

### Custom Font Loading

```zig
const font = FontSpec{
    .font_id = 0x02,
    .code_page = 0x0850, // multilingual
    .height = 14,
    .width = 7,
};

// Use in WSF command
```

### Image Embedding

```zig
const image = ImageSpec{
    .image_id = 0x01,
    .format = .indexed,
    .width = 256,
    .height = 256,
    .data_length = 65536, // 256×256 palette-indexed
};
```

## See Also

- `structured_fields.zig` - Core implementation
- TN3270 Protocol Specification (RFC 1646)
- IBM 3270 Information Display System documentation
