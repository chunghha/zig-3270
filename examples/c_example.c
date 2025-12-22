/*
 * C Example: Using zig-3270 Library
 * 
 * Demonstrates core functionality:
 * - EBCDIC encoding/decoding
 * - Memory management
 * - Version information
 * 
 * Build and run:
 *   gcc -I./include examples/c_example.c -o c_example -lm
 *   ./c_example
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../include/zig3270.h"

/* ========================================================================== */
/* Test: EBCDIC Encoding/Decoding                                          */
/* ========================================================================== */

void test_ebcdic(void) {
    printf("\n=== EBCDIC Encoding/Decoding ===\n");
    
    /* Test decode_byte */
    uint8_t ebcdic_a = 0xc1;  /* EBCDIC 'A' */
    uint8_t ascii_a = zig3270_ebcdic_decode_byte(ebcdic_a);
    printf("EBCDIC 0xc1 -> ASCII '%c' (expected 'A')\n", ascii_a);
    if (ascii_a != 'A') {
        fprintf(stderr, "ERROR: Decode byte failed\n");
        return;
    }
    
    /* Test encode_byte */
    int32_t encoded = zig3270_ebcdic_encode_byte('A');
    printf("ASCII 'A' -> EBCDIC 0x%02x (expected 0xc1)\n", (uint8_t)encoded);
    if (encoded != 0xc1) {
        fprintf(stderr, "ERROR: Encode byte failed\n");
        return;
    }
    
    /* Test buffer decode */
    const uint8_t ebcdic_hello[] = {0xc8, 0x85, 0x93, 0x93, 0x96};  /* "HELLO" */
    uint8_t ascii_buf[5];
    int32_t decoded = zig3270_ebcdic_decode(
        ebcdic_hello, sizeof(ebcdic_hello),
        ascii_buf, sizeof(ascii_buf)
    );
    printf("Decoded buffer: %.*s (expected 'HELLO')\n", (int)decoded, (char*)ascii_buf);
    if (decoded != 5 || strncmp((char*)ascii_buf, "HELLO", 5) != 0) {
        fprintf(stderr, "ERROR: Buffer decode failed\n");
        return;
    }
    
    /* Test buffer encode */
    const char *text = "WORLD";
    uint8_t ebcdic_buf[5];
    int32_t encoded_len = zig3270_ebcdic_encode(
        (const uint8_t*)text, strlen(text),
        ebcdic_buf, sizeof(ebcdic_buf)
    );
    printf("Encoded buffer (%.*s): %02x %02x %02x %02x %02x\n",
           (int)encoded_len, text,
           ebcdic_buf[0], ebcdic_buf[1], ebcdic_buf[2], ebcdic_buf[3], ebcdic_buf[4]);
    if (encoded_len != 5) {
        fprintf(stderr, "ERROR: Buffer encode failed\n");
        return;
    }
    
    printf("✓ EBCDIC tests passed\n");
}

/* ========================================================================== */
/* Test: Memory Management                                                  */
/* ========================================================================== */

void test_memory(void) {
    printf("\n=== Memory Management ===\n");
    
    /* Test malloc */
    size_t size = 256;
    uint8_t *buf = zig3270_malloc(size);
    if (buf == NULL) {
        fprintf(stderr, "ERROR: malloc failed\n");
        return;
    }
    printf("Allocated %zu bytes\n", size);
    
    /* Write some data */
    memset(buf, 'X', size);
    printf("Wrote %zu 'X' bytes\n", size);
    
    /* Free memory */
    zig3270_free(buf, size);
    printf("Freed memory\n");
    
    printf("✓ Memory management tests passed\n");
}

/* ========================================================================== */
/* Test: Version Information                                               */
/* ========================================================================== */

void test_version(void) {
    printf("\n=== Version Information ===\n");
    
    const char *version = zig3270_version();
    printf("zig-3270 version: %s\n", version);
    if (version == NULL) {
        fprintf(stderr, "ERROR: Failed to get version\n");
        return;
    }
    
    const char *proto_version = zig3270_protocol_version();
    printf("Protocol version: %s\n", proto_version);
    if (proto_version == NULL) {
        fprintf(stderr, "ERROR: Failed to get protocol version\n");
        return;
    }
    
    printf("✓ Version tests passed\n");
}

/* ========================================================================== */
/* Main                                                                      */
/* ========================================================================== */

int main(void) {
    printf("zig-3270 C Binding Examples\n");
    printf("============================\n");
    
    test_ebcdic();
    test_memory();
    test_version();
    
    printf("\n✓ All tests passed!\n");
    return 0;
}
