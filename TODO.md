# TODO & Project Roadmap

## Summary

**Status**: Active development with solid foundation  
**Test Coverage**: 60+ unit tests, all passing  
**Codebase Size**: ~3,038 lines of Zig  
**Key Achievement**: Hex viewer implementation complete ✓  

---

## Priority 1: Documentation (High Impact)

### Documentation Tasks
- [ ] **Create README.md** - Project overview, quick-start, feature list
  - *Impact*: Makes project accessible to new contributors
  - *Effort*: 2-3 hours
  
- [ ] **Create ARCHITECTURE.md** - System design and module diagrams
  - *Impact*: Guides future development and refactoring
  - *Effort*: 3-4 hours
  
- [ ] **Document protocol.zig** - TN3270 specification and constants
  - *Impact*: Reference for protocol implementation
  - *Effort*: 2 hours

---

## Priority 2: Refactoring (Code Quality)

### Dependency Management
- [ ] **Reduce main.zig coupling** - Extract facade/adapter layer
  - *Problem*: main.zig imports 18 modules (too many)
  - *Solution*: Create intermediate abstraction layer
  - *Effort*: 4-6 hours
  
- [ ] **Extract parsing utilities** - Common patterns across modules
  - *Problem*: Duplication in parser.zig and stream_parser.zig
  - *Solution*: Create utils module with shared parsing functions
  - *Effort*: 2-3 hours

### Architecture Improvements
- [ ] **Implement layered architecture**
  ```
  Layer 1: Protocol (protocol.zig, parser.zig, stream_parser.zig)
  Layer 2: Domain (screen.zig, field.zig, terminal.zig)
  Layer 3: Application (client.zig, executor.zig)
  ```
  - *Impact*: Better testability and maintainability
  - *Effort*: 6-8 hours

---

## Priority 3: Testing (Coverage)

### Integration Tests
- [ ] **Add end-to-end tests** - Combine multiple modules
  - Examples: full screen update cycle, field parsing → display
  - *Effort*: 3-4 hours

- [ ] **Add hex_viewer stress tests** - Large files (10KB+)
  - *Effort*: 1-2 hours

### Performance
- [ ] **Add parsing benchmarks** - Measure throughput
  - *Effort*: 2 hours

- [ ] **Profile memory allocation** - Identify hotspots
  - *Effort*: 3 hours

---

## Priority 4: Features (User Experience)

### Core Features
- [ ] **EBCDIC encoding support**
  - *Status*: Currently ASCII only
  - *Impact*: Full 3270 protocol compatibility
  - *Effort*: 4-6 hours

- [ ] **Keyboard mapping configuration**
  - *Status*: Hard-coded currently
  - *Impact*: Better user control
  - *Effort*: 3-4 hours

- [ ] **Session persistence**
  - *Status*: Not implemented
  - *Impact*: Save/restore terminal state
  - *Effort*: 5-6 hours

### UX Enhancements
- [ ] **Screen history & scrollback**
  - *Effort*: 4-5 hours

- [ ] **Advanced terminal attributes** (colors, bold, etc.)
  - *Effort*: 3-4 hours

---

## Priority 5: Quality Assurance

### Error Handling
- [ ] **Enhance error messages**
  - Add context and recovery suggestions
  - *Effort*: 2 hours

- [ ] **Add debug logging**
  - Log protocol interactions for troubleshooting
  - *Effort*: 3 hours

### Performance
- [ ] **Profile for bottlenecks**
  - *Effort*: 3 hours

- [ ] **Optimize memory patterns**
  - Reduce allocations in parsing hot paths
  - *Effort*: 4-6 hours

### Integration
- [ ] **Test with real mainframe** (mvs38j.com)
  - *Effort*: 1 hour

- [ ] **Add CI/CD pipeline** (GitHub Actions)
  - *Effort*: 2 hours

---

## Completed ✓

- [x] **Implement hex viewer** (COMPLETED - Dec 21)
  - Side-by-side hex and ASCII display
  - Configurable bytes per line
  - 7 unit tests, example program
  - Integration into main build system

---

## Metrics & Progress

### Code Statistics
```
Total Lines: 3,038
Modules: 23
Tests: 60+
Test Pass Rate: 100%
```

### Module Breakdown
- Core Protocol: 5 modules (654 lines)
- Terminal & Display: 6 modules (892 lines)
- Network: 3 modules (562 lines)
- Commands & Data: 4 modules (521 lines)
- Utilities & Examples: 5 modules (409 lines)

### Test Coverage by Module
| Module | Tests | Status |
|--------|-------|--------|
| hex_viewer | 7 | ✓ |
| terminal | 8 | ✓ |
| field | 6 | ✓ |
| executor | 6 | ✓ |
| data_entry | 5 | ✓ |
| command | 5 | ✓ |
| input | 4 | ✓ |
| screen | 5 | ✓ |
| **TOTAL** | **60+** | **✓** |

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

### Month 1
- Complete Priority 1 & 2 (Documentation + Refactoring)
- Reduce main.zig to < 10 imports
- Create architecture documentation

### Month 2
- Complete Priority 3 & 4 (Testing + Core Features)
- Add EBCDIC support
- Implement basic session persistence

### Month 3
- Complete Priority 5 (Quality)
- Performance optimization
- Real mainframe testing
- CI/CD setup

---

## Resources

- **AGENTS.md** - Development philosophy & TDD guidelines
- **GHOSTTY_INTEGRATION.md** - libghostty-vt integration details
- **HEX_VIEWER.md** - Hex viewer documentation
- **CODEBASE_REVIEW.md** - Detailed code analysis

