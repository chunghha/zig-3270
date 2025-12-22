"""
zig-3270: Python Bindings for TN3270 Terminal Emulator

High-level Pythonic interface to the zig-3270 library using ctypes.

Example:
    >>> from zig3270 import TN3270Client, Screen
    >>> client = TN3270Client("mainframe.example.com", 23)
    >>> client.connect()
    >>> screen = client.read_screen()
    >>> print(screen.get_text(0, 0, 10))
    >>> client.disconnect()

Version: 0.11.1-beta
"""

import ctypes
import os
import sys
from pathlib import Path
from typing import Optional, Tuple, List
from enum import IntEnum
import logging

logger = logging.getLogger(__name__)

# ============================================================================
# Library Loading
# ============================================================================

def _find_library():
    """Find the zig-3270 shared library."""
    # Try common locations
    search_paths = [
        Path(__file__).parent.parent.parent / "zig-out" / "lib",
        Path("/usr/lib"),
        Path("/usr/local/lib"),
        Path("/opt/zig-3270/lib"),
        Path.home() / ".local" / "lib",
    ]
    
    lib_names = [
        "libzig3270.so",  # Linux
        "libzig3270.dylib",  # macOS
        "zig3270.dll",  # Windows
        "libzig3270.a",  # Static
    ]
    
    for search_path in search_paths:
        if not search_path.exists():
            continue
        for lib_name in lib_names:
            lib_path = search_path / lib_name
            if lib_path.exists():
                logger.debug(f"Found zig-3270 library at {lib_path}")
                return str(lib_path)
    
    # Fallback: try ctypes.util
    try:
        from ctypes.util import find_library
        lib_path = find_library("zig3270")
        if lib_path:
            return lib_path
    except ImportError:
        pass
    
    raise RuntimeError(
        "zig-3270 library not found. "
        "Please build with 'zig build -Doptimize=ReleaseFast' "
        "or set ZIG3270_LIB_PATH environment variable."
    )

# Load library from environment or search
_lib_path = os.environ.get("ZIG3270_LIB_PATH") or _find_library()
_lib = ctypes.CDLL(_lib_path)

logger.info(f"Loaded zig-3270 from {_lib_path}")

# ============================================================================
# Error Codes
# ============================================================================

class ErrorCode(IntEnum):
    """TN3270 error codes."""
    SUCCESS = 0
    INVALID_ARG = 1
    OUT_OF_MEMORY = 2
    CONNECTION_FAILED = 3
    PARSE_ERROR = 4
    INVALID_STATE = 5
    TIMEOUT = 6
    FIELD_NOT_FOUND = 7


class TN3270Error(Exception):
    """Base exception for zig-3270 errors."""
    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(f"[{code}] {message}")


class ConnectionError(TN3270Error):
    """Connection-related error."""
    pass


class ParseError(TN3270Error):
    """Protocol parsing error."""
    pass


class TimeoutError(TN3270Error):
    """Operation timeout."""
    pass


def _check_error(code: int, context: str = "") -> None:
    """Check error code and raise appropriate exception."""
    if code == ErrorCode.SUCCESS:
        return
    
    error_messages = {
        ErrorCode.INVALID_ARG: "Invalid argument",
        ErrorCode.OUT_OF_MEMORY: "Out of memory",
        ErrorCode.CONNECTION_FAILED: "Connection failed",
        ErrorCode.PARSE_ERROR: "Parse error",
        ErrorCode.INVALID_STATE: "Invalid state",
        ErrorCode.TIMEOUT: "Timeout",
        ErrorCode.FIELD_NOT_FOUND: "Field not found",
    }
    
    message = error_messages.get(code, f"Unknown error {code}")
    if context:
        message = f"{context}: {message}"
    
    if code == ErrorCode.CONNECTION_FAILED:
        raise ConnectionError(code, message)
    elif code == ErrorCode.PARSE_ERROR:
        raise ParseError(code, message)
    elif code == ErrorCode.TIMEOUT:
        raise TimeoutError(code, message)
    else:
        raise TN3270Error(code, message)

# ============================================================================
# C Type Definitions
# ============================================================================

# Opaque types
class CClient(ctypes.Structure):
    """C TN3270Client opaque type."""
    pass

class CScreen(ctypes.Structure):
    """C TN3270Screen opaque type."""
    pass

class CFieldManager(ctypes.Structure):
    """C TN3270FieldManager opaque type."""
    pass

# C struct definitions
class CAddress(ctypes.Structure):
    """C zig3270_address_t."""
    _fields_ = [
        ("row", ctypes.c_uint8),
        ("col", ctypes.c_uint8),
    ]

class CFieldAttr(ctypes.Structure):
    """C zig3270_field_attr_t."""
    _fields_ = [
        ("value", ctypes.c_uint8),
    ]

# ============================================================================
# C Function Bindings
# ============================================================================

# Protocol functions
_lib.zig3270_ebcdic_decode_byte.argtypes = [ctypes.c_uint8]
_lib.zig3270_ebcdic_decode_byte.restype = ctypes.c_uint8

_lib.zig3270_ebcdic_encode_byte.argtypes = [ctypes.c_uint8]
_lib.zig3270_ebcdic_encode_byte.restype = ctypes.c_int32

_lib.zig3270_ebcdic_decode.argtypes = [
    ctypes.c_char_p, ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t
]
_lib.zig3270_ebcdic_decode.restype = ctypes.c_int32

_lib.zig3270_ebcdic_encode.argtypes = [
    ctypes.c_char_p, ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t
]
_lib.zig3270_ebcdic_encode.restype = ctypes.c_int32

# Memory functions
_lib.zig3270_malloc.argtypes = [ctypes.c_size_t]
_lib.zig3270_malloc.restype = ctypes.POINTER(ctypes.c_uint8)

_lib.zig3270_free.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
_lib.zig3270_free.restype = None

_lib.zig3270_string_free.argtypes = [ctypes.c_char_p]
_lib.zig3270_string_free.restype = None

# Client functions
_lib.zig3270_client_new.argtypes = [ctypes.c_char_p, ctypes.c_uint16]
_lib.zig3270_client_new.restype = ctypes.c_int32

_lib.zig3270_client_free.argtypes = [ctypes.POINTER(CClient)]
_lib.zig3270_client_free.restype = None

_lib.zig3270_client_connect.argtypes = [ctypes.POINTER(CClient)]
_lib.zig3270_client_connect.restype = ctypes.c_int32

_lib.zig3270_client_disconnect.argtypes = [ctypes.POINTER(CClient)]
_lib.zig3270_client_disconnect.restype = ctypes.c_int32

_lib.zig3270_client_send_command.argtypes = [
    ctypes.POINTER(CClient),
    ctypes.c_char_p,
    ctypes.c_size_t
]
_lib.zig3270_client_send_command.restype = ctypes.c_int32

_lib.zig3270_client_read_response.argtypes = [
    ctypes.POINTER(CClient),
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_size_t,
    ctypes.c_uint32
]
_lib.zig3270_client_read_response.restype = ctypes.c_int32

# Screen functions
_lib.zig3270_screen_new.argtypes = []
_lib.zig3270_screen_new.restype = ctypes.c_int32

_lib.zig3270_screen_free.argtypes = [ctypes.POINTER(CScreen)]
_lib.zig3270_screen_free.restype = None

_lib.zig3270_screen_clear.argtypes = [ctypes.POINTER(CScreen)]
_lib.zig3270_screen_clear.restype = ctypes.c_int32

_lib.zig3270_screen_write.argtypes = [
    ctypes.POINTER(CScreen),
    ctypes.c_uint8, ctypes.c_uint8,
    ctypes.c_char_p, ctypes.c_size_t
]
_lib.zig3270_screen_write.restype = ctypes.c_int32

_lib.zig3270_screen_read.argtypes = [
    ctypes.POINTER(CScreen),
    ctypes.c_uint8, ctypes.c_uint8,
    ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t
]
_lib.zig3270_screen_read.restype = ctypes.c_int32

_lib.zig3270_screen_to_string.argtypes = [ctypes.POINTER(CScreen)]
_lib.zig3270_screen_to_string.restype = ctypes.c_char_p

_lib.zig3270_screen_get_cursor.argtypes = [ctypes.POINTER(CScreen), ctypes.POINTER(CAddress)]
_lib.zig3270_screen_get_cursor.restype = ctypes.c_int32

# Field functions
_lib.zig3270_fields_new.argtypes = []
_lib.zig3270_fields_new.restype = ctypes.c_int32

_lib.zig3270_fields_free.argtypes = [ctypes.POINTER(CFieldManager)]
_lib.zig3270_fields_free.restype = None

_lib.zig3270_fields_add.argtypes = [
    ctypes.POINTER(CFieldManager),
    ctypes.c_uint16, ctypes.c_uint16,
    CFieldAttr
]
_lib.zig3270_fields_add.restype = ctypes.c_int32

_lib.zig3270_fields_count.argtypes = [ctypes.POINTER(CFieldManager)]
_lib.zig3270_fields_count.restype = ctypes.c_uint32

_lib.zig3270_fields_get.argtypes = [
    ctypes.POINTER(CFieldManager),
    ctypes.c_uint32,
    ctypes.POINTER(ctypes.c_uint16),
    ctypes.POINTER(ctypes.c_uint16)
]
_lib.zig3270_fields_get.restype = ctypes.c_int32

# Version functions
_lib.zig3270_version.argtypes = []
_lib.zig3270_version.restype = ctypes.c_char_p

_lib.zig3270_protocol_version.argtypes = []
_lib.zig3270_protocol_version.restype = ctypes.c_char_p

# ============================================================================
# High-Level Python Bindings
# ============================================================================

class Address:
    """Screen address (row, column)."""
    def __init__(self, row: int, col: int):
        self.row = row
        self.col = col
    
    def __repr__(self):
        return f"Address(row={self.row}, col={self.col})"
    
    def __eq__(self, other):
        if not isinstance(other, Address):
            return False
        return self.row == other.row and self.col == other.col


class FieldAttr:
    """Field attribute."""
    def __init__(self, protected: bool = False, numeric: bool = False,
                 hidden: bool = False, intensity: bool = False):
        self.protected = protected
        self.numeric = numeric
        self.hidden = hidden
        self.intensity = intensity
    
    def _to_c(self) -> CFieldAttr:
        """Convert to C structure."""
        value = 0
        if self.protected:
            value |= 0x01
        if self.numeric:
            value |= 0x02
        if self.hidden:
            value |= 0x04
        if self.intensity:
            value |= 0x08
        return CFieldAttr(value)
    
    def __repr__(self):
        return (f"FieldAttr(protected={self.protected}, numeric={self.numeric}, "
                f"hidden={self.hidden}, intensity={self.intensity})")


class Screen:
    """TN3270 Screen (24x80 character grid)."""
    
    ROWS = 24
    COLS = 80
    
    def __init__(self):
        self._screen = None
    
    def clear(self) -> None:
        """Clear the screen."""
        if self._screen is None:
            raise ValueError("Screen not initialized")
        code = _lib.zig3270_screen_clear(self._screen)
        _check_error(code, "Failed to clear screen")
    
    def write(self, row: int, col: int, text: str) -> None:
        """Write text to screen at position."""
        if self._screen is None:
            raise ValueError("Screen not initialized")
        if not 0 <= row < self.ROWS:
            raise ValueError(f"Row {row} out of range [0, {self.ROWS})")
        if not 0 <= col < self.COLS:
            raise ValueError(f"Col {col} out of range [0, {self.COLS})")
        
        text_bytes = text.encode('ascii')
        code = _lib.zig3270_screen_write(
            self._screen, row, col,
            text_bytes, len(text_bytes)
        )
        _check_error(code, f"Failed to write at ({row}, {col})")
    
    def read(self, row: int, col: int, length: int) -> str:
        """Read text from screen at position."""
        if self._screen is None:
            raise ValueError("Screen not initialized")
        if not 0 <= row < self.ROWS:
            raise ValueError(f"Row {row} out of range [0, {self.ROWS})")
        if not 0 <= col < self.COLS:
            raise ValueError(f"Col {col} out of range [0, {self.COLS})")
        
        buf = ctypes.create_string_buffer(length)
        code = _lib.zig3270_screen_read(
            self._screen, row, col,
            buf, length
        )
        _check_error(code, f"Failed to read from ({row}, {col})")
        return buf.raw[:code].decode('ascii', errors='replace')
    
    def to_string(self) -> str:
        """Get entire screen as string."""
        if self._screen is None:
            raise ValueError("Screen not initialized")
        ptr = _lib.zig3270_screen_to_string(self._screen)
        if not ptr:
            raise RuntimeError("Failed to get screen as string")
        result = ctypes.c_char_p(ptr).value.decode('ascii', errors='replace')
        _lib.zig3270_string_free(ptr)
        return result
    
    def get_cursor(self) -> Address:
        """Get current cursor position."""
        if self._screen is None:
            raise ValueError("Screen not initialized")
        addr = CAddress()
        code = _lib.zig3270_screen_get_cursor(self._screen, ctypes.byref(addr))
        _check_error(code, "Failed to get cursor")
        return Address(addr.row, addr.col)
    
    def __repr__(self):
        return "Screen(24x80)"
    
    def __del__(self):
        if self._screen:
            _lib.zig3270_screen_free(self._screen)


class FieldManager:
    """Field manager for TN3270 fields."""
    
    def __init__(self):
        self._fields = None
    
    def add_field(self, offset: int, length: int, attr: Optional[FieldAttr] = None) -> None:
        """Add a field."""
        if self._fields is None:
            raise ValueError("FieldManager not initialized")
        if not 0 <= offset < 1920:
            raise ValueError(f"Offset {offset} out of range [0, 1920)")
        if length <= 0:
            raise ValueError(f"Length must be positive")
        
        if attr is None:
            attr = FieldAttr()
        
        code = _lib.zig3270_fields_add(
            self._fields, offset, length,
            attr._to_c()
        )
        _check_error(code, "Failed to add field")
    
    def count(self) -> int:
        """Get number of fields."""
        if self._fields is None:
            raise ValueError("FieldManager not initialized")
        return _lib.zig3270_fields_count(self._fields)
    
    def get_field(self, index: int) -> Tuple[int, int]:
        """Get field information by index."""
        if self._fields is None:
            raise ValueError("FieldManager not initialized")
        offset = ctypes.c_uint16()
        length = ctypes.c_uint16()
        code = _lib.zig3270_fields_get(
            self._fields, index,
            ctypes.byref(offset),
            ctypes.byref(length)
        )
        _check_error(code, f"Failed to get field {index}")
        return (offset.value, length.value)
    
    def __repr__(self):
        return "FieldManager()"
    
    def __del__(self):
        if self._fields:
            _lib.zig3270_fields_free(self._fields)


class TN3270Client:
    """High-level TN3270 client."""
    
    def __init__(self, host: str, port: int = 23):
        """Create a new TN3270 client.
        
        Args:
            host: Hostname or IP address
            port: Port number (default: 23 for telnet)
        """
        self.host = host
        self.port = port
        self._client = None
        self._connected = False
    
    def connect(self, timeout_ms: int = 5000) -> None:
        """Connect to the mainframe.
        
        Args:
            timeout_ms: Connection timeout in milliseconds
        """
        if self._connected:
            raise ValueError("Already connected")
        
        code = _lib.zig3270_client_new(
            self.host.encode('ascii'),
            self.port
        )
        _check_error(code, f"Failed to create client for {self.host}:{self.port}")
        
        code = _lib.zig3270_client_connect(self._client)
        _check_error(code, "Failed to connect")
        
        self._connected = True
        logger.info(f"Connected to {self.host}:{self.port}")
    
    def disconnect(self) -> None:
        """Disconnect from the mainframe."""
        if not self._connected:
            return
        
        code = _lib.zig3270_client_disconnect(self._client)
        _check_error(code, "Failed to disconnect")
        
        self._connected = False
        logger.info(f"Disconnected from {self.host}:{self.port}")
    
    def send_command(self, command: bytes) -> None:
        """Send a raw command to the mainframe.
        
        Args:
            command: Raw command bytes
        """
        if not self._connected:
            raise ValueError("Not connected")
        
        code = _lib.zig3270_client_send_command(
            self._client,
            command,
            len(command)
        )
        _check_error(code, "Failed to send command")
    
    def read_response(self, timeout_ms: int = 5000) -> bytes:
        """Read response from mainframe.
        
        Args:
            timeout_ms: Read timeout in milliseconds
            
        Returns:
            Response bytes
        """
        if not self._connected:
            raise ValueError("Not connected")
        
        buf = ctypes.create_string_buffer(4096)
        code = _lib.zig3270_client_read_response(
            self._client,
            buf,
            len(buf),
            timeout_ms
        )
        _check_error(code, "Failed to read response")
        
        return buf.raw[:code]
    
    def __repr__(self):
        status = "connected" if self._connected else "disconnected"
        return f"TN3270Client({self.host}:{self.port}, {status})"
    
    def __del__(self):
        if self._client and self._connected:
            try:
                self.disconnect()
            except:
                pass
        if self._client:
            _lib.zig3270_client_free(self._client)


def get_version() -> str:
    """Get library version."""
    return _lib.zig3270_version().decode('ascii')


def get_protocol_version() -> str:
    """Get TN3270 protocol version."""
    return _lib.zig3270_protocol_version().decode('ascii')


# ============================================================================
# EBCDIC Encoding/Decoding (Convenience Functions)
# ============================================================================

def ebcdic_decode(data: bytes) -> str:
    """Decode EBCDIC bytes to ASCII string."""
    if not data:
        return ""
    
    output = ctypes.create_string_buffer(len(data))
    code = _lib.zig3270_ebcdic_decode(
        data, len(data),
        output, len(data)
    )
    _check_error(code, "Failed to decode EBCDIC")
    return output.raw[:code].decode('ascii', errors='replace')


def ebcdic_encode(text: str) -> bytes:
    """Encode ASCII string to EBCDIC bytes."""
    text_bytes = text.encode('ascii')
    if not text_bytes:
        return b""
    
    output = ctypes.create_string_buffer(len(text_bytes))
    code = _lib.zig3270_ebcdic_encode(
        text_bytes, len(text_bytes),
        output, len(text_bytes)
    )
    _check_error(code, "Failed to encode EBCDIC")
    return output.raw[:code]


if __name__ == "__main__":
    # Quick test
    print(f"zig-3270 version: {get_version()}")
    print(f"Protocol version: {get_protocol_version()}")
    
    # Test EBCDIC
    encoded = ebcdic_encode("HELLO")
    print(f"EBCDIC 'HELLO': {encoded.hex()}")
    decoded = ebcdic_decode(encoded)
    print(f"Decoded back: {decoded}")
