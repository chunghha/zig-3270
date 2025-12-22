# v0.8.1 Development Plan

**Target Release**: Early January 2025  
**Estimated Duration**: 1-2 weeks (7-10 hours)  
**Version**: 0.8.1 (Minor enhancement release)  
**Status**: Starting development

---

## Overview

v0.8.1 focuses on **Documentation Enhancement**, **Testing Infrastructure**, and **Performance Tooling**. These are quality-of-life improvements that complement the production-ready v0.8.0 release.

---

## Priority Items

### Item 1: Protocol Reference Update (5b) - 2-3 hours

**What**: Comprehensive TN3270 protocol specification

**Current State**:
- `docs/PROTOCOL.md` exists (535 lines)
- Basic command reference
- Limited structured field details

**Enhancements**:
- Add detailed command code tables with all variants
- Field attribute encoding with examples
- Structured field format specifications for v0.8.0 types
- Keyboard/AID mapping reference
- Session negotiation flow diagram
- Error codes and responses
- RFC references (RFC 1576, RFC 1647)
- Side-by-side hex/ASCII examples throughout
- Quick reference tables for developers

**Target Sections**:
1. Command codes (complete reference)
2. Order codes (all types)
3. Field attributes (with color, highlighting, protection)
4. Structured fields (extended types from v0.8.0)
5. Keyboard/AID mapping (complete table)
6. Session negotiation (detailed flow)
7. Error handling (codes and recovery)
8. Known implementation limits
9. RFC references

**Success Criteria**:
- [ ] 1000+ lines of specification
- [ ] Side-by-side hex/ASCII examples
- [ ] Complete command reference
- [ ] Complete field attribute reference
- [ ] Quick reference tables
- [ ] Diagrams for complex sequences

**File**: `docs/PROTOCOL.md` (enhance existing, add ~500-700 lines)

---

### Item 2: Fuzzing Framework (6a) - 3-4 hours

**What**: Standalone fuzzing framework for protocol robustness

**Current State**:
- FuzzTester in parser.zig (partial implementation)
- No corpus management
- No crash reporting

**Implementation**:
- **File**: `src/fuzzing.zig` (new, 300+ lines)
- Fuzzer implementations:
  - Command code fuzzing (all 256 possible bytes)
  - Data stream fuzzing (random valid/invalid sequences)
  - Field attribute fuzzing (all combinations)
  - Address fuzzing (boundary conditions)
- Corpus management:
  - Store known-good inputs
  - Seed with real-world sessions
  - Track coverage metrics
- Crash reporting:
  - Automatic test case minimization
  - Stack trace capture
  - Reproducible test generation
- Integration with benchmark suite

**Tests**: 8+ covering:
- Fuzzer initialization
- Corpus loading
- Crash detection
- Minimization
- Coverage tracking

**Success Criteria**:
- [ ] Standalone fuzzer compiles
- [ ] Finds no crashes in v0.8.0 code
- [ ] Corpus management working
- [ ] 8+ tests passing
- [ ] Zero warnings

**File**: `src/fuzzing.zig` (new)

---

### Item 3: Performance Regression Testing (6b) - 2-3 hours

**What**: Automated detection of performance regressions

**Current State**:
- Benchmarks exist but manual comparison
- No baseline storage
- No regression detection

**Enhancement to Taskfile.yml**:
- New tasks:
  - `task benchmark:baseline` - Save current baseline
  - `task benchmark:check` - Compare to baseline
  - `task benchmark:report` - Generate regression report
- Implementation:
  - Baseline storage in JSON format
  - Regression detection (10% warning, 20% fail)
  - Per-module tracking
  - CI/CD integration hints

**Tests**: 6+ covering:
- Baseline saving
- Regression detection logic
- Report generation
- Threshold triggering

**Success Criteria**:
- [ ] Baseline file created
- [ ] Regression detection implemented
- [ ] Tasks integrate with Taskfile
- [ ] 6+ tests passing
- [ ] CI/CD documentation

**Files**: 
- `Taskfile.yml` (enhance with 50+ lines)
- `src/performance_regression.zig` (new, 200+ lines)

---

## Implementation Schedule

### Day 1: Protocol Reference (2-3 hours)
- [ ] Research comprehensive TN3270 specs
- [ ] Expand PROTOCOL.md with all details
- [ ] Add hex/ASCII examples throughout
- [ ] Create quick reference tables
- [ ] Add RFC references

### Day 2-3: Fuzzing Framework (3-4 hours)
- [ ] Write tests first (TDD)
- [ ] Implement `fuzzing.zig` core
- [ ] Corpus management
- [ ] Crash reporting
- [ ] Integration tests
- [ ] Zero warnings validation

### Day 3: Performance Regression Testing (2-3 hours)
- [ ] Baseline storage implementation
- [ ] Regression detection logic
- [ ] Taskfile integration
- [ ] Tests for all components
- [ ] CI/CD documentation

---

## Testing Strategy

Following TDD (Red → Green → Refactor):

1. Write failing tests for each component
2. Implement minimal code to pass
3. Run all tests (407 existing + new)
4. Refactor for clarity
5. Ensure zero warnings
6. Commit with conventional messages

---

## Success Criteria

### Code Quality
- [ ] All 407 existing tests still pass
- [ ] 15+ new tests added
- [ ] Zero compiler warnings
- [ ] 100% code formatting
- [ ] Conventional commits

### Features Complete
- [ ] PROTOCOL.md comprehensive (1000+ lines)
- [ ] Fuzzing framework functional
- [ ] Performance regression detection working
- [ ] Taskfile tasks integrated
- [ ] Documentation complete

### Integration
- [ ] All modules compile
- [ ] Build succeeds
- [ ] Tests pass
- [ ] No regressions

---

## Estimated Totals

- **Documentation**: 500-700 lines added to PROTOCOL.md
- **Code**: 500+ lines (fuzzing + regression testing)
- **Tests**: 15+ new tests
- **Total Time**: 7-10 hours
- **Status**: Ready to start

---

## Post v0.8.1

After v0.8.1 is released, future work may include:

### v0.9.0 (Future)
- Multi-session management
- Load balancing and failover
- Audit logging and compliance
- Custom protocol extensions

### v1.0.0 (Future)
- Comprehensive test coverage (>300 tests) ✓ (already have 407)
- Long-term API stability guarantee
- Commercial support options
- Production SLA documentation

---

## Next Steps

1. ✓ Baseline v0.8.0 verified (all tests pass)
2. Start Item 1: Protocol Reference Update
3. Implement Item 2: Fuzzing Framework
4. Implement Item 3: Performance Regression
5. Final testing and validation
6. Release v0.8.1

---

**Status**: Ready to start development  
**Created**: Dec 22, 2024  
**Target Completion**: Jan 5, 2025
