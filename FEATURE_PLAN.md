# User Features Implementation Plan

## Timeline: ~15-19 hours total
- Keyboard Mapping Configuration: 3-4 hours
- Screen History & Scrollback: 4-5 hours  
- ANSI Color Support: 3-4 hours
- Session Persistence: 5-6 hours

## 1. Keyboard Mapping Configuration (3-4 hours)

### Files to Create/Modify
- `src/keyboard_config.zig` - Config loading and parsing
- `src/input.zig` - Integration with key binding system
- Tests in files

### Design
```zig
pub const KeyConfig = struct {
    bindings: std.StringHashMap(KeyAction),  // "F1" -> Enter
    modifier_map: std.StringHashMap(u32),    // "alt" -> ALT_MASK
};

pub const KeyAction = union(enum) {
    aid_key: protocol.AID,
    char: u8,
    none,
};
```

### Config File Format (JSON)
```json
{
  "keys": {
    "F1": "AID_ENTER",
    "F2": "AID_CLEAR",
    "Tab": "AID_TAB",
    "Home": "AID_HOME",
    "Escape": "AID_ESCAPE"
  }
}
```

---

## 2. Screen History & Scrollback (4-5 hours)

### Files to Create/Modify
- `src/screen_history.zig` - History buffer management
- `src/screen.zig` - Add history saving
- Tests

### Design
```zig
pub const ScreenHistory = struct {
    screens: std.ArrayList(ScreenSnapshot),
    current_index: usize,
    max_history: usize,
};

pub const ScreenSnapshot = struct {
    buffer: []u8,  // Copy of screen buffer
    timestamp: i64,
    sequence_number: u64,
};
```

### Features
- Configurable history size (default: 100 screens)
- Navigate backward/forward
- Clear history
- Save snapshots on screen updates

---

## 3. ANSI Color Support (3-4 hours)

### Files to Create/Modify
- `src/ansi_colors.zig` - Attribute to ANSI mapping
- `src/renderer.zig` - Update rendering with colors
- Tests

### Design
```zig
pub const AnsiColors = struct {
    fn attribute_to_ansi(attr: attributes.FieldAttribute) []const u8;
    fn wrap_text(text: []const u8, attr: attributes.FieldAttribute) []u8;
};
```

### Color Mapping
```
Normal       -> Default
Intensified  -> Bright/Bold
Protected    -> Dim
Hidden       -> Invisible
```

---

## 4. Session Persistence (5-6 hours)

### Files to Create/Modify
- `src/session_storage.zig` - Save/restore session state
- `src/main.zig` - Load/save on startup/shutdown
- Tests

### Design
```zig
pub const SessionState = struct {
    screen_buffer: []u8,
    field_data: []FieldSnapshot,
    cursor_position: Address,
    keyboard_locked: bool,
    timestamp: i64,
};

pub fn save_session(allocator, path, state) !void;
pub fn load_session(allocator, path) !SessionState;
```

### Features
- Save session state to file (~/.zig3270/session.bin)
- Restore on startup
- Auto-save periodically
- Recover from crashes

---

## Implementation Order
1. Start with Keyboard Mapping (simplest, good foundation)
2. Add Screen History (builds on existing screen module)
3. Add ANSI Colors (integrates with renderer)
4. Add Session Persistence (pulls everything together)

## Testing Strategy
- Unit tests for each module
- Integration tests in integration_test.zig
- Validation with mock server

## Commits per Feature
- `feat(keyboard-config): implement configurable key bindings`
- `feat(screen-history): add scrollback buffer and navigation`
- `feat(ansi-colors): map 3270 attributes to terminal colors`
- `feat(session-storage): save and restore terminal state`

---

**Status**: Ready to implement
**Start Date**: Dec 21, 2024
**Target Completion**: Jan 4, 2025
