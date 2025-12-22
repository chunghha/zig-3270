# Property-Based Testing Framework Guide

## Overview

Property-based testing automatically generates test cases to find edge cases and bugs. This framework provides QuickCheck-style testing for TN3270 protocol components.

## Core Concepts

### Properties

A property is an invariant that should always hold true:

```zig
/// All field attributes should be in valid ranges
pub const FieldAttributeValidityProperty = struct {
    pub fn check(self: FieldAttributeValidityProperty, input: []const u8) !bool {
        if (input.len < 1) return true;
        const attr = input[0];
        const valid = (attr >= 0x00 and attr <= 0x0F) or 
                      (attr >= 0xC0 and attr <= 0xFF);
        return valid or attr == 0xFF;
    }
};
```

### Random Number Generation

```zig
var rng = property_testing.Rng.init(seed);

const byte_value = rng.u8();
const word_value = rng.u16();
const dword_value = rng.u32();
const bounded = rng.range(10, 20); // 10-19
const random_bool = rng.bool();
```

### Generators

Generators create arbitrary test inputs:

```zig
// Command code generator
var cmd_gen = property_testing.CommandCodeGenerator.init(allocator);
const code = try cmd_gen.generate(&rng);
defer allocator.free(code);

// Field attribute generator  
var attr_gen = property_testing.FieldAttributeGenerator.init(allocator);
const attr = try attr_gen.generate(&rng);
defer allocator.free(attr);

// Address generator (24×80 screen)
var addr_gen = property_testing.AddressGenerator.init(allocator);
const addr = try addr_gen.generate(&rng);
defer allocator.free(addr);

// Custom buffer generator
var buf_gen = property_testing.BufferGenerator.init(allocator);
buf_gen.max_size = 4096;
const buffer = try buf_gen.generate(&rng);
defer allocator.free(buffer);
```

## Built-in Properties

### 1. CommandParseRoundtripProperty

Verifies parse/format consistency for command codes.

```zig
var prop = protocol_properties.CommandParseRoundtripProperty.init(allocator);
const passes = try prop.check(&buffer);
```

**Tests:** Command codes can be parsed and formatted repeatedly.

### 2. FieldAttributeValidityProperty

Checks field attributes are in valid ranges.

```zig
var prop = protocol_properties.FieldAttributeValidityProperty.init(allocator);
const valid = try prop.check(&buffer);
```

**Tests:** All field attributes are 0x00-0x0F or 0xC0-0xFF.

### 3. AddressValidityProperty

Validates addresses fit within 24×80 grid.

```zig
var prop = protocol_properties.AddressValidityProperty.init(allocator);
const valid = try prop.check(&buffer);
```

**Tests:** Addresses stay within bounds (row < 24, col < 80).

### 4. ParserCrashResistanceProperty

Ensures parser never crashes on arbitrary input.

```zig
var prop = protocol_properties.ParserCrashResistanceProperty.init(allocator);
const safe = try prop.check(&buffer);
```

**Tests:** Parser handles malformed data gracefully.

### 5. AddressConversionProperty

Verifies address conversion is identity-preserving.

```zig
var prop = protocol_properties.AddressConversionProperty.init(allocator);
const consistent = try prop.check(&buffer);
```

**Tests:** (row, col) → offset → (row', col') where row' == row and col' == col.

### 6. BufferBoundaryProperty

Checks buffer operations don't overflow.

```zig
var prop = protocol_properties.BufferBoundaryProperty.init(allocator);
const safe = try prop.check(&buffer);
```

**Tests:** Large buffers are processed safely.

### 7. CommandConsistencyProperty

Validates command codes are consistent across parse/format.

```zig
var prop = protocol_properties.CommandConsistencyProperty.init(allocator);
const consistent = try prop.check(&buffer);
```

**Tests:** Known codes parse, unknown codes reject consistently.

### 8. ParserCrashResistanceProperty

Duplicate of #4 - ensures robustness.

## Running Tests

### Simple Property Test

```zig
test "property test field attributes" {
    var allocator = std.testing.allocator;
    var prop = protocol_properties.FieldAttributeValidityProperty.init(allocator);
    
    var rng = property_testing.Rng.init(42);
    var gen = property_testing.FieldAttributeGenerator.init(allocator);
    
    for (0..100) |_| {
        const input = try gen.generate(&rng);
        defer allocator.free(input);
        
        const result = try prop.check(input);
        try std.testing.expect(result);
    }
}
```

### Using PropertyRunner

```zig
test "property runner integration" {
    var allocator = std.testing.allocator;
    var runner = property_testing.PropertyRunner.init(allocator);
    
    runner.iterations = 500;
    runner.seed = 12345;
    
    var prop = MyProperty.init(allocator);
    var gen = MyGenerator.init(allocator);
    
    const result = try runner.run_test(MyProperty, prop, gen);
    defer result.deinit(allocator);
    
    try std.testing.expect(result.passed);
}
```

## Creating Custom Properties

### Basic Property Template

```zig
pub const MyProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MyProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: MyProperty, input: []const u8) !bool {
        // Validate the property
        // Return true if property holds, false if violated
        
        if (input.len < 1) return true; // Skip empty input
        
        // Your property logic here
        const is_valid = input[0] < 128;
        return is_valid;
    }
};
```

### Using in Tests

```zig
test "my custom property" {
    var allocator = std.testing.allocator;
    var prop = MyProperty.init(allocator);
    
    var rng = property_testing.Rng.init(9999);
    var gen = property_testing.CommandCodeGenerator.init(allocator);
    
    for (0..50) |_| {
        const input = try gen.generate(&rng);
        defer allocator.free(input);
        
        try std.testing.expect(try prop.check(input));
    }
}
```

## Advanced Techniques

### Shrinking Failing Cases

When a property fails, the framework can shrink the input:

```zig
if (!try prop.check(input)) {
    // Try to shrink to minimal failing case
    var shrank = try allocator.dupe(u8, input);
    defer allocator.free(shrank);
    
    // Remove bytes one at a time
    for (0..shrank.len) |i| {
        shrank[i] = 0;
        if (!try prop.check(shrank[0..i])) {
            // Still fails with fewer bytes
            break;
        }
    }
}
```

### Parameterized Generators

```zig
var gen = property_testing.BufferGenerator.init(allocator);
gen.max_size = 10_000; // Large buffers

// Or use address generator with screen constraints
var addr_gen = property_testing.AddressGenerator.init(allocator);
// Generates valid 24×80 addresses
```

### Multiple Property Testing

```zig
const properties = [_]type{
    CommandParseRoundtripProperty,
    FieldAttributeValidityProperty,
    AddressValidityProperty,
};

for (properties) |PropType| {
    var prop = PropType.init(allocator);
    // Run tests for each property
}
```

## Tips and Best Practices

### 1. Keep Properties Simple

Each property should test one invariant:

```zig
// Good: Single concern
pub fn check(self: Self, input: []const u8) !bool {
    return input[0] < 24; // Row validity only
}

// Bad: Multiple concerns
pub fn check(self: Self, input: []const u8) !bool {
    return input[0] < 24 and input[1] < 80 and input[2] == 0;
}
```

### 2. Handle Edge Cases

```zig
pub fn check(self: Self, input: []const u8) !bool {
    // Skip if insufficient data
    if (input.len < required_size) return true;
    
    // Your property logic
    return validate(input);
}
```

### 3. Use Appropriate Seeds

```zig
var rng = property_testing.Rng.init(1337); // Deterministic seed
// Tests are reproducible with same seed
```

### 4. Test at Boundaries

```zig
var rng = property_testing.Rng.init(seed);

// Add boundary checks
const min_value = rng.range(0, 1);     // 0
const max_value = rng.range(99, 100);  // 99
const mid_value = rng.range(50, 51);   // 50
```

### 5. Document Properties

```zig
/// Property: All addresses fit within 24×80 grid
/// 
/// This property ensures that screen coordinates never exceed bounds.
/// Valid: row ∈ [0,23], col ∈ [0,79]
pub const AddressValidityProperty = struct { ... };
```

## Integration with CI/CD

Properties can run in automated tests:

```bash
# Run all tests including properties
task test

# Run specific property tests
zig build test -- --name "*property*"
```

## Performance Considerations

1. **Iterations**: Start with 100, increase to 1000 for critical properties
2. **Input Size**: Keep generated inputs reasonable (< 10KB)
3. **Allocations**: Reuse allocators across multiple runs
4. **Seed Variation**: Test with multiple seeds for coverage

## Common Patterns

### Testing Parse Roundtrips

```zig
pub const ParseRoundtripProperty = struct {
    allocator: std.mem.Allocator,

    pub fn check(self: Self, input: []const u8) !bool {
        const parsed = try parse(input);
        const formatted = try format(parsed);
        return std.mem.eql(u8, formatted, input);
    }
};
```

### Testing Invariants

```zig
pub const InvariantProperty = struct {
    allocator: std.mem.Allocator,

    pub fn check(self: Self, input: []const u8) !bool {
        const obj = try process(input);
        return isValid(obj); // Check invariant
    }
};
```

### Testing Error Handling

```zig
pub const ErrorHandlingProperty = struct {
    allocator: std.mem.Allocator,

    pub fn check(self: Self, input: []const u8) !bool {
        _ = try parse(input) catch {
            // Errors are acceptable
            return true;
        };
        // Successful parses must be valid
        return true;
    }
};
```

## Troubleshooting

### Properties Always Pass

- May be too permissive (too many `return true` paths)
- Check with deliberate failures first
- Use smaller input ranges

### Slow Test Execution

- Reduce iteration count
- Simplify generators
- Profile allocations

### Allocation Failures

- Use testing allocator's safety checks
- Verify all generated data is freed
- Check for memory leaks in generators

## See Also

- `property_testing.zig` - Core framework
- `protocol_properties.zig` - Protocol-specific properties
- QuickCheck (Haskell) - Original inspiration
- Hypothesis (Python) - Similar framework
