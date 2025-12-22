# zig-3270: User Guide

A high-performance TN3270 terminal emulator written in Zig for connecting to IBM mainframe systems.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Connecting to Mainframe](#connecting-to-mainframe)
- [Configuration](#configuration)
- [Using Connection Profiles](#using-connection-profiles)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)

---

## Installation

### From Source

#### Prerequisites
- Zig 0.15.2 or later
- Git
- Standard build tools (gcc/clang)

#### Build Steps

```bash
# Clone the repository
git clone https://github.com/chunghha/zig-3270.git
cd zig-3270

# Build the project
zig build

# Run tests to verify installation
zig build test

# Run the emulator
zig build run
```

### From Pre-compiled Binaries

Visit [GitHub Releases](https://github.com/chunghha/zig-3270/releases) to download pre-built binaries for:
- macOS (ARM64)
- Linux (x86_64)

---

## Quick Start

### 1. First Connection

```bash
# Connect to a mainframe with default settings
zig-3270 connect --host mainframe.example.com --port 23
```

### 2. Using a Connection Profile

```bash
# List available profiles
zig-3270 list-profiles

# Connect using a profile
zig-3270 connect --profile TSO
```

### 3. Interactive Terminal

Once connected, you'll see the terminal in interactive mode:
- Type normally to enter data in input fields
- Press Tab to move to next field
- Press Shift+Tab to move to previous field
- Press Enter to submit the form
- Press F3 to exit (or Ctrl+D)

---

## Connecting to Mainframe

### Basic Connection

```bash
zig-3270 connect --host 192.168.1.100 --port 23
```

### With Timeout

```bash
# Set 10 second timeout
zig-3270 connect --host mainframe.example.com --port 23 --timeout 10000
```

### With Verbose Logging

```bash
# Enable debug output
zig-3270 connect --host mainframe.example.com --verbose
```

### With Maximum Debug

```bash
# Enable trace-level logging
zig-3270 connect --host mainframe.example.com --debug
```

### Getting Help

```bash
# Show all available commands and options
zig-3270 help

# Show version
zig-3270 --version
```

---

## Configuration

### Configuration File Location

Configuration files are stored in the user's home directory:

```
~/.zig3270/
├── profiles.json           # Connection profiles
├── keyboard-config.json    # Keyboard mappings
└── session.dat             # Last session state (if enabled)
```

### Environment Variables

Set these environment variables to customize behavior:

```bash
# Set debug log level (error, warn, info, debug, trace)
export ZIG3270_LOG_LEVEL=debug

# Set keyboard profile
export ZIG3270_KEYBOARD_PROFILE=standard

# Disable auto-save
export ZIG3270_AUTO_SAVE=0
```

### Creating Configuration Manually

If config files don't exist, they're created with defaults on first run. You can also create them manually.

---

## Using Connection Profiles

### What Are Profiles?

Connection profiles store commonly-used settings for specific mainframes or applications. Instead of typing all parameters each time, you save them in a profile and reuse it.

### Built-in Profiles

The following profiles are pre-configured:

#### TSO (Time Sharing Option)
```bash
zig-3270 connect --profile TSO
```
Standard IBM mainframe TSO logon screen.

#### CICS (Customer Information Control System)
```bash
zig-3270 connect --profile CICS
```
CICS transaction server connection.

#### IMS (Information Management System)
```bash
zig-3270 connect --profile IMS
```
IMS DC (Data Communications) terminal.

#### Batch Job Monitor
```bash
zig-3270 connect --profile BATCH
```
Monitor batch job submissions.

### Creating a Custom Profile

1. Create `~/.zig3270/profiles.json`:

```json
{
  "my-test-server": {
    "host": "test.example.com",
    "port": 23,
    "timeout": 5000,
    "keyboard_profile": "standard",
    "auto_login": false
  }
}
```

2. Use the profile:

```bash
zig-3270 connect --profile my-test-server
```

### Profile Options

- `host`: IP address or hostname (required)
- `port`: TCP port number (default: 23)
- `timeout`: Connection timeout in milliseconds (default: 5000)
- `keyboard_profile`: Which keyboard layout to use (default: standard)
- `auto_login`: Auto-login with credentials (requires secure setup)
- `default_commands`: Commands to auto-execute on connection

---

## Keyboard Shortcuts

### Navigation
| Key | Action |
|-----|--------|
| Tab | Next input field |
| Shift+Tab | Previous input field |
| Home | First field on screen |
| End | Last field on screen |
| Ctrl+Home | Beginning of current field |
| Ctrl+End | End of current field |

### Editing
| Key | Action |
|-----|--------|
| Backspace | Delete character before cursor |
| Delete | Delete character at cursor |
| Ctrl+U | Clear current field |
| Ctrl+W | Delete word |
| Ctrl+A | Select all in field |

### Control
| Key | Action |
|-----|--------|
| Enter | Submit form / Send data |
| Escape | Interrupt / Cancel |
| Ctrl+C | Exit application (with confirmation) |
| Ctrl+D | Exit application |
| F3 / F4 | Function keys (configurable) |

### Screen Navigation
| Key | Action |
|-----|--------|
| Page Up | Scroll history backward |
| Page Down | Scroll history forward |
| Ctrl+L | Refresh screen |

### Function Keys
- F1 through F24 are transmitted to the mainframe
- Mappings depend on your keyboard configuration
- See `docs/CONFIG_REFERENCE.md` for customization

---

## Common Tasks

### Task 1: Connect and Navigate TSO

```bash
# 1. Connect to TSO
zig-3270 connect --profile TSO

# 2. Wait for "READY" prompt (or login screen)
# 3. Type your username
# 4. Press Tab to move to password field
# 5. Type password
# 6. Press Enter to submit

# 7. You should see the TSO menu
# 8. Type commands (e.g., "LISTCATS" to list catalogs)
# 9. Press Enter to execute
```

### Task 2: Monitor Screen Changes

While connected:

```bash
# View screen state (in another terminal)
zig-3270 dump-state

# This shows:
# - Current screen buffer
# - All fields and their attributes
# - Keyboard lock status
```

### Task 3: Save Session for Replay

```bash
# Record a session
zig-3270 connect --profile TSO --record mysession.bin

# Later, replay it
zig-3270 replay mysession.bin
```

### Task 4: Capture Screen to File

```bash
# Export current screen
zig-3270 export-screen output.txt

# Export as JSON
zig-3270 export-screen output.json --format json
```

### Task 5: Performance Analysis

```bash
# Run with profiler
zig-3270 connect --profile TSO --profile-performance

# This outputs:
# - Memory usage
# - Response times
# - Allocation statistics
# - Hot path analysis
```

### Task 6: Troubleshoot Connection Issues

```bash
# Enable debug logging
zig-3270 connect --host mainframe.example.com --debug

# This shows:
# - Protocol negotiations
# - Command/response details
# - Any errors with recovery suggestions
```

---

## Troubleshooting

### Cannot Connect to Mainframe

**Symptom**: "Connection refused" or timeout

**Solutions**:
1. Verify host and port are correct
   ```bash
   # Test with standard tools
   telnet mainframe.example.com 23
   nc -zv mainframe.example.com 23
   ```

2. Check firewall allows outbound port 23
   ```bash
   # On macOS
   sudo pfctl -s rules | grep 23
   
   # On Linux
   sudo iptables -L -n | grep 23
   ```

3. Increase timeout
   ```bash
   zig-3270 connect --host mainframe.example.com --timeout 15000
   ```

### Screen Appears Garbled

**Symptom**: Characters don't display correctly

**Causes & Solutions**:
- Terminal emulator doesn't support required escape sequences
- EBCDIC encoding mismatch
- Mainframe using different character set

**Fix**:
```bash
# Enable ANSI color support (if supported)
export TERM=xterm-256color

# Try different debug output
zig-3270 connect --host mainframe.example.com --debug
```

### Keyboard Input Not Working

**Symptom**: Typing doesn't appear on screen

**Causes**:
- Field is protected (read-only)
- Keyboard is locked by mainframe
- Wrong keyboard mapping

**Solutions**:
1. Check if field is editable (look for underline or outline)
2. Check keyboard status (should show "ready" in status bar)
3. Try Tab to move to an input field
4. Reset keyboard mapping
   ```bash
   zig-3270 connect --profile TSO --keyboard-reset
   ```

### Performance Issues

**Symptom**: Slow response times

**Solutions**:
1. Profile the session
   ```bash
   zig-3270 connect --profile TSO --profile-performance
   ```

2. Check network latency
   ```bash
   ping -c 5 mainframe.example.com
   ```

3. Monitor system resources
   ```bash
   # On macOS
   top -n 1 | head -15
   
   # On Linux
   top -b -n 1 | head -15
   ```

### Screen Doesn't Update

**Symptom**: Screen stays blank or frozen

**Solutions**:
1. Refresh screen
   ```bash
   # Press Ctrl+L in the emulator
   ```

2. Check connection status
   ```bash
   # Enable verbose logging
   zig-3270 connect --host mainframe.example.com --verbose
   ```

3. Reconnect
   ```bash
   # Exit with Ctrl+D and reconnect
   zig-3270 connect --host mainframe.example.com
   ```

### Lost Connection

**Symptom**: "Connection lost" message

**Solutions**:
1. The emulator will automatically retry (with exponential backoff)
2. To manually reconnect:
   ```bash
   zig-3270 connect --host mainframe.example.com
   ```

3. If auto-reconnect fails:
   - Check network connectivity
   - Verify mainframe is still running
   - Check firewall/proxy rules
   - Try from different network

---

## Advanced Usage

### Custom Keyboard Configuration

See `docs/CONFIG_REFERENCE.md` for details on:
- Creating custom keyboard layouts
- Function key mappings
- Modifier key combinations
- Saving configurations

### Session Persistence

The emulator automatically saves session state:
- Screen contents
- Field data
- Cursor position
- Keyboard state

Resume a saved session:
```bash
zig-3270 resume --session last
```

### Protocol Snooping

Capture and analyze protocol traffic:
```bash
# Capture protocol events
zig-3270 connect --profile TSO --snoop-log traffic.log

# View captured traffic
cat traffic.log
```

### Performance Tuning

Adjust performance parameters in `~/.zig3270/profiles.json`:

```json
{
  "performance-tuned": {
    "host": "mainframe.example.com",
    "buffer_size": 8192,
    "max_fields": 500,
    "cache_enabled": true
  }
}
```

---

## Getting Help

### Documentation

- **QUICKSTART.md** - Fast setup and testing
- **docs/ARCHITECTURE.md** - System design
- **docs/PROTOCOL.md** - TN3270 protocol details
- **docs/CONFIG_REFERENCE.md** - Configuration options
- **docs/PERFORMANCE.md** - Performance tuning

### Command Line Help

```bash
# Full help
zig-3270 --help

# Specific command help
zig-3270 connect --help
zig-3270 replay --help
```

### Reporting Issues

Found a bug? Report it on [GitHub Issues](https://github.com/chunghha/zig-3270/issues)

Include:
- zig-3270 version (`zig-3270 --version`)
- OS and version
- Steps to reproduce
- Error messages and logs

---

## Tips & Best Practices

1. **Use Connection Profiles** - Save time with profiles instead of typing parameters
2. **Enable Auto-Save** - Session state is automatically saved for recovery
3. **Monitor Performance** - Use `--profile-performance` to identify bottlenecks
4. **Review Logs** - Enable `--debug` when troubleshooting
5. **Verify Keyboard** - Test function keys with `zig-3270 test-keyboard`
6. **Check Compatibility** - Run with `--version` and reference protocol docs

---

**zig-3270 v0.7.0** - TN3270 Terminal Emulator  
Production-Ready • 175+ Tests • Zero Warnings
