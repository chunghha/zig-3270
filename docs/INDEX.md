# Documentation Index

Welcome to zig-3270 documentation. This index links all available guides organized by topic.

## Getting Started

- **QUICKSTART.md** - Quick setup and basic usage
- **README.md** - Project overview and features

## Architecture & Design

- **ARCHITECTURE.md** - System design and module organization (v0.5.1+)
- **CODEBASE_REVIEW.md** - Detailed code analysis and patterns

## Core Protocol & Features

- **API_GUIDE.md** - Public API reference and usage
- **WSF_GUIDE.md** - Structured Fields (Attributes, Fonts, Colors, Images) - v0.11.0
- **LU3_PRINTING_GUIDE.md** - Advanced printing with SCS commands - v0.11.0
- **PROPERTY_TESTING_GUIDE.md** - Property-based testing framework - v0.11.0
- **GHOSTTY_INTEGRATION.md** - libghostty-vt terminal integration
- **HEX_VIEWER.md** - Hex viewer tool for protocol debugging

## Performance & Optimization

- **ADVANCED_ALLOCATORS.md** - Memory allocation patterns (ring buffer, fixed pool, scratch) - v0.11.1
- **ZERO_COPY_PARSING.md** - Zero-copy network parsing with buffer views - v0.11.1
- **PERFORMANCE.md** - Performance baselines and metrics
- **PERFORMANCE_TUNING.md** - Configuration for optimal performance

## Operations & Testing

- **OPERATIONS.md** - Installation, deployment, troubleshooting
- **CHAOS_TESTING.md** - Chaos engineering framework with 50+ scenarios - v0.11.1
- **CONFIG_REFERENCE.md** - Configuration options and defaults
- **DEPLOYMENT.md** - Production deployment guide
- **INTEGRATION_ADVANCED.md** - Advanced integration patterns

## User Features

- **USER_GUIDE.md** - Interactive mode and CLI usage

## Development

- **AGENTS.md** - Development philosophy, TDD guidelines, commit discipline
- **V0_11_0_SUMMARY.md** - v0.11.0 planning and strategic opportunities
- **V0_11_0_PHASE1_COMPLETE.md** - v0.11.0 Phase 1 completion summary
- **V0_11_0_PLANNING.md** - Detailed v0.11.0 planning analysis
- **V0_11_1_IMPLEMENTATION.md** - v0.11.1 Phase 2 implementation summary

## Examples

The examples/ directory contains working programs:

- `batch_processor.zig` - High-throughput batch operations
- `session_monitor.zig` - Real-time session monitoring
- `load_test.zig` - Load testing framework
- `audit_analysis.zig` - Audit log analysis tool

## Quick Links by Version

### v0.10.3 (Latest Production)
- Production-hardened with security audit
- Resource management and disaster recovery
- Comprehensive documentation and examples

### v0.11.0-alpha (Advanced Protocol)
- Structured Fields (WSF) support
- LU3 printing with SCS commands
- Property-based testing framework

### v0.11.1-beta (Performance & Reliability)
- Advanced allocator patterns for 10-100x faster allocations
- Zero-copy network parsing for 2x latency improvement
- Chaos engineering framework with 50+ fault scenarios

## By Use Case

### Building a New Feature
1. Start with AGENTS.md for TDD guidelines
2. Reference API_GUIDE.md for existing APIs
3. Add tests following the TDD pattern
4. Use ZERO_COPY_PARSING.md if parsing needed
5. Use ADVANCED_ALLOCATORS.md for memory optimization

### Deploying to Production
1. Read OPERATIONS.md for setup checklist
2. Review DEPLOYMENT.md for production configuration
3. Configure monitoring per PERFORMANCE_TUNING.md
4. Set up disaster recovery per OPERATIONS.md

### Optimizing Performance
1. Baseline with PERFORMANCE.md
2. Review PERFORMANCE_TUNING.md for configuration
3. Consider ADVANCED_ALLOCATORS.md for allocation patterns
4. Use ZERO_COPY_PARSING.md to avoid copies

### Testing Reliability
1. Write tests per AGENTS.md (TDD)
2. Use CHAOS_TESTING.md for fault injection
3. Validate with PROPERTY_TESTING_GUIDE.md
4. Measure with profiler (PERFORMANCE.md)

### Integrating with Code
1. Review INTEGRATION_ADVANCED.md patterns
2. Understand allocator options (ADVANCED_ALLOCATORS.md)
3. Choose parsing approach (ZERO_COPY_PARSING.md or API_GUIDE.md)
4. Handle errors per error_context documentation

## Documentation Statistics

| Category | Files | Lines |
|----------|-------|-------|
| Core | 5 | 2,000+ |
| Features | 7 | 3,500+ |
| Performance | 3 | 2,000+ |
| Operations | 5 | 3,000+ |
| Development | 5 | 2,500+ |
| **Total** | **25+** | **13,000+** |

## Reading Order by Level

### Beginner
1. QUICKSTART.md
2. USER_GUIDE.md
3. API_GUIDE.md
4. README.md

### Intermediate
1. ARCHITECTURE.md
2. INTEGRATION_ADVANCED.md
3. PERFORMANCE_TUNING.md
4. CONFIG_REFERENCE.md

### Advanced
1. ADVANCED_ALLOCATORS.md
2. ZERO_COPY_PARSING.md
3. CHAOS_TESTING.md
4. CODEBASE_REVIEW.md

### Expert
1. AGENTS.md (development methodology)
2. Source code in src/
3. V0_11_0_PLANNING.md (strategic analysis)
4. V0_11_1_IMPLEMENTATION.md (technical deep dive)

## Version Timeline

```
v0.5.1 → v0.6.0 → v0.7.0 → v0.9.0 → v0.10.3 → v0.11.0-alpha → v0.11.1-beta → v0.11.0-rc1
   ↓        ↓        ↓         ↓         ↓           ↓              ↓              ↓
Protocol  Features Features  Enterprise Production Protocol-2   Performance    Ecosystem
Parsing   & UI     & Network  Features  Hardening   & Testing    & Reliability  & Windows
```

## Contributing

See AGENTS.md for contribution guidelines including:
- TDD methodology
- Commit discipline
- Code quality standards
- Review process

## Support

- Issues: GitHub Issues
- Discussions: GitHub Discussions
- Docs: This directory
- Examples: examples/ directory

## See Also

- **Source Code**: `src/` directory
- **Tests**: Test blocks in source files + integration tests
- **Examples**: `examples/` directory
- **Build**: `build.zig` and `Taskfile.yml`
