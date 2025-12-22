# v0.11.0 Implementation Plan

**Start Date**: Dec 22, 2025  
**Target Completion**: Late January 2025 (7 weeks)  
**Current Version**: v0.10.3 (Production-hardened)  
**Baseline Tests**: 250+ tests, all passing ✓

---

## Phase 1: Advanced Protocol (Weeks 1-2)

### Target Completion: v0.11.0-alpha
**Effort**: 30-35 hours  
**New Tests Target**: 50+ tests  
**Success Criteria**: All tests passing, zero compiler warnings, code formatted

---

### A1: Structured Field Extensions (WSF) - 12 hours

**Objective**: Complete Write Structured Field (WSF) support for advanced 3270 features

**Architecture**:
```
structured_fields.zig (existing)
  ├── WSFCommand parsing
  ├── 3270 Data Stream attributes
  ├── Font/charset negotiation
  ├── Color palette support
  └── Image integration
```

**Scope**:
1. **Core WSF Parser** (3h)
   - Parse WSF command variants (5-7 types)
   - Handle variable-length field structures
   - Error recovery for malformed fields
   - Tests: 8-10 tests

2. **3270 Data Stream Attributes** (2h)
   - Attribute type parsing (foreground, background, intensity, etc.)
   - Attribute encoding/decoding
   - Validation and constraints
   - Tests: 6-8 tests

3. **Font & Charset Negotiation** (3h)
   - Font selection protocol
   - Character set switching
   - Code page negotiation
   - Tests: 8-10 tests

4. **Color Palette Support** (2h)
   - Palette definition parsing
   - Color mapping and remapping
   - Extended color support
   - Tests: 4-6 tests

5. **Integration & Documentation** (2h)
   - Update REST API for WSF commands
   - Protocol guide documentation
   - Example usage in client

**Files**:
- Enhance: `src/structured_fields.zig`
- Test: Add 30+ tests to `src/structured_fields_test.zig` (if needed)
- Docs: `docs/WSF_GUIDE.md`

**Success Metrics**:
- [ ] Parse all WSF command variants without errors
- [ ] 30+ new tests covering all WSF scenarios
- [ ] Zero regressions in existing 250+ tests
- [ ] Documentation complete with examples
- [ ] Integration tests with domain_layer

---

### A2: Advanced Printing Support (LU3+) - 15 hours

**Objective**: Complete LU3 and LU4 printing with SCS (SAA Composite Sequence) support

**Architecture**:
```
lu3_printer.zig (enhance existing)
  ├── Print session lifecycle
  ├── SCS command processor (50+ commands)
  ├── Font selection & negotiation
  ├── Output routing (file, network, queue)
  └── Print metrics & monitoring

print_driver.zig (new example)
  └── Complete driver demonstrating LU3
```

**Scope**:
1. **Print Session Lifecycle** (3h)
   - Session start/end handling
   - Print job queuing
   - Job status tracking
   - Tests: 6-8 tests

2. **SCS Command Processing** (5h)
   - Implement 40-50 SCS commands
   - Page formatting (line spacing, tabs, justification)
   - Vertical positioning
   - Font switching
   - Tests: 15-20 tests

3. **Font Selection & TN3270E Negotiation** (3h)
   - Font selection protocol
   - Code page negotiation
   - Font validation
   - Tests: 8-10 tests

4. **Output Routing** (2h)
   - File output (text, PDF structure)
   - Network routing
   - Print queue management
   - Tests: 4-6 tests

5. **Metrics & Monitoring** (2h)
   - Print job statistics
   - Page counts, character counts
   - Output file sizes
   - Tests: 3-5 tests

**Files**:
- Enhance: `src/lu3_printer.zig`
- New: `src/print_driver.zig` (example)
- Test: Add 40+ tests to `src/lu3_printer_test.zig`
- Docs: `docs/LU3_PRINTING_GUIDE.md`

**Success Metrics**:
- [ ] Full LU3 session support operational
- [ ] 50+ SCS commands tested and documented
- [ ] 40+ new tests, all passing
- [ ] Example print driver working
- [ ] Integration with REST API complete
- [ ] No regressions in existing tests

---

### F1: Property-Based Testing Framework - 12 hours

**Objective**: Implement comprehensive property-based testing for protocol robustness

**Architecture**:
```
property_testing.zig (new)
  ├── Generator library
  ├── Shrinking framework
  ├── Property definitions
  └── Test execution engine

protocol_properties.zig (new)
  ├── Command properties
  ├── Parser properties
  ├── Field properties
  └── Screen rendering properties
```

**Scope**:
1. **Generator Library** (3h)
   - Arbitrary value generator trait/interface
   - Generators for protocol types:
     - Command codes (0x0000-0xFFFF)
     - Order codes
     - Field attributes
     - Screen addresses
     - Buffer content
   - Composable generators
   - Tests: 5-7 tests

2. **Shrinking Framework** (3h)
   - Shrinking strategies for generated values
   - Minimal failing case extraction
   - Shrink history tracking
   - Tests: 4-6 tests

3. **100+ Property Definitions** (4h)
   - Command parsing properties:
     - Parse → Format → Parse roundtrip
     - Parser never crashes on random bytes
     - All parse errors recoverable
   - Field properties:
     - Field creation always succeeds
     - Field storage valid after writes
     - Field cache consistent with underlying data
   - Screen rendering:
     - Rendering never crashes
     - Screen state consistent after commands
   - Buffer management:
     - Allocations tracked correctly
     - No memory leaks
     - Buffer boundaries respected
   - Tests: 50+ property test cases

4. **Test Execution & Reporting** (2h)
   - Test runner with configurable iterations
   - Failure reporting with minimal cases
   - Integration with CI/CD
   - Tests: 2-3 tests

**Files**:
- New: `src/property_testing.zig`
- New: `src/protocol_properties.zig`
- New: `src/property_testing_test.zig` (60+ tests)
- Docs: `docs/PROPERTY_TESTING_GUIDE.md`

**Success Metrics**:
- [ ] 100+ property definitions created
- [ ] Fuzzer finds regressions within 5 seconds
- [ ] Shrinking produces minimal failing cases
- [ ] 20+ edge cases discovered and documented
- [ ] 60+ property tests, all passing
- [ ] Framework integrated into CI/CD

---

## Phase 1 Completion Checklist

- [ ] **A1: WSF Support**
  - [ ] Structured field parsing complete
  - [ ] 30+ tests passing
  - [ ] Documentation written
  - [ ] Example code working

- [ ] **A2: LU3 Printing**
  - [ ] Print session lifecycle complete
  - [ ] 50+ SCS commands implemented
  - [ ] 40+ tests passing
  - [ ] Example driver working

- [ ] **F1: Property Testing**
  - [ ] Generator library complete
  - [ ] 100+ properties defined
  - [ ] 60+ tests passing
  - [ ] Framework documented

- [ ] **Integration & QA**
  - [ ] All 300+ tests passing
  - [ ] Zero compiler warnings
  - [ ] Code formatted with `zig fmt`
  - [ ] All new code follows TDD

- [ ] **Release Preparation**
  - [ ] Version bumped to v0.11.0-alpha
  - [ ] GitHub Release created
  - [ ] CHANGELOG updated
  - [ ] Documentation published

---

## Implementation Strategy

### TDD Workflow
1. Write failing test first (Red)
2. Implement minimal code to pass (Green)
3. Run full test suite to ensure no regressions
4. Refactor if needed (Refactor)
5. Format code with `zig fmt`
6. Commit with conventional message

### Commit Discipline
- Structural changes separate from behavioral changes
- Small, focused commits (one feature per commit)
- All tests passing before commit
- Conventional commit format: `feat(module): description`

### Quality Gates
- [ ] `task test` - All tests passing
- [ ] `task check` - Format check + tests
- [ ] `task build` - Full build successful
- [ ] Code review of complex logic

---

## Risk Mitigation

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| WSF complexity underestimated | Medium | Medium | Break into smaller tasks, incremental testing |
| SCS command count too high | Medium | Medium | Focus on 30 most common commands first |
| Property generation too slow | Low | Medium | Implement caching, optimize generators |
| Integration issues | Medium | Low | Test with existing modules early and often |

### Schedule Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Scope creep | High | High | Stick to 3 items only, defer others |
| Learning curve for properties | Medium | Medium | Start with simple properties, iterate |
| Unforeseen blockers | Low | High | Daily testing, early integration |

---

## Success Metrics for Phase 1

**Code Quality**:
- [ ] 300+ tests (50+ new)
- [ ] 100% test pass rate
- [ ] Zero compiler warnings
- [ ] Zero code formatting violations

**Features**:
- [ ] WSF fully parsed and validated
- [ ] LU3 printing operational with example
- [ ] Property-based testing framework usable

**Performance**:
- [ ] No regressions from v0.10.3
- [ ] Parser still 500+ MB/s
- [ ] Field operations still O(1)

**Documentation**:
- [ ] WSF guide complete
- [ ] LU3 printing guide complete
- [ ] Property testing guide complete
- [ ] Example code for each feature

---

## Next Phases (Deferred)

### Phase 2: Performance & Reliability (Weeks 3-4)
- B1: Advanced Allocator Patterns (ring buffer, fixed-size pool)
- B3: Zero-Copy Network Parsing
- F2: Stress Testing & Chaos Engineering

### Phase 3: Ecosystem & Integration (Weeks 5-6)
- C1: Language Bindings (C, Python)
- C3: OpenTelemetry Integration
- E1: Windows Support

### Phase 4: Polish & Release (Week 7)
- D1: VS Code Extension (debugging)
- G1: Vertical Integration Guides
- Final documentation and release

---

**Last Updated**: Dec 22, 2025  
**Status**: Ready for Phase 1 implementation
