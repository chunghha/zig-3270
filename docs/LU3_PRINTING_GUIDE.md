# LU3 Printing Support Guide

## Overview

LU3 (Logical Unit 3) provides printing capabilities for TN3270 terminals. This guide covers print job management and SCS (SAA Composite Sequence) command processing.

## Print Job Management

### Creating Print Jobs

```zig
var allocator = std.mem.Allocator;
var printer = LU3Printer.init(allocator);
defer printer.deinit();

// Create a text print job
var job = try printer.queue.create_job(.text);
try job.add_data("Sample print data");
```

### Job Lifecycle

Jobs progress through states:

```
queued → printing → completed
         ↓
         failed
         ↓
       cancelled
```

```zig
// Start printing
try printer.start_job(job.job_id);

// Complete the job
try printer.complete_job(job.job_id);

// Check status
if (printer.get_status(job.job_id)) |status| {
    switch (status) {
        .queued => std.debug.print("Waiting to print\n", .{}),
        .printing => std.debug.print("Printing now\n", .{}),
        .completed => std.debug.print("Finished\n", .{}),
        .failed => std.debug.print("Error occurred\n", .{}),
        .cancelled => std.debug.print("Cancelled\n", .{}),
    }
}
```

### Multiple Jobs

```zig
// Create multiple jobs
const job1 = try printer.queue.create_job(.text);
const job2 = try printer.queue.create_job(.postscript);
const job3 = try printer.queue.create_job(.pdf);

// Track them independently
try printer.submit_data(job1.job_id, "First job data");
try printer.submit_data(job2.job_id, "Second job data");

// Get statistics
const stats = printer.get_statistics();
std.debug.print("Total jobs: {}\n", .{stats.total_jobs});
std.debug.print("Queued: {}\n", .{stats.queued_jobs});
std.debug.print("Completed: {}\n", .{stats.completed_jobs});
```

## Print Formats

### Supported Formats

```zig
pub const PrintFormat = enum {
    text,       // Plain text output
    postscript, // PostScript format
    pdf,        // PDF format
    raw,        // Raw data passthrough
};
```

Each format has different processing characteristics:

| Format | Use Case | Processing |
|--------|----------|-----------|
| text | Reports, listings | Line-oriented |
| postscript | Graphics, fonts | Vector graphics |
| pdf | Distribution | Printable, portable |
| raw | Pass-through | No processing |

## SCS (SAA Composite Sequence) Commands

### Core Commands

SCS commands control print formatting and positioning:

```zig
pub const SCSCommand = enum(u8) {
    carriage_return = 0x0D,           // CR
    line_feed = 0x0A,                // LF
    form_feed = 0x0C,                // FF - Page eject
    set_absolute_horizontal = 0x2B,  // Set column
    set_absolute_vertical = 0x2C,    // Set row
    set_relative_horizontal = 0x2D,  // Move right
    set_relative_vertical = 0x2E,    // Move down
    set_page_size = 0x73,            // Page dimensions
    set_font = 0x66,                 // Font selection
    set_color = 0x6D,                // Color setting
    set_intensity = 0x69,            // Bright/dim
    // ... 8 more command types
};
```

### SCS Processor

The `SCSProcessor` handles command execution:

```zig
var processor = SCSProcessor.init(allocator);

// Process formatting commands
_ = processor.process_command(.carriage_return, 0, 0);
_ = processor.process_command(.line_feed, 0, 0);
_ = processor.process_command(.set_absolute_horizontal, 25, 0); // Column 25

// Get current position
const pos = processor.get_position();
std.debug.print("Position: row={}, col={}\n", .{ pos.row, pos.col });
```

### SCS Parameter Parsing

```zig
var buffer: [3]u8 = .{ 0x2B, 0x20, 0x00 }; // Set column 32
const param = SCSParameter.from_bytes(&buffer);

if (param) |p| {
    std.debug.print("Command: {}\n", .{p.command});
    std.debug.print("Parameter: {}\n", .{p.param1});
}
```

## Processing Print Data

### Command Detection

```zig
var detector = PrintCommandDetector.init(allocator);

var buffer: [10]u8 = undefined;
if (detector.is_print_command(&buffer)) {
    const print_data = try detector.extract_print_data(&buffer);
    defer allocator.free(print_data);
    // Process print data
}
```

### Stream Processing

```zig
// Process incoming data stream
if (try printer.process_stream(data_buffer)) |job_id| {
    std.debug.print("Created print job {}\n", .{job_id});
    
    // Add more data if needed
    try printer.submit_data(job_id, additional_data);
    
    // Finalize
    try printer.start_job(job_id);
}
```

## Page Management

### Page Size Configuration

```zig
var processor = SCSProcessor.init(allocator);

// Set to 80×24 page
_ = processor.process_command(.set_page_size, 80, 24);

// Set to 132×66 (standard report)
_ = processor.process_command(.set_page_size, 132, 66);

std.debug.print("Page size: {}×{}\n", 
    .{ processor.page_width, processor.page_height });
std.debug.print("Lines printed: {}\n", .{processor.line_count});
```

### Form Feed Handling

```zig
// Detect form feed
if (cmd == .form_feed) {
    // Eject current page
    processor.current_row = 1;
    processor.current_column = 1;
    save_page_to_output();
}
```

## Statistics and Monitoring

### Queue Statistics

```zig
const stats = printer.get_statistics();

std.debug.print("=== Print Queue Statistics ===\n", .{});
std.debug.print("Total jobs: {}\n", .{stats.total_jobs});
std.debug.print("Queued: {}\n", .{stats.queued_jobs});
std.debug.print("Printing: {}\n", .{stats.printing_jobs});
std.debug.print("Completed: {}\n", .{stats.completed_jobs});
std.debug.print("Failed: {}\n", .{stats.error_jobs});
std.debug.print("Total bytes: {}\n", .{stats.total_bytes});
std.debug.print("Bytes printed: {}\n", .{stats.total_bytes_printed});
```

### Job Size Tracking

```zig
var job = try printer.queue.create_job(.text);

try job.add_data("Line 1\n");
try job.add_data("Line 2\n");

std.debug.print("Job size: {} bytes\n", .{job.size_bytes()});
```

## Configuration

### Queue Limits

```zig
var queue = PrintQueue.init(allocator);
queue.max_queue_size = 500; // Maximum 500 jobs in queue

const job = try queue.create_job(.text);
// Returns error.QueueFull if limit exceeded
```

### Enable/Disable Printing

```zig
// Temporarily disable printing
printer.set_enabled(false);

// Try to process print stream - will return null
if (try printer.process_stream(&buffer)) |job_id| {
    // Never executed when disabled
}

// Re-enable
printer.set_enabled(true);
```

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|-----------|
| `QueueFull` | Too many jobs queued | Increase `max_queue_size` |
| `JobNotFound` | Invalid job ID | Use valid ID from `create_job()` |
| `InvalidJobState` | Wrong state for operation | Check job status before submit |
| `InsufficientData` | Print data too short | Ensure minimum data size |

```zig
if (printer.submit_data(job_id, data)) |_| {
    std.debug.print("Data submitted\n", .{});
} else |err| {
    switch (err) {
        error.InvalidJobState => std.debug.print("Job not ready\n", .{}),
        error.JobNotFound => std.debug.print("Job missing\n", .{}),
        else => std.debug.print("Unknown error\n", .{}),
    }
}
```

## Examples

### Simple Report Printing

```zig
var printer = LU3Printer.init(allocator);
defer printer.deinit();

// Create job
var job = try printer.queue.create_job(.text);
try job.add_data("===== REPORT =====\n");
try job.add_data("Date: 2025-01-01\n");
try job.add_data("Total: $1,234.56\n");

// Start and complete
try printer.start_job(job.job_id);
try printer.complete_job(job.job_id);

const stats = printer.get_statistics();
std.debug.print("Printed {} bytes\n", .{stats.total_bytes_printed});
```

### Formatted Output with SCS

```zig
var processor = SCSProcessor.init(allocator);

// Set page to 80×24
_ = processor.process_command(.set_page_size, 80, 24);

// Position at column 20
_ = processor.process_command(.set_absolute_horizontal, 20, 0);

// Move down 5 lines
for (0..5) |_| {
    _ = processor.process_command(.line_feed, 0, 0);
}

// Get final position
const pos = processor.get_position();
std.debug.print("Positioned at: row={}, col={}\n", .{ pos.row, pos.col });
```

## Performance Considerations

1. **Job Batching**: Create multiple jobs sequentially, not parallel
2. **Data Streaming**: Add large print data in chunks
3. **Memory**: Each job allocates its own data buffer
4. **Queue Size**: Keep `max_queue_size` reasonable (100-1000)

## Compatibility

- TN3270 protocol specification
- TN3270E protocol enhancements
- IBM 3270 printer support
- LU1 and LU3 sessions

## See Also

- `lu3_printer.zig` - Core implementation
- SCS specification in IBM 3270 documentation
- Print stream processing examples
