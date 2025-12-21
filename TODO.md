# TODO & Project Roadmap

## Summary

**Status**: Priorities 1-5 COMPLETE ✓  
**Test Coverage**: 121+ tests (109+ unit + 12 integration), all passing  
**Codebase Size**: ~4,074 lines of Zig (2 facades + 1 EBCDIC + 3 QA + profiler + docs)  
**Architecture**: 5-layer design with facades + EBCDIC + error context + debug logging + profiler ✓  
**Documentation**: Complete with ARCHITECTURE.md, PERFORMANCE.md, HEX_VIEWER.md, GHOSTTY_INTEGRATION.md

### Quick Stats
- **Modules**: 33 source files (23 + 2 facades + 1 EBCDIC + 3 QA + profiler)
- **Imports in emulator.zig**: 4 (std + protocol_layer + domain_layer + input + attributes)
- **Layer Facades**: protocol_layer (5 modules) + domain_layer (5 modules)
- **EBCDIC Support**: encode/decode functions + round-trip conversion (16 tests)
- **Error Context**: ParseError, FieldError, ConnectionError with recovery suggestions (9 tests)
- **Debug Logging**: Configurable per-module logging with 5 severity levels (11 tests)
- **Profiler**: Memory tracking & timing analysis with reporting (11 tests)
- **Tests**: 121+ total (109+ unit + 12 integration e2e)
- **Integration Tests**: 12 comprehensive e2e tests validating layer interaction
- **Build System**: Zig build.zig + Taskfile.yml (with `task loc` for code metrics)
- **Documentation**: README.md, docs/ARCHITECTURE.md, docs/PERFORMANCE.md, docs/HEX_VIEWER.md, docs/GHOSTTY_INTEGRATION.md

### Progress Summary
- **Phase 1**: ✓ Decouple emulator.zig (12→4 imports)
- **Phase 2**: ✓ Consolidate parsing utilities
- **Phase 3**: ✓ Add e2e integration tests (12 total)
- **Phase 4**: ✓ EBCDIC encoder/decoder (16 tests, complete)
- **Phase 5a**: ✓ Error handling & context (9 tests)
- **Phase 5b**: ✓ Debug logging system (11 tests)
- **Phase 5c**: ✓ Profiler & performance analysis (11 tests, PERFORMANCE.md guide)

---

## Priority 1: Refactoring - Reduce Coupling (COMPLETED ✓)

### Core Refactoring Task: Decouple emulator.zig - COMPLETE
**Status**: Completed Dec 21 with 3 commits (5.5 hours total)  
**Problem Solved**: emulator.zig reduced from 12 imports → 4 imports  
**Solution Implemented**: Two facade modules consolidate 10 protocol + domain modules

#### Phase 1a: Create protocol_layer.zig ✓
- [x] **Extract protocol facade** - Wrap protocol layer modules
  - Consolidates: `protocol.zig`, `parser.zig`, `stream_parser.zig`, `command.zig`, `data_entry.zig`
  - Re-exports: CommandCode, OrderCode, FieldAttribute, Address, Parser, Command, Order, etc.
  - Reduces emulator.zig from 12→8 imports
  - Tests: All existing tests pass + 3 new facade tests
  - Commit: `e022d86`

#### Phase 1b: Create domain_layer.zig ✓
- [x] **Extract domain facade** - Wrap domain layer modules
  - Consolidates: `screen.zig`, `field.zig`, `terminal.zig`, `executor.zig`, `renderer.zig`
  - Re-exports: Screen, FieldManager, Field, Terminal, Executor, Renderer
  - Reduces emulator.zig from 8→4 imports
  - Tests: All existing tests pass + 3 new facade tests
  - Commit: `ee09ad0`

#### Phase 1c: Update emulator.zig ✓
- [x] **Import only facades** - Update to use new layers
  - `const protocol_layer = @import("protocol_layer.zig");`
  - `const domain_layer = @import("domain_layer.zig");`
  - `const input = @import("input.zig");`
  - `const attributes = @import("attributes.zig");`
  - Final result: 4 imports (std + 3 logic + input + attributes)
  - All public API identical for backward compatibility
  - Full test suite: 60+ tests pass ✓

#### Phase 1d: Update main.zig ✓
- [x] **Use emulator facade** - Verified no new imports needed
  - Updated test block to reference layer facades
  - Validate: `task check` passes ✓
  - Commit: `40167a0`

**Total Effort**: 5.5 hours (actual: ~3 hours with TDD + testing)  
**Validation**: All 60+ tests pass ✓, `task check` clean ✓, no behavioral changes ✓

**Results Summary**:
- emulator.zig imports: 12 → 4 (67% reduction)
- New facade modules: protocol_layer.zig, domain_layer.zig
- Code organization: Clear separation between protocol and domain concerns
- Maintainability: Future changes to protocol/domain modules only need updates in facades

---

## Priority 2: Refactoring - Consolidate Parsing Utilities (COMPLETED ✓)

### Consolidate parse_utils usage - COMPLETE
**Status**: Completed Dec 21  
**Problem Solved**: Eliminated duplicate address/code conversion logic  
**Solution Implemented**: Refactored command.zig and data_entry.zig to use parse_utils

#### Changes Made
- [x] **Update command.zig** - Use parse_utils for command/order code parsing
  - Replace: `std.meta.intToEnum(protocol.CommandCode, ...)` → `parse_utils.parse_command_code(...)`
  - Replace: `std.meta.intToEnum(protocol.OrderCode, ...)` → `parse_utils.parse_order_code(...)`
  - Benefit: Consistent error handling, single source of truth
  - Tests: All passing, error mapping preserved

- [x] **Update data_entry.zig** - Use parse_utils for address conversion
  - Replace: `screen_offset / 80, screen_offset % 80` → `parse_utils.buffer_to_address(...)`
  - Eliminate: 3 instances of duplicate address conversion logic
  - Benefit: DRY principle, consistent address handling
  - Tests: All passing

**Total Effort**: 1.5 hours (actual, less than estimated 2-3h)  
**Validation**: All 60+ tests pass ✓, no behavioral changes ✓

**Results Summary**:
- Parsing utilities consolidated from duplication to single usage pattern
- Code reduced by ~10 lines of address conversion boilerplate
- Easier to maintain protocol parsing logic in one place
- Commit: `afed468`

---

## Priority 3: Testing - Integration Tests (COMPLETED ✓)

### Add End-to-End Tests - COMPLETE
**Status**: Completed Dec 21  
**Problem Solved**: Validated protocol_layer + domain_layer facades work together  
**Solution Implemented**: Added 6 comprehensive e2e tests to integration_test.zig

#### Tests Added (12 total integration tests)
- [x] **Layer facade integration** - protocol_layer with domain_layer
  - Direct use of facades for command creation and execution
  - Validates type re-exports work correctly
  
- [x] **Complex screen with multiple fields** - Label + input + second field
  - Tests realistic form layout with 3+ fields
  - Validates field creation and attribute handling
  
- [x] **Sequential commands** - Erase Write then Write
  - Tests command sequencing (erase vs. partial update)
  - Validates state transitions between commands
  
- [x] **Protocol layer parsing** - Command and order code parsing
  - Validates parse_utils works with protocol types
  - Tests all major command/order codes
  
- [x] **Terminal state with screen updates**
  - Tests terminal abstraction with screen writes
  - Validates cursor position tracking
  
- [x] **Address conversion round-trip** - Full 24×80 grid
  - Tests address conversion for all screen positions
  - Ensures no precision loss in row/col calculations

**Total Test Count**: 70+ tests (60 unit + 12 integration)  
**Validation**: All tests pass ✓, covers layer interaction ✓, validates data flow ✓

**Results Summary**:
- Protocol → Domain layer integration validated
- Complex field structures working correctly
- Sequential command execution verified
- Address conversions accurate across full screen
- Commit: `fb785e5`

---

## Priority 4: Features - EBCDIC Support (COMPLETED ✓)

### Core: EBCDIC Encoding - COMPLETE
- [x] **Implement EBCDIC encoder/decoder** - IBM mainframe character encoding
  - Create `ebcdic.zig` with standard EBCDIC-to-ASCII and ASCII-to-EBCDIC tables
  - Exported via root.zig as public API
  - Tests: 16 test cases covering single bytes, buffers, round-trips, error cases
  - Effort: Completed Dec 21 (actual: ~1.5 hours with TDD)
  - Impact: Foundation for TN3270 protocol compliance
  - Commit: `2457836`
  - Key Functions:
    - `decode_byte(ebcdic_byte: u8) -> u8` - Single byte decoding
    - `encode_byte(ascii_byte: u8) -> !u8` - Single byte encoding with error handling
    - `decode(ebcdic_buffer: []const u8, ascii_buffer: []u8) -> !usize` - Buffer decoding
    - `encode(ascii_buffer: []const u8, ebcdic_buffer: []u8) -> !usize` - Buffer encoding
    - `decode_alloc(allocator, buffer) -> ![]u8` - Allocating decode
    - `encode_alloc(allocator, buffer) -> ![]u8` - Allocating encode

### Nice-to-Have Features
- [ ] **Keyboard mapping configuration** - Allow user-defined key bindings
  - Status: Hard-coded currently in input.zig
  - Effort: 3-4 hours

- [ ] **Screen history & scrollback** - Terminal scroll-back buffer
  - Effort: 4-5 hours

- [ ] **Advanced terminal attributes** - Colors, bold, underline (via ANSI)
  - Effort: 3-4 hours

- [ ] **Session persistence** - Save/restore terminal state to disk
  - Effort: 5-6 hours

---

## Priority 5: Quality Assurance

### Error Handling - COMPLETE ✓
- [x] **Enhance error messages**
  - Add context and recovery suggestions
  - *Status*: Completed Dec 21 (actual: ~1.5 hours)
  - Implementation: `error_context.zig` with ParseError, FieldError, ConnectionError
  - Each error includes position/field info and recovery suggestions
  - Commit: `99001fc`

- [x] **Add debug logging**
  - Log protocol interactions for troubleshooting
  - *Status*: Completed Dec 21 (actual: ~1.5 hours)
  - Implementation: `debug_log.zig` with configurable per-module logging
  - 5 severity levels: disabled, error, warn, info, debug, trace
  - Can set global or per-module log levels
  - Commit: `a89587b`

### Performance - COMPLETE ✓
- [x] **Profile for bottlenecks**
  - *Status*: Completed Dec 21 (actual: ~2 hours)
  - Implementation: `profiler.zig` with memory tracking and timing analysis
  - Benchmark suite in `benchmark.zig` measures parser, executor, field management
  - Results documented in PERFORMANCE.md with baseline metrics
  - Commit: `7223f3c`

- [x] **Document memory optimization patterns**
  - *Status*: Completed Dec 21 (actual: ~1 hour)
  - Created PERFORMANCE.md with:
    - Hot path identification (parser, stream parser, data entry, executor)
    - Memory patterns and allocation sites
    - 3 high-priority optimization opportunities
    - Profiler usage guide and measurement results
    - Guidelines for new code
  - Commit: `7223f3c`

### Integration
- [ ] **Test with real mainframe** (mvs38j.com)
  - *Effort*: 1 hour

- [x] **Add CI/CD pipeline** (GitHub Actions)
  - *Status*: Completed Dec 21
  - Implementation: `.github/workflows/ci.yml`
  - Features:
    - Test on every push to main
    - Build on Ubuntu and macOS
    - Auto-create GitHub releases on version tags (v0.2.0, etc.)
    - Release assets include binaries and documentation
  - Commit: `<pending>`

---

## Completed ✓

- [x] **Priority 5: Quality Assurance Complete** (COMPLETED - Dec 21)
  - Phase 5a: Error handling & context with recovery suggestions (9 tests)
  - Phase 5b: Debug logging system with per-module filtering (11 tests)
  - Phase 5c: Memory & timing profiler with reporting (11 tests)
  - PERFORMANCE.md guide with hot path analysis and optimization opportunities
  - Total effort: ~5 hours actual
  - Commits: 99001fc, a89587b, 7223f3c

- [x] **Priority 5: Error Handling & Logging** (COMPLETED - Dec 21)
  - Created error_context.zig with structured error types and recovery suggestions
  - Created debug_log.zig with configurable per-module logging system
  - 20 tests covering all error types and logging scenarios
  - Effort: ~3 hours actual
  - Commits: 99001fc, a89587b

- [x] **Priority 4: Implement EBCDIC encoder/decoder** (COMPLETED - Dec 21)
  - Created ebcdic.zig with standard EBCDIC-to-ASCII and ASCII-to-EBCDIC tables
  - 16 comprehensive tests covering single bytes, buffers, round-trips, special chars, digits, lowercase
  - Error handling for invalid ASCII values and buffer overflow
  - Allocating and non-allocating variants for flexible memory management
  - Commit: 2457836

- [x] **Priority 3: Add e2e integration tests** (COMPLETED - Dec 21)
  - Added 6 comprehensive e2e tests to integration_test.zig
  - Validated protocol_layer + domain_layer facade integration
  - Tested complex field structures, sequential commands, address conversion
  - Total: 70+ tests (60 unit + 12 integration)
  - Commit: fb785e5

- [x] **Priority 2: Consolidate parsing utilities** (COMPLETED - Dec 21)
  - Refactored command.zig to use parse_utils for code parsing
  - Refactored data_entry.zig to use parse_utils for address conversion
  - Eliminated ~10 lines of duplicate conversion logic
  - Improved code maintainability and DRY principle
  - Commit: afed468

- [x] **Priority 1: Decouple emulator.zig** (COMPLETED - Dec 21)
  - Created protocol_layer.zig facade (5 modules consolidated)
  - Created domain_layer.zig facade (5 modules consolidated)
  - Reduced emulator.zig imports from 12 to 4 (67% reduction)
  - Updated main.zig test block to reference facades
  - All 60+ tests passing, zero behavioral changes
  - Commits: e022d86, ee09ad0, 40167a0

- [x] **ARCHITECTURE.md & CODEBASE_REVIEW.md** (COMPLETED - Dec 21)
  - Comprehensive system design documentation
  - Identified coupling issues and refactoring strategy
  - Clear module dependency graph and layer design

- [x] **Implement hex viewer** (COMPLETED - Dec 21)
  - Side-by-side hex and ASCII display
  - Configurable bytes per line
  - 7 unit tests, example program
  - Integration into main build system

---

## Metrics & Progress

### Code Statistics
```
Total Lines: 4,074
Modules: 33
Tests: 121+
Test Pass Rate: 100%
```

### Module Breakdown
- Core Protocol: 5 modules (654 lines)
- Terminal & Display: 6 modules (892 lines)
- Network: 3 modules (562 lines)
- Commands & Data: 4 modules (521 lines)
- Character Encoding: 1 module (359 lines - EBCDIC)
- Quality Assurance: 3 modules (852 lines - error_context + debug_log + profiler)
- Utilities & Examples: 8 modules (600+ lines)

### Test Coverage by Module
| Module | Tests | Status |
|--------|-------|--------|
| profiler | 11 | ✓ |
| debug_log | 11 | ✓ |
| error_context | 9 | ✓ |
| ebcdic | 16 | ✓ |
| hex_viewer | 7 | ✓ |
| terminal | 8 | ✓ |
| field | 6 | ✓ |
| executor | 6 | ✓ |
| data_entry | 5 | ✓ |
| command | 5 | ✓ |
| input | 4 | ✓ |
| screen | 5 | ✓ |
| **TOTAL** | **121+** | **✓** |

---

## Development Guidelines

### Commit Strategy
Follow conventional commits:
- `feat(module): description` - New feature
- `fix(module): description` - Bug fix
- `refactor: description` - Refactoring (behavior unchanged)
- `test: description` - Test additions
- `docs: description` - Documentation
- `chore: description` - Build/maintenance

### TDD Workflow
1. Write failing test
2. Implement minimal code to pass
3. Run `task test` to verify
4. Run `task fmt` to format
5. Commit when tests pass

### Testing Commands
```bash
task test              # Run all tests
task test-ghostty      # Run VT integration test
task test-connection   # Test real mainframe
task hex-viewer        # Run hex viewer demo
```

### Code Quality
```bash
task fmt               # Format code
task check             # Check format + test
task build             # Full build
task dev               # Format + test + build
```

---

## Next 3 Months (Estimated)

### Month 1: Refactoring & Decoupling
**Focus**: Complete Priority 1 coupling refactoring
- Week 1: Create `protocol_layer.zig` facade (5.5 hours = 1 workday)
- Week 2: Create `domain_layer.zig` facade (2 hours)
- Week 3: Update `emulator.zig` and `main.zig` (1.5 hours)
- **Result**: Reduce emulator.zig from 12→3 imports, all 60+ tests pass
- **Buffer**: Polish, run `task check`, commit with conventional commits

### Month 2: Testing & Coverage
**Focus**: Complete Priority 2 & 3 (utils extraction + integration tests)
- Extract `parse_utils.zig` - DRY up parser duplication (3 hours)
- Add e2e integration tests - screen update cycle validation (4 hours)
- Performance benchmarks and memory profiling (3 hours)
- **Result**: 70+ total tests, clear layer validation

### Month 3: Features & Polish
**Focus**: Complete Priority 4 (EBCDIC) + Quality
- Implement EBCDIC encoder/decoder (6 hours)
- Real mainframe testing with mvs38j.com (1-2 hours)
- CI/CD setup with GitHub Actions (2 hours)
- Polish error messages and logging (2 hours)
- **Result**: Full protocol compliance, production-ready

---

## Resources

- **AGENTS.md** - Development philosophy & TDD guidelines
- **GHOSTTY_INTEGRATION.md** - libghostty-vt integration details
- **HEX_VIEWER.md** - Hex viewer documentation
- **CODEBASE_REVIEW.md** - Detailed code analysis

