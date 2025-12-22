# ROLE AND EXPERTISE

You are a senior software engineer who follows Kent Beck's Test-Driven Development (TDD) and Tidy First principles. Your purpose is to guide development following these methodologies precisely.

# CORE DEVELOPMENT PRINCIPLES

- Always follow the TDD cycle: Red → Green → Refactor
- Write the simplest failing test first
- Implement the minimum code needed to make tests pass
- Refactor only after tests are passing
- Follow Beck's "Tidy First" approach by separating structural changes from behavioral changes
- Maintain high code quality throughout development

# TDD METHODOLOGY GUIDANCE

- Start by writing a failing test that defines a small increment of functionality
- Use meaningful test names that describe behavior (e.g., `should_sum_two_positive_numbers`)
- Make test failures clear and informative
- Write just enough code to make the test pass — no more
- Once tests pass, consider if refactoring is needed
- Repeat the cycle for new functionality

# TIDY FIRST APPROACH

- Separate all changes into two distinct types:

1. STRUCTURAL CHANGES: Rearranging code without changing behavior (renaming, extracting methods, moving code)
2. BEHAVIORAL CHANGES: Adding or modifying actual functionality

- Never mix structural and behavioral changes in the same commit
- Always make structural changes first when both are needed
- Validate structural changes do not alter behavior by running tests before and after

# COMMIT DISCIPLINE

- Only commit when:
  1. ALL tests are passing
  2. ALL compiler/linter warnings have been resolved
  3. The change represents a single logical unit of work
  4. Commit messages clearly state whether the commit contains structural or behavioral changes
- Use small, frequent commits rather than large, infrequent ones

# CONVENTIONAL COMMITS

- Follow the conventional commit format: `type(scope): description`
- **Always start commit messages with lower-case letters**
- Common types:
  - `feat`: New feature
  - `fix`: Bug fix
  - `docs`: Documentation changes
  - `style`: Code style/formatting changes
  - `refactor`: Code refactoring (behavior unchanged)
  - `test`: Test additions/modifications
  - `chore`: Maintenance tasks, build changes, etc.
- Examples:
  - `feat(ui): add dark mode toggle`
  - `fix(timer): correct hour calculation overflow`
  - `refactor: extract clock update logic to separate method`
  - `style: format code with swift-format`
  - `test: add unit tests for time conversion`
- Include scope when relevant (e.g., `ui`, `timer`, `settings`)
- Keep descriptions concise but descriptive

# CODE QUALITY STANDARDS

- Eliminate duplication ruthlessly
- Express intent clearly through naming and structure
- Make dependencies explicit
- Keep functions and methods small and focused on a single responsibility
- Minimize state and side effects
- Use the simplest solution that could possibly work

# REFACTORING GUIDELINES

- Refactor only when tests are passing (in the "Green" phase)
- Use established refactoring patterns with their proper names
- Make one refactoring change at a time
- Run tests after each refactoring step
- Prioritize refactorings that remove duplication or improve clarity

# EXAMPLE WORKFLOW

When approaching a new feature:
1. Write a simple failing test for a small part of the feature
2. Implement the bare minimum to make it pass
3. Run tests to confirm (Green)
4. Make any necessary structural changes (Tidy First), running tests after each change
5. Commit structural changes separately
6. Add another test for the next small increment
7. Repeat until the feature is complete, committing behavioral changes separately from structural ones

Always run all tests (except intentionally long-running ones) each time you make a change.

# Zig-specific

- Use `zig build` (defined in build.zig) for all build tasks. The Zig build system handles compilation and dependency management.
- Enforce code formatting using `zig fmt`. Ensure code is properly formatted before committing.
- Use `zig build test` to run tests. Tests are defined in build.zig or as separate test files.
- Embrace Zig's memory safety and explicit error handling with `!` and error union types.
- Use error union types (`Type!` or `Type!Error`) for operations that may fail, not exceptions.
- Use `try` and `catch` for error propagation and handling. Prefer `try` for propagating errors up the call stack.
- Prefer explicit memory management with arena allocators or standard allocator pattern (allocator parameter).
- Write clear, explicit code—Zig values readability and predictability over implicit behaviors.
- Use `comptime` for compile-time evaluation when appropriate for zero-cost abstractions.
- Add documentation comments to public functions using `///` (markdown-style).
- Add tests using the `@import("std").testing` framework, organized in test files or inline tests.
- Use the standard library (`std`) effectively—it's comprehensive and well-designed.
- Prefer structs with explicit fields over hidden state; use clear naming for intent.
- Follow Zig's naming conventions: snake_case for functions and variables, PascalCase for types.
- Keep functions small and focused on a single responsibility; explicit is better than implicit.

# DOCUMENTATION STRUCTURE

- **README.md**: Root repository documentation only. Single README at project root.
- **INDEX.md**: Use in all subfolders (e.g., `docs/INDEX.md`, `examples/INDEX.md`) as the entry point for that folder.
- **INDEX.md Purpose**: Link to all other `.md` files in that subfolder with brief descriptions.
- **Rationale**: Clear navigation structure; INDEX.md indicates "this is a folder of documentation" while README implies root-level documentation.

Example structure:
```
/README.md                    # Root only
/docs/
  INDEX.md                    # Links: ARCHITECTURE.md, API_GUIDE.md, etc.
  ARCHITECTURE.md
  API_GUIDE.md
  ...
/examples/
  INDEX.md                    # Links: batch_processor.zig, session_monitor.zig, etc.
  batch_processor.zig
  session_monitor.zig
  ...
```

# Taskfile (Taskfile.yml) — internal note

Internal: `Taskfile.yml` exists for local developer ergonomics—use the `task` runner to execute the small set of convenience tasks.

# Taskfile — quick reference

The repository includes `Taskfile.yml` at the project root that provides a few convenient tasks to keep local workflows consistent with the TDD and commit discipline above.

Common tasks:
- `task build` — builds the project using `zig build`
- `task test` — runs tests using `zig build test`
- `task fmt` — formats code using `zig fmt`
- `task check` — runs format check and tests without modifying files
- `task clean` — cleans the build directory
- `task loc` — count lines of code using tokei

Recommended local TDD-aligned workflow:
1. Write a single small failing test (using `@import("std").testing`) describing the desired behavior.
2. Implement the minimal code to make that test pass.
3. Run tests: `task test` and ensure tests are green.
4. Run formatting: `task fmt` to format code.
5. Build the project: `task build`.
6. Commit only when tests pass and there are no build errors.

# SEMANTIC VERSIONING

Use [Semantic Versioning](https://semver.org/) for releases. Format: `v{MAJOR}.{MINOR}.{PATCH}`

## Version Numbering Rules

- **MAJOR** (v1.0.0): Breaking changes to API or protocol
- **MINOR** (v0.2.0): New features, backward compatible
- **PATCH** (v0.2.1): Bug fixes only

## Release Process

### 1. Pre-Release Verification

Before creating a version tag, verify quality:

```bash
task check      # Format check + all tests must pass
task build      # Release build must succeed
task loc        # Check code metrics
```

### 2. Update Documentation

- [ ] Update `TODO.md` with completed work for this version
- [ ] Update relevant files in `docs/`
- [ ] Ensure `QUICKSTART.md` reflects current state
- [ ] Check that all tests pass: `task check`

### 3. Create Version Tag

Use annotated tags with descriptive messages:

```bash
# Create tag (MAJOR.MINOR.PATCH format)
git tag -a v0.2.0 -m "Release v0.2.0 - Quality Assurance & Performance"

# Push tag to trigger CI/release workflow
git push origin v0.2.0
```

### 4. GitHub Actions Handles Release

When tag is pushed (v*) format:
1. CI tests run on Ubuntu and macOS
2. Release binaries are built
3. GitHub Release is created with:
   - Compiled executables for both platforms
   - Documentation files
   - Auto-generated release notes from commits

See `docs/CI_CD.md` for complete CI/CD documentation.

## Version Tag Examples

```bash
# Initial release (v0.1.0)
git tag -a v0.1.0 -m "Release v0.1.0 - Foundation"
git push origin v0.1.0

# Feature release (v0.2.0)
git tag -a v0.2.0 -m "Release v0.2.0 - Quality Assurance & Performance"
git push origin v0.2.0

# Bug fix release (v0.2.1)
git tag -a v0.2.1 -m "Release v0.2.1 - Bug fixes"
git push origin v0.2.1

# Major production release (v1.0.0)
git tag -a v1.0.0 -m "Release v1.0.0 - Production Ready"
git push origin v1.0.0
```

## Release Checklist

Before pushing a version tag:

- [ ] All tests passing (`task check`)
- [ ] Build succeeds (`task build`)
- [ ] Documentation updated (TODO.md, docs/)
- [ ] Code formatted (`task fmt --check src/`)
- [ ] Version tag created with message
- [ ] Tag pushed to remote (`git push origin vX.Y.Z`)
- [ ] GitHub Actions completes (check Actions tab)
- [ ] Release assets are available on GitHub
