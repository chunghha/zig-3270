# Windows Support Guide

zig-3270 includes comprehensive Windows support for both building and running on Windows platforms.

## System Requirements

### Windows Versions
- **Minimum**: Windows 7 SP1
- **Recommended**: Windows 10 22H2 or Windows 11
- **For ANSI Support**: Windows 10 Build 14931+

### Build Tools
- **Zig**: 0.12.0 or later
- **LLVM**: 17+ (included with Zig)
- **Optional**: Visual Studio Build Tools 2019+ (for native debugging)

## Building on Windows

### Option 1: With Zig (Recommended)

```bash
# Clone repository
git clone https://github.com/chunghha/zig-3270.git
cd zig-3270

# Build for Windows (auto-detects current platform)
zig build -Doptimize=ReleaseFast

# Build in debug mode
zig build -Doptimize=Debug

# Cross-compile from Linux/macOS to Windows x86_64
zig build -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseFast
```

### Option 2: Direct Compilation

```bash
# Compile main executable
zig build-exe -Doptimize=ReleaseFast src/main.zig

# Compile as library
zig build-lib -Doptimize=ReleaseFast src/root.zig -dynamic -fallow-shlib-undefined
```

### Output Location
Build artifacts are placed in:
```
zig-out/
├── bin/
│   ├── zig-3270.exe
│   ├── client-test.exe
│   └── mock-server.exe
└── lib/
    └── zig-3270.dll
```

## Running on Windows

### Command Prompt

```batch
# Navigate to build directory
cd zig-out\bin

# Run emulator
zig-3270.exe --host mainframe.example.com --port 23

# Run with interactive terminal
zig-3270.exe --interactive

# Run client test
client-test.exe
```

### PowerShell

```powershell
# Set path
$env:PATH += ";$(Get-Location)\zig-out\bin"

# Run emulator
./zig-3270.exe --host mainframe.example.com
```

### Creating Batch Scripts

Create `run-zig-3270.bat`:
```batch
@echo off
REM zig-3270 Launcher for Windows

set SCRIPT_DIR=%~dp0
set ZIG3270_PATH=%SCRIPT_DIR%zig-out\bin\zig-3270.exe

if not exist "%ZIG3270_PATH%" (
    echo Error: zig-3270.exe not found at %ZIG3270_PATH%
    echo Please build with: zig build -Doptimize=ReleaseFast
    exit /b 1
)

REM Enable ANSI color support (Windows 10+)
if exist "C:\Windows\System32\cmd.exe" (
    REM Try to enable virtual terminal processing
)

"%ZIG3270_PATH%" %*
```

## Windows Console Features

### ANSI Escape Sequence Support

Windows 10 Build 14931+ supports ANSI escape sequences in console:

```zig
const windows_console = @import("windows_console");

var mgr = try windows_console.ConsoleManager.init(allocator);
defer mgr.deinit();

// Enable VT100 mode on Windows 10+
try mgr.enable_virtual_terminal_processing();

// Now ANSI sequences work in console output
std.debug.print("\x1b[31mRed Text\x1b[0m\n", .{});
```

### Text Colors and Attributes

```zig
// Set text color (Windows native)
try mgr.set_text_color(
    windows_console.ConsoleColor.Yellow,
    windows_console.ConsoleColor.Black
);

std.debug.print("Yellow text on black background\n", .{});
```

### Cursor Management

```zig
// Get cursor information
const cursor = try mgr.get_cursor_info();
std.debug.print("Cursor size: {}%\n", .{cursor.size});
std.debug.print("Cursor visible: {}\n", .{cursor.visible});

// Set cursor position
try mgr.set_cursor_position(10, 5);

// Set cursor visibility
try mgr.set_cursor_info(25, false);  // Hide cursor
```

### Screen Buffer Info

```zig
// Get current screen dimensions and attributes
const info = try mgr.get_screen_buffer_info();
std.debug.print("Screen size: {}x{}\n", .{info.size.x, info.size.y});
std.debug.print("Cursor at: ({}, {})\n", .{info.cursor_position.x, info.cursor_position.y});
std.debug.print("Window: {}..{} x {}..{}\n", .{
    info.window.left, info.window.right,
    info.window.top, info.window.bottom,
});
```

## Code Page Support

### UTF-8 Console (Recommended)

```zig
// Set console to UTF-8 (code page 65001)
try mgr.set_code_page(65001);

// Now console input/output is UTF-8
```

### Legacy ANSI Code Pages

```zig
// Set to Windows-1252 (Western European)
try mgr.set_code_page(1252);

// Set to EBCDIC-US (for mainframe compatibility)
try mgr.set_code_page(500);
```

### Supported Code Pages for EBCDIC

- 037: EBCDIC-US
- 273: EBCDIC-German
- 285: EBCDIC-UK
- 297: EBCDIC-French
- 500: EBCDIC-International
- 875: EBCDIC-Greek
- 1026: EBCDIC-Turkish

## Windows Network Configuration

### Firewall

Allow zig-3270 through Windows Firewall:

```powershell
# As Administrator
New-NetFirewallRule -DisplayName "zig-3270" `
  -Direction Inbound -Program "C:\Path\To\zig-3270.exe" `
  -Action Allow -Protocol TCP -LocalPort 23,3270

New-NetFirewallRule -DisplayName "zig-3270 Outbound" `
  -Direction Outbound -Program "C:\Path\To\zig-3270.exe" `
  -Action Allow -Protocol TCP
```

### Proxy Configuration

zig-3270 respects Windows proxy settings:

```powershell
# View current proxy
netsh winhttp show proxy

# Set proxy
netsh winhttp set proxy 10.0.0.1:8080

# Clear proxy
netsh winhttp reset proxy
```

## Installation

### Portable Installation

1. Build zig-3270:
   ```
   zig build -Doptimize=ReleaseFast
   ```

2. Copy executable:
   ```
   copy zig-out\bin\zig-3270.exe C:\zig-3270\
   ```

3. Run from any directory:
   ```
   C:\zig-3270\zig-3270.exe --host mainframe.example.com
   ```

### Windows Package Manager

```powershell
# If published to winget (future)
winget install chunghha.zig-3270
```

### Chocolatey

```powershell
# If published to Chocolatey (future)
choco install zig-3270
```

## Library Usage on Windows

### Using zig-3270.dll in C/C++ Projects

```c
#include "zig3270.h"

// Link against zig-3270.dll
#pragma comment(lib, "zig3270.lib")

int main() {
    const char* version = zig3270_version();
    printf("Version: %s\n", version);
    return 0;
}
```

Compile:
```batch
cl /I zig-3270\include myapp.c /link /LIBPATH:zig-3270\lib zig3270.lib
```

### Python Bindings

```python
import sys
import os

# Set library path for Windows
os.environ['PATH'] = r'C:\zig-3270\lib;' + os.environ.get('PATH', '')

from zig3270 import TN3270Client, ebcdic_encode, ebcdic_decode

client = TN3270Client("mainframe.example.com", 23)
client.connect()
# ... use client
client.disconnect()
```

## Troubleshooting

### Issue: DLL Not Found

**Problem**: `zig-3270.dll not found`

**Solutions**:
1. Ensure `zig-3270.dll` is in same directory as executable
2. Add directory to PATH: `set PATH=%PATH%;C:\zig-3270\lib`
3. Set `ZIG3270_LIB_PATH` environment variable

### Issue: Console Output Not Colored

**Problem**: ANSI color codes not working

**Solutions**:
1. Verify Windows 10 Build 14931+ with `winver`
2. Enable VT mode: `mgr.enable_virtual_terminal_processing()`
3. Use native Windows colors instead: `ConsoleManager.set_text_color()`

### Issue: UTF-8 Characters Garbled

**Problem**: Special characters display incorrectly

**Solutions**:
1. Set code page to UTF-8: `mgr.set_code_page(65001)`
2. Use ANSI escape sequences for colors instead of code page attributes
3. Ensure terminal supports UTF-8 (ConEmu, Windows Terminal recommended)

### Issue: Slow Performance

**Problem**: zig-3270 runs slowly on Windows

**Solutions**:
1. Use Release build: `zig build -Doptimize=ReleaseFast`
2. Disable antivirus scanning of executable
3. Check for excessive logging (set `ZIG_LOG_LEVEL=error`)
4. Profile with `task benchmark`

## Terminal Emulators

### Windows Terminal (Recommended)

Modern terminal with full Unicode, ANSI, and UTF-8 support:

```powershell
# Install from Microsoft Store or:
winget install Microsoft.WindowsTerminal
```

Features:
- ANSI color support
- UTF-8 support
- Tabs and splits
- Custom schemes
- Configuration via JSON

### ConEmu

Classic console emulator:

```powershell
choco install conemu
```

Features:
- ANSI support
- Transparency
- Tabs
- Better Unicode handling

### mintty (Git Bash)

```powershell
# Ships with Git for Windows
winget install Git.Git
```

Benefits:
- Better Unix-like experience
- Full ANSI support
- Cross-platform consistency

## Cross-Compilation

### From Linux to Windows

```bash
# Linux → Windows x86_64
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast

# Linux → Windows ARM64
zig build -Dtarget=aarch64-windows-gnu -Doptimize=ReleaseFast
```

### From macOS to Windows

```bash
# macOS → Windows x86_64
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast
```

## Performance Considerations

### Memory

- Base executable: ~5-10MB
- Dynamic library: ~3-5MB
- Runtime memory: 10-20MB typical

### CPU

- Minimal: Uses available CPU efficiently
- Can utilize all cores
- Idle CPU: <1% when connected but idle

### Network

- Uses IOCP (I/O Completion Ports) for efficient async I/O
- Minimal CPU overhead during network operations
- Supports connection pooling

## Testing on Windows

```bash
# Run all tests
task test

# Run specific test
zig build test -Dtest-filter="windows_console"

# Run benchmarks
task benchmark

# Run integration tests
task test-connection
```

## Windows CI/CD

See `.github/workflows/windows-build.yml` for automated Windows builds and tests.

## Known Limitations

- Virtual Terminal Processing requires Windows 10+
- Some legacy Windows 7 features may not work
- Dynamic library needs MSVC runtime on some systems

## Future Windows Enhancements

- [ ] Native Windows installer (MSI)
- [ ] Windows service wrapper
- [ ] System tray icon
- [ ] Registry integration for file associations
- [ ] Windows Hello for biometric auth

## Resources

- [Zig Documentation](https://ziglang.org/documentation/)
- [Windows Console API](https://learn.microsoft.com/en-us/windows/console/)
- [Windows Terminal Docs](https://learn.microsoft.com/en-us/windows/terminal/)
- [ANSI Escape Codes](https://en.wikipedia.org/wiki/ANSI_escape_code)

