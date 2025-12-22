const std = @import("std");

/// Graphics Protocol Support for TN3270
/// Implements basic GDDM (Graphical Data Display Manager) subset
/// for vector and raster graphics handling
/// Graphics command types
pub const GraphicsCommand = enum(u8) {
    begin_graphics = 0x00,
    end_graphics = 0x01,
    draw_line = 0x02,
    draw_rectangle = 0x03,
    draw_circle = 0x04,
    draw_polygon = 0x05,
    draw_text = 0x06,
    set_color = 0x07,
    set_pen = 0x08,
    set_fill = 0x09,
    clear_area = 0x0A,
    raster_image = 0x0B,
    _,

    pub fn to_byte(self: GraphicsCommand) u8 {
        return @intFromEnum(self);
    }

    pub fn from_byte(byte: u8) ?GraphicsCommand {
        return std.meta.intToEnum(GraphicsCommand, byte) catch null;
    }
};

/// Graphics data stream header
pub const GraphicsHeader = struct {
    command: GraphicsCommand,
    data_length: u16,
    flags: u8 = 0,

    const MIN_SIZE = 3; // cmd + length (2 bytes)

    pub fn from_buffer(buffer: []const u8) ?GraphicsHeader {
        if (buffer.len < MIN_SIZE) return null;

        const length = (@as(u16, buffer[1]) << 8) | buffer[2];
        const cmd = GraphicsCommand.from_byte(buffer[0]) orelse return null;

        return .{
            .command = cmd,
            .data_length = length,
            .flags = if (buffer.len > 3) buffer[3] else 0,
        };
    }

    pub fn to_buffer(self: GraphicsHeader, buffer: []u8) !usize {
        if (buffer.len < MIN_SIZE) return error.BufferTooSmall;

        buffer[0] = self.command.to_byte();
        buffer[1] = @intCast((self.data_length >> 8) & 0xFF);
        buffer[2] = @intCast(self.data_length & 0xFF);

        return MIN_SIZE;
    }
};

/// 2D Point in graphics coordinate space
pub const Point = struct {
    x: i16,
    y: i16,

    pub fn from_buffer(buffer: []const u8) ?Point {
        if (buffer.len < 4) return null;
        return .{
            .x = @bitCast(@as(u16, (@as(u16, buffer[0]) << 8) | buffer[1])),
            .y = @bitCast(@as(u16, (@as(u16, buffer[2]) << 8) | buffer[3])),
        };
    }
};

/// Bounding rectangle
pub const Rectangle = struct {
    left: i16,
    top: i16,
    right: i16,
    bottom: i16,

    pub fn from_buffer(buffer: []const u8) ?Rectangle {
        if (buffer.len < 8) return null;
        return .{
            .left = @bitCast(@as(u16, (@as(u16, buffer[0]) << 8) | buffer[1])),
            .top = @bitCast(@as(u16, (@as(u16, buffer[2]) << 8) | buffer[3])),
            .right = @bitCast(@as(u16, (@as(u16, buffer[4]) << 8) | buffer[5])),
            .bottom = @bitCast(@as(u16, (@as(u16, buffer[6]) << 8) | buffer[7])),
        };
    }

    pub fn width(self: Rectangle) i32 {
        return @as(i32, self.right) - @as(i32, self.left);
    }

    pub fn height(self: Rectangle) i32 {
        return @as(i32, self.bottom) - @as(i32, self.top);
    }
};

/// RGB Color specification
pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,

    pub fn from_buffer(buffer: []const u8) ?Color {
        if (buffer.len < 3) return null;
        return .{
            .red = buffer[0],
            .green = buffer[1],
            .blue = buffer[2],
        };
    }

    pub fn to_hex_string(self: Color, buffer: []u8) !usize {
        if (buffer.len < 7) return error.BufferTooSmall;
        const chars = "0123456789ABCDEF";
        buffer[0] = '#';
        buffer[1] = chars[self.red >> 4];
        buffer[2] = chars[self.red & 0x0F];
        buffer[3] = chars[self.green >> 4];
        buffer[4] = chars[self.green & 0x0F];
        buffer[5] = chars[self.blue >> 4];
        buffer[6] = chars[self.blue & 0x0F];
        return 7;
    }
};

/// Pen style for drawing
pub const PenStyle = struct {
    width: u8,
    style: enum(u8) {
        solid = 0x00,
        dashed = 0x01,
        dotted = 0x02,
        dash_dot = 0x03,
    } = .solid,

    pub fn from_buffer(buffer: []const u8) ?PenStyle {
        if (buffer.len < 2) return null;

        const s = switch (buffer[1]) {
            0x00 => @as(@TypeOf(@as(PenStyle, undefined).style), .solid),
            0x01 => .dashed,
            0x02 => .dotted,
            0x03 => .dash_dot,
            else => return null,
        };

        return .{
            .width = buffer[0],
            .style = s,
        };
    }
};

/// Fill pattern specification
pub const FillPattern = struct {
    pattern_id: enum(u8) {
        solid = 0x00,
        hollow = 0x01,
        hatched = 0x02,
        cross_hatched = 0x03,
    } = .solid,
    foreground_color: u8 = 0,
    background_color: u8 = 0,

    pub fn from_buffer(buffer: []const u8) ?FillPattern {
        if (buffer.len < 3) return null;

        const p = switch (buffer[0]) {
            0x00 => @as(@TypeOf(@as(FillPattern, undefined).pattern_id), .solid),
            0x01 => .hollow,
            0x02 => .hatched,
            0x03 => .cross_hatched,
            else => return null,
        };

        return .{
            .pattern_id = p,
            .foreground_color = buffer[1],
            .background_color = buffer[2],
        };
    }
};

/// Graphics object (line, rectangle, circle, etc.)
pub const GraphicsObject = union(enum) {
    begin: void,
    end: void,
    line: struct {
        start: Point,
        end: Point,
    },
    rectangle: struct {
        bounds: Rectangle,
    },
    circle: struct {
        center: Point,
        radius: u16,
    },
    polygon: struct {
        point_count: u16,
        points: []const Point,
    },
    text: struct {
        position: Point,
        text: []const u8,
    },
    color: Color,
    pen: PenStyle,
    fill: FillPattern,
    clear: Rectangle,
    raster: struct {
        bounds: Rectangle,
        format: enum(u8) {
            monochrome = 0x00,
            rgb = 0x01,
            gray = 0x02,
        } = .rgb,
        data: []const u8,
    },
    unknown: struct {
        command: GraphicsCommand,
        data: []const u8,
    },

    pub fn deinit(self: *GraphicsObject, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .polygon => |p| {
                allocator.free(p.points);
            },
            .text => |t| {
                allocator.free(t.text);
            },
            .raster => |r| {
                allocator.free(r.data);
            },
            .unknown => |u| {
                allocator.free(u.data);
            },
            else => {},
        }
    }
};

/// Graphics stream parser
pub const GraphicsParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GraphicsParser {
        return .{ .allocator = allocator };
    }

    /// Parse a single graphics object from buffer
    pub fn parse_object(self: GraphicsParser, buffer: []const u8) !?GraphicsObject {
        const header = GraphicsHeader.from_buffer(buffer) orelse return null;

        if (buffer.len < header.data_length) return error.IncompleteData;

        const data = if (buffer.len > 3) buffer[3..header.data_length] else &.{};

        return switch (header.command) {
            .begin_graphics => .{ .begin = {} },
            .end_graphics => .{ .end = {} },
            .draw_line => blk: {
                if (Point.from_buffer(data)) |start| {
                    if (data.len >= 8) {
                        if (Point.from_buffer(data[4..])) |end| {
                            break :blk .{
                                .line = .{
                                    .start = start,
                                    .end = end,
                                },
                            };
                        }
                    }
                }
                return error.InvalidLineData;
            },
            .draw_rectangle => blk: {
                if (Rectangle.from_buffer(data)) |bounds| {
                    break :blk .{
                        .rectangle = .{ .bounds = bounds },
                    };
                }
                return error.InvalidRectangleData;
            },
            .draw_circle => blk: {
                if (Point.from_buffer(data)) |center| {
                    if (data.len >= 6) {
                        const radius = (@as(u16, data[4]) << 8) | data[5];
                        break :blk .{
                            .circle = .{
                                .center = center,
                                .radius = radius,
                            },
                        };
                    }
                }
                return error.InvalidCircleData;
            },
            .set_color => blk: {
                if (Color.from_buffer(data)) |color| {
                    break :blk .{ .color = color };
                }
                return error.InvalidColorData;
            },
            .set_pen => blk: {
                if (PenStyle.from_buffer(data)) |pen| {
                    break :blk .{ .pen = pen };
                }
                return error.InvalidPenData;
            },
            .set_fill => blk: {
                if (FillPattern.from_buffer(data)) |fill| {
                    break :blk .{ .fill = fill };
                }
                return error.InvalidFillData;
            },
            .clear_area => blk: {
                if (Rectangle.from_buffer(data)) |bounds| {
                    break :blk .{
                        .clear = bounds,
                    };
                }
                return error.InvalidClearData;
            },
            else => blk: {
                const obj_data = try self.allocator.dupe(u8, data);
                break :blk .{
                    .unknown = .{
                        .command = header.command,
                        .data = obj_data,
                    },
                };
            },
        };
    }

    /// Detect if buffer contains graphics data
    pub fn is_graphics_stream(self: GraphicsParser, buffer: []const u8) bool {
        if (buffer.len < 1) return false;

        const cmd = GraphicsCommand.from_byte(buffer[0]) orelse return false;
        return cmd == .begin_graphics or cmd == .end_graphics;
    }

    /// Convert graphics object to SVG representation
    pub fn to_svg_element(self: GraphicsParser, obj: GraphicsObject, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        var result = std.ArrayList(u8).init(allocator);
        var writer = result.writer();

        switch (obj) {
            .rectangle => |r| {
                try writer.print(
                    "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" />",
                    .{ r.bounds.left, r.bounds.top, r.bounds.width(), r.bounds.height() },
                );
            },
            .circle => |c| {
                try writer.print(
                    "<circle cx=\"{}\" cy=\"{}\" r=\"{}\" />",
                    .{ c.center.x, c.center.y, c.radius },
                );
            },
            .line => |l| {
                try writer.print(
                    "<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" />",
                    .{ l.start.x, l.start.y, l.end.x, l.end.y },
                );
            },
            else => {
                try writer.writeAll("<!-- unsupported graphics object -->");
            },
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "graphics command enum" {
    const cmd = GraphicsCommand.draw_line;
    try std.testing.expectEqual(@as(u8, 0x02), cmd.to_byte());

    const cmd2 = GraphicsCommand.from_byte(0x02);
    try std.testing.expect(cmd2 != null);
    if (cmd2) |c| {
        try std.testing.expectEqual(GraphicsCommand.draw_line, c);
    }
}

test "graphics header from buffer" {
    var buffer: [4]u8 = .{ 0x02, 0x01, 0x00, 0x42 };
    const header = GraphicsHeader.from_buffer(&buffer);

    try std.testing.expect(header != null);
    if (header) |h| {
        try std.testing.expectEqual(GraphicsCommand.draw_line, h.command);
        try std.testing.expectEqual(@as(u16, 0x0100), h.data_length);
    }
}

test "graphics header to buffer" {
    var buffer: [3]u8 = undefined;
    const header = GraphicsHeader{
        .command = .draw_line,
        .data_length = 8,
    };

    const size = try header.to_buffer(&buffer);
    try std.testing.expectEqual(@as(usize, 3), size);
    try std.testing.expectEqual(@as(u8, 0x02), buffer[0]);
}

test "point from buffer" {
    var buffer: [4]u8 = .{ 0x00, 0x10, 0x00, 0x20 };
    const point = Point.from_buffer(&buffer);

    try std.testing.expect(point != null);
    if (point) |p| {
        try std.testing.expectEqual(@as(i16, 0x0010), p.x);
        try std.testing.expectEqual(@as(i16, 0x0020), p.y);
    }
}

test "rectangle from buffer" {
    var buffer: [8]u8 = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00, 0x64 };
    const rect = Rectangle.from_buffer(&buffer);

    try std.testing.expect(rect != null);
    if (rect) |r| {
        try std.testing.expectEqual(@as(i16, 0), r.left);
        try std.testing.expectEqual(@as(i32, 100), r.width());
        try std.testing.expectEqual(@as(i32, 100), r.height());
    }
}

test "color from buffer" {
    var buffer: [3]u8 = .{ 0xFF, 0x80, 0x00 };
    const color = Color.from_buffer(&buffer);

    try std.testing.expect(color != null);
    if (color) |c| {
        try std.testing.expectEqual(@as(u8, 0xFF), c.red);
        try std.testing.expectEqual(@as(u8, 0x80), c.green);
        try std.testing.expectEqual(@as(u8, 0x00), c.blue);
    }
}

test "color to hex string" {
    var buffer: [7]u8 = undefined;
    const color = Color{ .red = 0xFF, .green = 0x80, .blue = 0x00 };

    const size = try color.to_hex_string(&buffer);
    try std.testing.expectEqual(@as(usize, 7), size);
    try std.testing.expectEqualSlices(u8, "#FF8000", &buffer);
}

test "pen style from buffer" {
    var buffer: [2]u8 = .{ 0x02, 0x01 };
    const pen = PenStyle.from_buffer(&buffer);

    try std.testing.expect(pen != null);
    if (pen) |p| {
        try std.testing.expectEqual(@as(u8, 2), p.width);
        try std.testing.expectEqual(.dashed, p.style);
    }
}

test "fill pattern from buffer" {
    var buffer: [3]u8 = .{ 0x02, 0xFF, 0x00 };
    const fill = FillPattern.from_buffer(&buffer);

    try std.testing.expect(fill != null);
    if (fill) |f| {
        try std.testing.expectEqual(.hatched, f.pattern_id);
    }
}

test "graphics parser is graphics stream" {
    var allocator = std.testing.allocator;
    const parser = GraphicsParser.init(allocator);

    var buffer: [1]u8 = .{0x00};
    const is_graphics = parser.is_graphics_stream(&buffer);

    try std.testing.expectEqual(true, is_graphics);
}

test "graphics parser parse rectangle" {
    var allocator = std.testing.allocator;
    const parser = GraphicsParser.init(allocator);

    var buffer: [11]u8 = .{
        0x03, 0x00, 0x08, // header: draw_rectangle, length 8
        0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00, 0x64, // rectangle data
    };

    const obj = try parser.parse_object(&buffer);
    try std.testing.expect(obj != null);

    if (obj) |o| {
        try std.testing.expect(o == .rectangle);
    }
}

test "graphics parser parse circle" {
    var allocator = std.testing.allocator;
    const parser = GraphicsParser.init(allocator);

    var buffer: [9]u8 = .{
        0x04, 0x00, 0x06, // header: draw_circle, length 6
        0x00, 0x10, 0x00, 0x20, // center point
        0x00, 0x32, // radius 50
    };

    const obj = try parser.parse_object(&buffer);
    try std.testing.expect(obj != null);

    if (obj) |o| {
        try std.testing.expect(o == .circle);
        if (o == .circle) {
            try std.testing.expectEqual(@as(u16, 50), o.circle.radius);
        }
    }
}

test "graphics parser svg generation" {
    var allocator = std.testing.allocator;
    const parser = GraphicsParser.init(allocator);

    const obj: GraphicsObject = .{
        .rectangle = .{
            .bounds = .{
                .left = 0,
                .top = 0,
                .right = 100,
                .bottom = 100,
            },
        },
    };

    const svg = try parser.to_svg_element(obj, allocator);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.containsAtLeast(u8, svg, 1, "rect"));
}

test "graphics command type roundtrip" {
    const cmds = [_]GraphicsCommand{
        .begin_graphics,
        .draw_line,
        .draw_rectangle,
        .draw_circle,
        .set_color,
    };

    for (cmds) |original| {
        const byte = original.to_byte();
        const converted = GraphicsCommand.from_byte(byte);
        try std.testing.expect(converted != null);
        if (converted) |c| {
            try std.testing.expectEqual(original, c);
        }
    }
}
