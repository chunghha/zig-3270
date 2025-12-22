# zig-3270: Configuration Reference

Complete reference for all configuration options and file formats.

## Table of Contents

- [Configuration Files](#configuration-files)
- [CLI Flags & Options](#cli-flags--options)
- [Connection Profiles](#connection-profiles)
- [Keyboard Configuration](#keyboard-configuration)
- [Environment Variables](#environment-variables)
- [JSON Schema Reference](#json-schema-reference)
- [Examples](#examples)

---

## Configuration Files

### File Locations

Configuration files are stored in user's home directory:

```
~/.zig3270/                      # Main configuration directory
├── profiles.json                # Connection profiles
├── keyboard-config.json         # Keyboard mappings
├── session.bin                  # Last session state (binary)
├── session-autosave.json        # Auto-save session data
└── debug.log                    # Debug log file (if logging enabled)
```

### File Permissions

For security, these permissions are recommended:

```bash
# Configuration directory
chmod 700 ~/.zig3270

# Configuration files
chmod 600 ~/.zig3270/profiles.json
chmod 600 ~/.zig3270/keyboard-config.json
```

---

## CLI Flags & Options

### Global Flags

```bash
zig-3270 [COMMAND] [OPTIONS]
```

#### Help & Version

| Flag | Description |
|------|-------------|
| `--help`, `-h` | Show help message and exit |
| `--version`, `-v` | Show version and exit |

#### Logging & Debug

| Flag | Description | Values |
|------|-------------|--------|
| `--verbose` | Enable verbose output | `(no value)` |
| `--debug` | Enable debug/trace logging | `(no value)` |
| `--log-level` | Set logging level | `error`, `warn`, `info`, `debug`, `trace` |
| `--log-file` | Write logs to file | `path` |

#### Connection

| Flag | Description | Example |
|------|-------------|---------|
| `--host` | Mainframe hostname/IP | `mainframe.example.com` |
| `--port` | TCP port (default: 23) | `23` |
| `--profile` | Use saved profile | `TSO` |
| `--timeout` | Connection timeout (ms) | `5000` |

#### Session & Recording

| Flag | Description | Example |
|------|-------------|---------|
| `--record` | Record session to file | `session.bin` |
| `--replay` | Replay recorded session | `session.bin` |
| `--auto-save` | Enable auto-save | `(no value)` |
| `--no-auto-save` | Disable auto-save | `(no value)` |

#### Performance & Monitoring

| Flag | Description | Example |
|------|-------------|---------|
| `--profile-performance` | Enable performance profiling | `(no value)` |
| `--snoop-log` | Log protocol events | `traffic.log` |
| `--memory-tracking` | Enable memory tracking | `(no value)` |

### Command Examples

```bash
# Basic connection
zig-3270 connect --host mainframe.example.com --port 23

# With profile
zig-3270 connect --profile TSO

# With logging
zig-3270 connect --host mainframe.example.com --debug --log-file debug.log

# Record session
zig-3270 connect --profile TSO --record mysession.bin

# Replay session
zig-3270 replay mysession.bin

# Profile performance
zig-3270 connect --profile TSO --profile-performance

# Snoop protocol traffic
zig-3270 connect --profile TSO --snoop-log traffic.log
```

---

## Connection Profiles

### Profile Structure

```json
{
  "profile-name": {
    "host": "string",                    // Required
    "port": 23,                          // Optional, default 23
    "timeout": 5000,                     // Optional, default 5000 (ms)
    "keyboard_profile": "string",        // Optional, default "standard"
    "auto_login": false,                 // Optional, default false
    "username": "string",                // Optional, for auto-login
    "auto_commands": ["string"]          // Optional, commands to auto-execute
  }
}
```

### Profile File Format

```json
{
  "TSO": {
    "host": "mainframe.example.com",
    "port": 23,
    "timeout": 5000,
    "keyboard_profile": "standard"
  },
  "CICS": {
    "host": "cics.example.com",
    "port": 23,
    "timeout": 10000
  },
  "IMS": {
    "host": "ims.example.com",
    "port": 23,
    "auto_commands": [
      "SIGN ON",
      "MENU"
    ]
  },
  "test-server": {
    "host": "127.0.0.1",
    "port": 3270,
    "timeout": 2000,
    "keyboard_profile": "testing"
  }
}
```

### Built-in Profiles

The following profiles are automatically available:

#### TSO (Time Sharing Option)
```
host: Set by --host flag
port: 23
timeout: 5000
keyboard: standard
```

#### CICS (Customer Information Control System)
```
host: Set by --host flag
port: 23
timeout: 10000
keyboard: standard
```

#### IMS (Information Management System)
```
host: Set by --host flag
port: 23
timeout: 5000
keyboard: standard
```

#### BATCH (Batch Job Monitor)
```
host: Set by --host flag
port: 23
timeout: 5000
keyboard: standard
```

### Profile Override

Command-line flags override profile settings:

```bash
# Load profile but override host
zig-3270 connect --profile TSO --host override.example.com

# Load profile but override timeout
zig-3270 connect --profile CICS --timeout 15000
```

---

## Keyboard Configuration

### Keyboard File Format

```json
{
  "layout-name": {
    "mappings": {
      "key": "aid_code",
      ...
    },
    "modifiers": {
      "shift": true,
      "ctrl": true,
      "alt": true
    }
  }
}
```

### Standard Keyboard Mapping

```json
{
  "standard": {
    "mappings": {
      "Tab": "TAB",
      "Shift+Tab": "BACKTAB",
      "Enter": "ENTER",
      "Escape": "CLEAR",
      "Home": "HOME",
      "End": "END",
      "Page_Up": "PA1",
      "Page_Down": "PA2",
      "F1": "F1",
      "F2": "F2",
      "F3": "F3",
      "F4": "F4",
      "F5": "F5",
      "F6": "F6",
      "F7": "F7",
      "F8": "F8",
      "F9": "F9",
      "F10": "F10",
      "F11": "F11",
      "F12": "F12",
      "F13": "F13",
      "F14": "F14",
      "F15": "F15",
      "F16": "F16",
      "F17": "F17",
      "F18": "F18",
      "F19": "F19",
      "F20": "F20",
      "F21": "F21",
      "F22": "F22",
      "F23": "F23",
      "F24": "F24"
    }
  }
}
```

### Key Names

Standard key names for keyboard mapping:

```
Alphabet:   a, b, c, ..., z
Numbers:    0, 1, 2, ..., 9
Symbols:    !, @, #, $, %, etc.
Special:    Space, Tab, Enter, Escape, Backspace, Delete
Navigation: Home, End, Page_Up, Page_Down, Left, Right, Up, Down
Function:   F1-F24
Modifiers:  Shift, Ctrl, Alt, Meta
```

### AID Codes

Attention Identifier (AID) codes transmitted to mainframe:

```
0x60 - NO AID (data only)
0x61 - STRUCTURED FIELD
0x6B - PA1
0x6C - PA2
0x6D - PA3
0x7D - CLEAR
0x7E - ENTER
0xF1 - F1
0xF2 - F2
...
0xFE - F24
```

### Custom Keyboard Example

```json
{
  "vim-style": {
    "mappings": {
      "h": "Left",
      "j": "Down",
      "k": "Up",
      "l": "Right",
      "w": "Tab",
      "b": "Shift+Tab",
      "gg": "Home",
      "G": "End",
      "Ctrl+d": "Page_Down",
      "Ctrl+u": "Page_Up"
    }
  },
  "emacs-style": {
    "mappings": {
      "Ctrl+n": "Down",
      "Ctrl+p": "Up",
      "Ctrl+f": "Right",
      "Ctrl+b": "Left",
      "Ctrl+a": "Home",
      "Ctrl+e": "End"
    }
  }
}
```

---

## Environment Variables

### Debug & Logging

```bash
# Set default log level
ZIG3270_LOG_LEVEL=debug

# Enable file logging
ZIG3270_LOG_FILE=~/.zig3270/app.log

# Module-specific logging
ZIG3270_LOG_MODULES=parser:trace,executor:debug,client:info
```

### Configuration Paths

```bash
# Override config directory
ZIG3270_CONFIG_DIR=/etc/zig3270

# Override profiles location
ZIG3270_PROFILES=/etc/zig3270/profiles.json

# Override keyboard config location
ZIG3270_KEYBOARD_CONFIG=/etc/zig3270/keyboard.json
```

### Session Management

```bash
# Enable auto-save
ZIG3270_AUTO_SAVE=1

# Auto-save interval (seconds)
ZIG3270_AUTO_SAVE_INTERVAL=30

# Session history size (number of screens)
ZIG3270_HISTORY_SIZE=100
```

### Network

```bash
# Default connection timeout (ms)
ZIG3270_DEFAULT_TIMEOUT=5000

# Connection pool size
ZIG3270_POOL_SIZE=10

# Max retries for auto-reconnect
ZIG3270_MAX_RETRIES=3
```

### Performance

```bash
# Enable performance profiling
ZIG3270_PROFILE_PERFORMANCE=1

# Memory tracking
ZIG3270_TRACK_MEMORY=1

# Buffer size (bytes)
ZIG3270_BUFFER_SIZE=8192
```

---

## JSON Schema Reference

### profiles.json Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "pattern": {
      "type": "object",
      "properties": {
        "host": {
          "type": "string",
          "description": "Hostname or IP address"
        },
        "port": {
          "type": "integer",
          "minimum": 1,
          "maximum": 65535,
          "default": 23,
          "description": "TCP port number"
        },
        "timeout": {
          "type": "integer",
          "minimum": 1000,
          "default": 5000,
          "description": "Timeout in milliseconds"
        },
        "keyboard_profile": {
          "type": "string",
          "default": "standard",
          "description": "Keyboard layout to use"
        },
        "auto_login": {
          "type": "boolean",
          "default": false,
          "description": "Auto-login with stored credentials"
        },
        "auto_commands": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "description": "Commands to execute after login"
        }
      },
      "required": ["host"],
      "additionalProperties": false
    }
  },
  "additionalProperties": false
}
```

---

## Examples

### Example 1: Multi-Server Setup

```json
{
  "prod-tso": {
    "host": "mainframe1.prod.example.com",
    "port": 23,
    "timeout": 10000,
    "keyboard_profile": "standard"
  },
  "dev-tso": {
    "host": "mainframe2.dev.example.com",
    "port": 23,
    "timeout": 5000,
    "keyboard_profile": "standard"
  },
  "test-cics": {
    "host": "127.0.0.1",
    "port": 3270,
    "timeout": 2000,
    "keyboard_profile": "testing"
  },
  "dr-ims": {
    "host": "dr-server.example.com",
    "port": 23,
    "timeout": 15000,
    "auto_commands": ["SIGN ON", "IMS"]
  }
}
```

### Example 2: Custom Keyboard Layout

```json
{
  "programmer": {
    "mappings": {
      "F1": "F1",
      "F2": "F2",
      "F3": "F3",
      "F4": "F4",
      "F5": "F5",
      "F6": "F6",
      "F7": "F7",
      "F8": "F8",
      "F9": "F9",
      "F10": "F10",
      "F11": "F11",
      "F12": "F12",
      "Tab": "TAB",
      "Shift+Tab": "BACKTAB",
      "Enter": "ENTER",
      "Escape": "PA1",
      "Ctrl+c": "CLEAR"
    }
  }
}
```

### Example 3: All Environment Variables

```bash
# ~/.zig3270/.env
ZIG3270_LOG_LEVEL=debug
ZIG3270_LOG_FILE=~/.zig3270/debug.log
ZIG3270_AUTO_SAVE=1
ZIG3270_AUTO_SAVE_INTERVAL=30
ZIG3270_HISTORY_SIZE=100
ZIG3270_DEFAULT_TIMEOUT=5000
ZIG3270_PROFILE_PERFORMANCE=1
ZIG3270_TRACK_MEMORY=1
```

### Example 4: Production Configuration

```json
{
  "production": {
    "host": "mainframe.prod.example.com",
    "port": 23,
    "timeout": 30000,
    "keyboard_profile": "standard",
    "auto_commands": [
      "SIGN ON",
      "SET PROFILE (NOINTERCOM)"
    ]
  }
}
```

---

## Troubleshooting Configuration

### Configuration Not Loaded

**Problem**: Config files are ignored

**Solutions**:
1. Verify file exists: `ls ~/.zig3270/profiles.json`
2. Check file permissions: `chmod 600 ~/.zig3270/profiles.json`
3. Verify JSON syntax: `jq . ~/.zig3270/profiles.json`
4. Check logs: `zig-3270 --log-level debug --log-file debug.log`

### Profile Not Found

**Problem**: `error: profile not found`

**Solutions**:
1. List profiles: `zig-3270 list-profiles`
2. Check spelling: `zig-3270 connect --profile [name]`
3. Validate JSON: `jq . ~/.zig3270/profiles.json`

### Keyboard Mapping Not Working

**Problem**: Keyboard shortcuts don't work

**Solutions**:
1. Verify keyboard config file exists
2. Check mapping name: `cat ~/.zig3270/keyboard-config.json`
3. Test with specific mapping: `zig-3270 connect --profile TSO --keyboard standard`
4. Reset to defaults: remove `~/.zig3270/keyboard-config.json`

---

## Migration Guide

### Upgrading from v0.6 to v0.7

No breaking changes in configuration format. Existing files will work unchanged:

```bash
# Backup old configuration
cp -r ~/.zig3270 ~/.zig3270.backup.v0.6

# No migration needed - v0.7 is backward compatible
```

---

**zig-3270 v0.7.0** - Configuration Reference  
Complete • Type-Safe • Backward Compatible
