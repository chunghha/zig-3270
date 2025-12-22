const std = @import("std");
const protocol = @import("protocol.zig");
const error_context = @import("error_context.zig");

/// LU3 (Logical Unit 3) Printing Support
/// Handles print job requests and management for TN3270 sessions
/// SCS (SAA Composite Sequence) Command enumeration - Core printing commands
pub const SCSCommand = enum(u8) {
    set_absolute_horizontal = 0x2B, // Absolute horizontal position
    set_absolute_vertical = 0x2C, // Absolute vertical position
    set_relative_horizontal = 0x2D, // Relative horizontal position
    set_relative_vertical = 0x2E, // Relative vertical position
    set_horizontal_tab_stop = 0x09, // Set horizontal tab
    set_vertical_tab_stop = 0x0B, // Set vertical tab
    carriage_return = 0x0D, // CR
    line_feed = 0x0A, // LF
    form_feed = 0x0C, // FF
    escape = 0x1B, // Escape (for extended commands)
    define_print_area = 0x34, // 4 - Define print area
    set_page_size = 0x73, // s - Set page size
    set_line_density = 0x6C, // l - Set line density
    set_character_density = 0x63, // c - Set character density
    set_font = 0x66, // f - Set font
    set_color = 0x6D, // m - Set color
    set_intensity = 0x69, // i - Set intensity
    start_highlight = 0x71, // q - Start highlight
    end_highlight = 0x72, // r - End highlight
    underscore = 0x75, // u - Underscore
    draw_box = 0x62, // b - Draw box
    _, // Unknown commands
};

/// SCS Parameter structure
pub const SCSParameter = struct {
    command: SCSCommand,
    param1: u8 = 0,
    param2: u8 = 0,
    param3: u16 = 0,

    pub fn from_bytes(bytes: []const u8) ?SCSParameter {
        if (bytes.len < 1) return null;

        const cmd = std.meta.intToEnum(SCSCommand, bytes[0]) catch return null;

        return .{
            .command = cmd,
            .param1 = if (bytes.len > 1) bytes[1] else 0,
            .param2 = if (bytes.len > 2) bytes[2] else 0,
            .param3 = if (bytes.len > 3)
                (@as(u16, bytes[3]) << 8) | (if (bytes.len > 4) bytes[4] else 0)
            else
                0,
        };
    }
};
/// Print job status enumeration
pub const PrintJobStatus = enum {
    queued,
    printing,
    completed,
    failed,
    cancelled,
};

/// Print format specification
pub const PrintFormat = enum {
    text, // Plain text output
    postscript, // PostScript format
    pdf, // PDF format (derived from PS)
    raw, // Raw data
};

/// Print job metadata
pub const PrintJob = struct {
    job_id: u32,
    timestamp: i64,
    status: PrintJobStatus = .queued,
    format: PrintFormat = .text,
    data: std.ArrayList(u8),
    page_count: u32 = 0,
    line_count: u32 = 0,
    error_message: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, job_id: u32) PrintJob {
        return .{
            .job_id = job_id,
            .timestamp = std.time.timestamp(),
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *PrintJob, allocator: std.mem.Allocator) void {
        self.data.deinit();
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }

    pub fn add_data(self: *PrintJob, data: []const u8) !void {
        try self.data.appendSlice(data);
    }

    pub fn size_bytes(self: PrintJob) usize {
        return self.data.items.len;
    }
};

/// Print queue manager
pub const PrintQueue = struct {
    allocator: std.mem.Allocator,
    jobs: std.ArrayList(PrintJob),
    next_job_id: u32 = 1,
    max_queue_size: usize = 100,
    total_bytes_printed: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) PrintQueue {
        return .{
            .allocator = allocator,
            .jobs = std.ArrayList(PrintJob).init(allocator),
        };
    }

    pub fn deinit(self: *PrintQueue) void {
        for (self.jobs.items) |*job| {
            job.deinit(self.allocator);
        }
        self.jobs.deinit();
    }

    /// Create and queue a new print job
    pub fn create_job(self: *PrintQueue, format: PrintFormat) !*PrintJob {
        if (self.jobs.items.len >= self.max_queue_size) {
            return error.QueueFull;
        }

        const job_id = self.next_job_id;
        self.next_job_id += 1;

        var job = PrintJob.init(self.allocator, job_id);
        job.format = format;

        try self.jobs.append(job);
        return &self.jobs.items[self.jobs.items.len - 1];
    }

    /// Get job by ID
    pub fn get_job(self: PrintQueue, job_id: u32) ?*PrintJob {
        for (self.jobs.items) |*job| {
            if (job.job_id == job_id) {
                return job;
            }
        }
        return null;
    }

    /// Complete a print job
    pub fn complete_job(self: *PrintQueue, job_id: u32) !void {
        if (self.get_job(job_id)) |job| {
            job.status = .completed;
            self.total_bytes_printed += job.size_bytes();
        } else {
            return error.JobNotFound;
        }
    }

    /// Cancel a print job
    pub fn cancel_job(self: *PrintQueue, job_id: u32) !void {
        if (self.get_job(job_id)) |job| {
            job.status = .cancelled;
        } else {
            return error.JobNotFound;
        }
    }

    /// Get job count by status
    pub fn count_by_status(self: PrintQueue, status: PrintJobStatus) usize {
        var count: usize = 0;
        for (self.jobs.items) |job| {
            if (job.status == status) {
                count += 1;
            }
        }
        return count;
    }

    /// Get all queued jobs
    pub fn get_queued_jobs(self: PrintQueue, allocator: std.mem.Allocator) ![]u32 {
        var job_ids = std.ArrayList(u32).init(allocator);
        for (self.jobs.items) |job| {
            if (job.status == .queued) {
                try job_ids.append(job.job_id);
            }
        }
        return job_ids.toOwnedSlice();
    }

    /// Statistics for the queue
    pub fn statistics(self: PrintQueue) PrintQueueStats {
        var queued: usize = 0;
        var printing: usize = 0;
        var completed: usize = 0;
        var failed_jobs: usize = 0;
        var total_bytes: u64 = 0;

        for (self.jobs.items) |job| {
            total_bytes += job.size_bytes();

            switch (job.status) {
                .queued => queued += 1,
                .printing => printing += 1,
                .completed => completed += 1,
                .failed => failed_jobs += 1,
                .cancelled => {},
            }
        }

        return .{
            .total_jobs = self.jobs.items.len,
            .queued_jobs = queued,
            .printing_jobs = printing,
            .completed_jobs = completed,
            .error_jobs = failed_jobs,
            .total_bytes = total_bytes,
            .total_bytes_printed = self.total_bytes_printed,
        };
    }
};

/// Print queue statistics
pub const PrintQueueStats = struct {
    total_jobs: usize,
    queued_jobs: usize,
    printing_jobs: usize,
    completed_jobs: usize,
    error_jobs: usize,
    total_bytes: u64,
    total_bytes_printed: u64,
};

/// Print data stream detector and processor
pub const PrintCommandDetector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PrintCommandDetector {
        return .{ .allocator = allocator };
    }

    /// Detect if buffer contains a print command
    pub fn is_print_command(self: PrintCommandDetector, buffer: []const u8) bool {
        if (buffer.len < 2) return false;

        // Check for print command markers
        // Common patterns: 0x7F (DEL) for print, or WSF commands with print intent
        return switch (buffer[0]) {
            0x7F => true, // PRINT command
            0xF3 => true, // Print screen variant
            else => false,
        };
    }

    /// Extract print data from buffer
    pub fn extract_print_data(self: PrintCommandDetector, buffer: []const u8) ![]u8 {
        if (buffer.len < 2) return error.InsufficientData;

        // Find end of print data (typically terminated by 0xFF)
        var end: usize = buffer.len;
        for (buffer[1..], 1..) |byte, idx| {
            if (byte == 0xFF) {
                end = idx;
                break;
            }
        }

        return try self.allocator.dupe(u8, buffer[1..end]);
    }
};

/// SCS Command Processor for print formatting
pub const SCSProcessor = struct {
    allocator: std.mem.Allocator,
    current_column: u16 = 1,
    current_row: u16 = 1,
    page_width: u16 = 132,
    page_height: u16 = 66,
    line_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) SCSProcessor {
        return .{
            .allocator = allocator,
        };
    }

    /// Process an SCS command and return true if output was modified
    pub fn process_command(self: *SCSProcessor, cmd: SCSCommand, param1: u8, param2: u8) bool {
        return switch (cmd) {
            .carriage_return => blk: {
                self.current_column = 1;
                break :blk true;
            },
            .line_feed => blk: {
                if (self.current_row < self.page_height) {
                    self.current_row += 1;
                }
                self.line_count += 1;
                break :blk true;
            },
            .form_feed => blk: {
                self.current_row = 1;
                self.current_column = 1;
                self.line_count += 1;
                break :blk true;
            },
            .set_absolute_horizontal => blk: {
                self.current_column = param1;
                break :blk true;
            },
            .set_absolute_vertical => blk: {
                self.current_row = param1;
                break :blk true;
            },
            .set_relative_horizontal => blk: {
                self.current_column += param1;
                if (self.current_column > self.page_width) {
                    self.current_column = self.page_width;
                }
                break :blk true;
            },
            .set_relative_vertical => blk: {
                self.current_row += param1;
                if (self.current_row > self.page_height) {
                    self.current_row = self.page_height;
                }
                break :blk true;
            },
            .set_page_size => blk: {
                self.page_width = param1;
                self.page_height = param2;
                break :blk true;
            },
            else => false,
        };
    }

    pub fn get_position(self: SCSProcessor) struct { row: u16, col: u16 } {
        return .{ .row = self.current_row, .col = self.current_column };
    }
};

/// LU3 Printer controller
pub const LU3Printer = struct {
    allocator: std.mem.Allocator,
    queue: PrintQueue,
    detector: PrintCommandDetector,
    scs_processor: SCSProcessor,
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) LU3Printer {
        return .{
            .allocator = allocator,
            .queue = PrintQueue.init(allocator),
            .detector = PrintCommandDetector.init(allocator),
            .scs_processor = SCSProcessor.init(allocator),
        };
    }

    pub fn deinit(self: *LU3Printer) void {
        self.queue.deinit();
    }

    /// Process a data stream for print commands
    pub fn process_stream(self: *LU3Printer, buffer: []const u8) !?u32 {
        if (!self.enabled) return null;

        if (!self.detector.is_print_command(buffer)) return null;

        // Extract print data
        const print_data = try self.detector.extract_print_data(buffer);
        defer self.allocator.free(print_data);

        // Create print job
        var job = try self.queue.create_job(.text);
        try job.add_data(print_data);

        return job.job_id;
    }

    /// Submit print data to existing job
    pub fn submit_data(self: *LU3Printer, job_id: u32, data: []const u8) !void {
        if (self.queue.get_job(job_id)) |job| {
            if (job.status != .queued and job.status != .printing) {
                return error.InvalidJobState;
            }
            try job.add_data(data);
        } else {
            return error.JobNotFound;
        }
    }

    /// Start printing a job
    pub fn start_job(self: *LU3Printer, job_id: u32) !void {
        if (self.queue.get_job(job_id)) |job| {
            job.status = .printing;
        } else {
            return error.JobNotFound;
        }
    }

    /// Complete a print job
    pub fn complete_job(self: *LU3Printer, job_id: u32) !void {
        try self.queue.complete_job(job_id);
    }

    /// Get job status
    pub fn get_status(self: LU3Printer, job_id: u32) ?PrintJobStatus {
        if (self.queue.get_job(job_id)) |job| {
            return job.status;
        }
        return null;
    }

    /// Get queue statistics
    pub fn get_statistics(self: LU3Printer) PrintQueueStats {
        return self.queue.statistics();
    }

    /// Enable/disable printing
    pub fn set_enabled(self: *LU3Printer, enabled: bool) void {
        self.enabled = enabled;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "print job creation" {
    var allocator = std.testing.allocator;
    var job = PrintJob.init(allocator, 1);
    defer job.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 1), job.job_id);
    try std.testing.expectEqual(PrintJobStatus.queued, job.status);
    try std.testing.expectEqual(@as(usize, 0), job.size_bytes());
}

test "print job add data" {
    var allocator = std.testing.allocator;
    var job = PrintJob.init(allocator, 1);
    defer job.deinit(allocator);

    const test_data = "Hello, World!";
    try job.add_data(test_data);

    try std.testing.expectEqual(test_data.len, job.size_bytes());
}

test "print queue create job" {
    var allocator = std.testing.allocator;
    var queue = PrintQueue.init(allocator);
    defer queue.deinit();

    const job = try queue.create_job(.text);
    try std.testing.expectEqual(@as(u32, 1), job.job_id);
    try std.testing.expectEqual(@as(usize, 1), queue.jobs.items.len);
}

test "print queue get job" {
    var allocator = std.testing.allocator;
    var queue = PrintQueue.init(allocator);
    defer queue.deinit();

    _ = try queue.create_job(.text);
    const job = queue.get_job(1);

    try std.testing.expect(job != null);
    if (job) |j| {
        try std.testing.expectEqual(@as(u32, 1), j.job_id);
    }
}

test "print queue job not found" {
    var allocator = std.testing.allocator;
    var queue = PrintQueue.init(allocator);
    defer queue.deinit();

    const job = queue.get_job(999);
    try std.testing.expect(job == null);
}

test "print queue complete job" {
    var allocator = std.testing.allocator;
    var queue = PrintQueue.init(allocator);
    defer queue.deinit();

    _ = try queue.create_job(.text);
    try queue.complete_job(1);

    const job = queue.get_job(1);
    try std.testing.expect(job != null);
    if (job) |j| {
        try std.testing.expectEqual(PrintJobStatus.completed, j.status);
    }
}

test "print queue cancel job" {
    var allocator = std.testing.allocator;
    var queue = PrintQueue.init(allocator);
    defer queue.deinit();

    _ = try queue.create_job(.text);
    try queue.cancel_job(1);

    const job = queue.get_job(1);
    try std.testing.expect(job != null);
    if (job) |j| {
        try std.testing.expectEqual(PrintJobStatus.cancelled, j.status);
    }
}

test "print queue count by status" {
    var allocator = std.testing.allocator;
    var queue = PrintQueue.init(allocator);
    defer queue.deinit();

    _ = try queue.create_job(.text);
    _ = try queue.create_job(.postscript);
    try queue.complete_job(1);

    const queued_count = queue.count_by_status(.queued);
    const completed_count = queue.count_by_status(.completed);

    try std.testing.expectEqual(@as(usize, 1), queued_count);
    try std.testing.expectEqual(@as(usize, 1), completed_count);
}

test "print queue statistics" {
    var allocator = std.testing.allocator;
    var queue = PrintQueue.init(allocator);
    defer queue.deinit();

    _ = try queue.create_job(.text);
    _ = try queue.create_job(.postscript);
    try queue.complete_job(1);

    const stats = queue.statistics();
    try std.testing.expectEqual(@as(usize, 2), stats.total_jobs);
    try std.testing.expectEqual(@as(usize, 1), stats.queued_jobs);
    try std.testing.expectEqual(@as(usize, 1), stats.completed_jobs);
}

test "print command detector is print command" {
    var allocator = std.testing.allocator;
    const detector = PrintCommandDetector.init(allocator);

    var print_cmd: [2]u8 = .{ 0x7F, 0x00 };
    const is_print = detector.is_print_command(&print_cmd);

    try std.testing.expectEqual(true, is_print);
}

test "print command detector not print command" {
    var allocator = std.testing.allocator;
    const detector = PrintCommandDetector.init(allocator);

    var data: [2]u8 = .{ 0x41, 0x42 };
    const is_print = detector.is_print_command(&data);

    try std.testing.expectEqual(false, is_print);
}

test "lu3 printer process stream" {
    var allocator = std.testing.allocator;
    var printer = LU3Printer.init(allocator);
    defer printer.deinit();

    var stream: [5]u8 = .{ 0x7F, 0x41, 0x42, 0x43, 0xFF };
    const job_id = try printer.process_stream(&stream);

    try std.testing.expect(job_id != null);
    if (job_id) |id| {
        const status = printer.get_status(id);
        try std.testing.expect(status != null);
        if (status) |s| {
            try std.testing.expectEqual(PrintJobStatus.queued, s);
        }
    }
}

test "lu3 printer submit data" {
    var allocator = std.testing.allocator;
    var printer = LU3Printer.init(allocator);
    defer printer.deinit();

    var job = try printer.queue.create_job(.text);
    const initial_size = job.size_bytes();

    try printer.submit_data(job.job_id, "test data");

    job = printer.queue.get_job(job.job_id) orelse unreachable;
    try std.testing.expect(job.size_bytes() > initial_size);
}

test "lu3 printer start job" {
    var allocator = std.testing.allocator;
    var printer = LU3Printer.init(allocator);
    defer printer.deinit();

    var job = try printer.queue.create_job(.text);
    try printer.start_job(job.job_id);

    const status = printer.get_status(job.job_id);
    try std.testing.expect(status != null);
    if (status) |s| {
        try std.testing.expectEqual(PrintJobStatus.printing, s);
    }
}

test "lu3 printer complete job" {
    var allocator = std.testing.allocator;
    var printer = LU3Printer.init(allocator);
    defer printer.deinit();

    var job = try printer.queue.create_job(.text);
    try printer.complete_job(job.job_id);

    const status = printer.get_status(job.job_id);
    try std.testing.expect(status != null);
    if (status) |s| {
        try std.testing.expectEqual(PrintJobStatus.completed, s);
    }
}

test "lu3 printer enable disable" {
    var allocator = std.testing.allocator;
    var printer = LU3Printer.init(allocator);
    defer printer.deinit();

    try std.testing.expectEqual(true, printer.enabled);

    printer.set_enabled(false);
    try std.testing.expectEqual(false, printer.enabled);

    printer.set_enabled(true);
    try std.testing.expectEqual(true, printer.enabled);
}

test "lu3 printer get statistics" {
    var allocator = std.testing.allocator;
    var printer = LU3Printer.init(allocator);
    defer printer.deinit();

    _ = try printer.queue.create_job(.text);
    _ = try printer.queue.create_job(.postscript);
    try printer.complete_job(1);

    const stats = printer.get_statistics();
    try std.testing.expectEqual(@as(usize, 2), stats.total_jobs);
    try std.testing.expectEqual(@as(usize, 1), stats.completed_jobs);
}

test "scs parameter from bytes carriage return" {
    var buffer: [1]u8 = .{0x0D};
    const param = SCSParameter.from_bytes(&buffer);

    try std.testing.expect(param != null);
    if (param) |p| {
        try std.testing.expectEqual(SCSCommand.carriage_return, p.command);
    }
}

test "scs parameter from bytes line feed" {
    var buffer: [1]u8 = .{0x0A};
    const param = SCSParameter.from_bytes(&buffer);

    try std.testing.expect(param != null);
    if (param) |p| {
        try std.testing.expectEqual(SCSCommand.line_feed, p.command);
    }
}

test "scs parameter from bytes with params" {
    var buffer: [3]u8 = .{ 0x2B, 0x20, 0x00 };
    const param = SCSParameter.from_bytes(&buffer);

    try std.testing.expect(param != null);
    if (param) |p| {
        try std.testing.expectEqual(SCSCommand.set_absolute_horizontal, p.command);
        try std.testing.expectEqual(@as(u8, 0x20), p.param1);
    }
}

test "scs processor carriage return" {
    var allocator = std.testing.allocator;
    var processor = SCSProcessor.init(allocator);

    processor.current_column = 50;
    _ = processor.process_command(.carriage_return, 0, 0);

    try std.testing.expectEqual(@as(u16, 1), processor.current_column);
}

test "scs processor line feed" {
    var allocator = std.testing.allocator;
    var processor = SCSProcessor.init(allocator);

    processor.current_row = 10;
    _ = processor.process_command(.line_feed, 0, 0);

    try std.testing.expectEqual(@as(u16, 11), processor.current_row);
    try std.testing.expectEqual(@as(u32, 1), processor.line_count);
}

test "scs processor form feed" {
    var allocator = std.testing.allocator;
    var processor = SCSProcessor.init(allocator);

    processor.current_row = 50;
    processor.current_column = 80;
    _ = processor.process_command(.form_feed, 0, 0);

    try std.testing.expectEqual(@as(u16, 1), processor.current_row);
    try std.testing.expectEqual(@as(u16, 1), processor.current_column);
}

test "scs processor absolute horizontal" {
    var allocator = std.testing.allocator;
    var processor = SCSProcessor.init(allocator);

    _ = processor.process_command(.set_absolute_horizontal, 25, 0);

    try std.testing.expectEqual(@as(u16, 25), processor.current_column);
}

test "scs processor absolute vertical" {
    var allocator = std.testing.allocator;
    var processor = SCSProcessor.init(allocator);

    _ = processor.process_command(.set_absolute_vertical, 30, 0);

    try std.testing.expectEqual(@as(u16, 30), processor.current_row);
}

test "scs processor page size" {
    var allocator = std.testing.allocator;
    var processor = SCSProcessor.init(allocator);

    const original_width = processor.page_width;
    const original_height = processor.page_height;

    _ = processor.process_command(.set_page_size, 80, 24);

    try std.testing.expect(processor.page_width != original_width);
    try std.testing.expectEqual(@as(u16, 80), processor.page_width);
    try std.testing.expectEqual(@as(u16, 24), processor.page_height);
}

test "scs processor get position" {
    var allocator = std.testing.allocator;
    var processor = SCSProcessor.init(allocator);

    processor.current_row = 15;
    processor.current_column = 40;

    const pos = processor.get_position();
    try std.testing.expectEqual(@as(u16, 15), pos.row);
    try std.testing.expectEqual(@as(u16, 40), pos.col);
}
