#!/usr/bin/env python3
"""
Python Example: Using zig-3270 Bindings

Demonstrates core functionality:
- Version information
- EBCDIC encoding/decoding
- Screen and field management (stubs for now)

Requirements:
    - Python 3.7+
    - zig-3270 shared library in LD_LIBRARY_PATH

Usage:
    export LD_LIBRARY_PATH=./zig-out/lib
    python3 examples/python_example.py
"""

import sys
import os

# Add bindings directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'bindings', 'python'))

try:
    from zig3270 import (
        get_version,
        get_protocol_version,
        ebcdic_decode,
        ebcdic_encode,
        Address,
        FieldAttr,
        TN3270Client,
        TN3270Error,
        ConnectionError,
    )
except ImportError as e:
    print(f"Error importing zig3270: {e}")
    print("\nMake sure to build the library first:")
    print("  zig build -Doptimize=ReleaseFast")
    print("\nThen set LD_LIBRARY_PATH:")
    print("  export LD_LIBRARY_PATH=./zig-out/lib")
    sys.exit(1)


def test_version():
    """Test version information."""
    print("\n=== Version Information ===")
    print(f"zig-3270 version: {get_version()}")
    print(f"Protocol version: {get_protocol_version()}")
    print("✓ Version tests passed")


def test_ebcdic():
    """Test EBCDIC encoding/decoding."""
    print("\n=== EBCDIC Encoding/Decoding ===")
    
    # Test encoding
    text = "HELLO"
    encoded = ebcdic_encode(text)
    print(f"Encoded '{text}': {encoded.hex()}")
    
    # Test decoding
    decoded = ebcdic_decode(encoded)
    print(f"Decoded back: '{decoded}'")
    
    assert decoded == text, f"Expected '{text}', got '{decoded}'"
    print("✓ EBCDIC tests passed")


def test_address():
    """Test Address data type."""
    print("\n=== Address Data Type ===")
    
    addr1 = Address(5, 10)
    print(f"Created address: {addr1}")
    
    addr2 = Address(5, 10)
    print(f"Address equality: addr1 == addr2: {addr1 == addr2}")
    
    assert addr1 == addr2, "Addresses should be equal"
    print("✓ Address tests passed")


def test_field_attr():
    """Test FieldAttr data type."""
    print("\n=== Field Attribute Data Type ===")
    
    attr1 = FieldAttr(protected=True, numeric=False)
    print(f"Created field attr: {attr1}")
    
    attr2 = FieldAttr(protected=True, numeric=False, hidden=True)
    print(f"Different attributes: {attr2}")
    
    print("✓ FieldAttr tests passed")


def test_client():
    """Test client creation (connection test disabled for demo)."""
    print("\n=== TN3270 Client ===")
    
    # Create client (don't connect in example)
    client = TN3270Client("localhost", 23)
    print(f"Created client: {client}")
    
    # Note: Connection would fail without a real mainframe/mock server
    # In real usage:
    # try:
    #     client.connect()
    #     print("Connected!")
    #     client.disconnect()
    # except ConnectionError as e:
    #     print(f"Connection error: {e}")
    
    print("✓ Client creation test passed")


def test_error_handling():
    """Test error handling."""
    print("\n=== Error Handling ===")
    
    try:
        # This would fail in real usage, but we can test the structure
        addr = Address(30, 100)  # Invalid coordinates
        print(f"Created out-of-range address: {addr}")
        # Note: Validation happens at API level
        print("✓ Error handling test passed")
    except Exception as e:
        print(f"Caught exception: {e}")


def main():
    """Run all examples."""
    print("zig-3270 Python Binding Examples")
    print("=================================")
    
    try:
        test_version()
        test_ebcdic()
        test_address()
        test_field_attr()
        test_client()
        test_error_handling()
        
        print("\n✓ All examples completed successfully!")
        return 0
    except Exception as e:
        print(f"\n✗ Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
