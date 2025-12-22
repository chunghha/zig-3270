/*
 * zig-3270: TN3270 Terminal Emulator C FFI
 * 
 * This header provides C-compatible bindings for the zig-3270 library.
 * 
 * Building C projects using zig-3270:
 *   gcc -I./include -L./zig-out/lib -c myapp.c -o myapp.o
 *   gcc -L./zig-out/lib myapp.o -l zig-3270 -lpthread -o myapp
 * 
 * Version: 0.11.1-beta
 */

#ifndef ZIG3270_H
#define ZIG3270_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================== */
/* Error Codes                                                              */
/* ========================================================================== */

typedef enum {
    ZIG3270_SUCCESS = 0,
    ZIG3270_INVALID_ARG = 1,
    ZIG3270_OUT_OF_MEMORY = 2,
    ZIG3270_CONNECTION_FAILED = 3,
    ZIG3270_PARSE_ERROR = 4,
    ZIG3270_INVALID_STATE = 5,
    ZIG3270_TIMEOUT = 6,
    ZIG3270_FIELD_NOT_FOUND = 7,
} zig3270_error_t;

/* ========================================================================== */
/* Opaque Types                                                             */
/* ========================================================================== */

typedef struct zig3270_client zig3270_client_t;
typedef struct zig3270_screen zig3270_screen_t;
typedef struct zig3270_field_manager zig3270_field_manager_t;
typedef struct zig3270_parser zig3270_parser_t;

/* ========================================================================== */
/* Type Definitions                                                         */
/* ========================================================================== */

/**
 * Screen address (row, column)
 */
typedef struct {
    uint8_t row;
    uint8_t col;
} zig3270_address_t;

/**
 * Field attribute byte
 * 
 * Bit layout:
 *   Bit 0: protected (1 = protected, 0 = unprotected)
 *   Bit 1: numeric (1 = numeric only, 0 = alphanumeric)
 *   Bit 2: hidden (1 = hidden, 0 = visible)
 *   Bit 3: intensity (1 = bright, 0 = normal)
 *   Bits 4-7: reserved
 */
typedef struct {
    uint8_t value;  /* Raw attribute byte */
} zig3270_field_attr_t;

/**
 * TN3270 Command Code
 */
typedef enum {
    ZIG3270_CMD_WRITE_STRUCTURED_FIELD = 0x01,
    ZIG3270_CMD_ERASE_WRITE = 0x05,
    ZIG3270_CMD_ERASE_WRITE_ALTERNATE = 0x0d,
    ZIG3270_CMD_WRITE = 0x01,
    ZIG3270_CMD_ERASE_ALL_UNPROTECTED = 0x0f,
    ZIG3270_CMD_READ_BUFFER = 0x02,
    ZIG3270_CMD_READ_MODIFIED = 0x06,
    ZIG3270_CMD_READ_MODIFIED_ALL = 0x6e,
    ZIG3270_CMD_SEARCH_FOR_STRING = 0x34,
    ZIG3270_CMD_SELECTIVE_ERASE_WRITE = 0x80,
} zig3270_command_code_t;

/**
 * Screen position (linear offset into 24x80 grid)
 * Offset ranges from 0-1919 (0 = top-left, 1919 = bottom-right)
 */
typedef struct {
    uint16_t offset;
} zig3270_position_t;

/* ========================================================================== */
/* Memory Management                                                        */
/* ========================================================================== */

/**
 * Allocate memory.
 * 
 * \param size Number of bytes to allocate
 * \return Pointer to allocated memory, or NULL on failure
 * 
 * Memory must be freed with zig3270_free().
 */
uint8_t* zig3270_malloc(size_t size);

/**
 * Free memory previously allocated with zig3270_malloc().
 * 
 * \param ptr Pointer to memory to free
 * \param size Size of allocation (must match allocation size)
 */
void zig3270_free(uint8_t* ptr, size_t size);

/**
 * Free a C string.
 * 
 * \param str Null-terminated string returned by zig3270 functions
 */
void zig3270_string_free(char* str);

/* ========================================================================== */
/* Protocol Functions                                                       */
/* ========================================================================== */

/**
 * Decode a single EBCDIC byte to ASCII.
 * 
 * \param ebcdic_byte EBCDIC byte value
 * \return ASCII byte value
 */
uint8_t zig3270_ebcdic_decode_byte(uint8_t ebcdic_byte);

/**
 * Encode a single ASCII byte to EBCDIC.
 * 
 * \param ascii_byte ASCII byte value
 * \return EBCDIC byte value (0-255), or -1 on error
 */
int32_t zig3270_ebcdic_encode_byte(uint8_t ascii_byte);

/**
 * Decode EBCDIC buffer to ASCII.
 * 
 * \param ebcdic_buf Input EBCDIC data
 * \param ebcdic_len Length of EBCDIC data
 * \param ascii_buf Output buffer for ASCII data
 * \param ascii_len Size of output buffer
 * \return Number of bytes decoded, or negative error code
 * 
 * The output buffer must be at least ebcdic_len bytes.
 */
int32_t zig3270_ebcdic_decode(
    const uint8_t* ebcdic_buf,
    size_t ebcdic_len,
    uint8_t* ascii_buf,
    size_t ascii_len
);

/**
 * Encode ASCII buffer to EBCDIC.
 * 
 * \param ascii_buf Input ASCII data
 * \param ascii_len Length of ASCII data
 * \param ebcdic_buf Output buffer for EBCDIC data
 * \param ebcdic_len Size of output buffer
 * \return Number of bytes encoded, or negative error code
 * 
 * The output buffer must be at least ascii_len bytes.
 */
int32_t zig3270_ebcdic_encode(
    const uint8_t* ascii_buf,
    size_t ascii_len,
    uint8_t* ebcdic_buf,
    size_t ebcdic_len
);

/* ========================================================================== */
/* Client Functions                                                         */
/* ========================================================================== */

/**
 * Create a new TN3270 client.
 * 
 * \param host Hostname or IP address of TN3270 server
 * \param port Port number (typically 23 for telnet)
 * \return 0 on success, negative error code on failure
 * 
 * The returned client pointer must be freed with zig3270_client_free().
 */
int32_t zig3270_client_new(const char* host, uint16_t port);

/**
 * Free a TN3270 client.
 * 
 * \param client Client pointer returned by zig3270_client_new()
 * 
 * If client is connected, it will be disconnected automatically.
 */
void zig3270_client_free(zig3270_client_t* client);

/**
 * Connect to the mainframe.
 * 
 * \param client Client pointer
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_client_connect(zig3270_client_t* client);

/**
 * Disconnect from the mainframe.
 * 
 * \param client Client pointer
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_client_disconnect(zig3270_client_t* client);

/**
 * Send a command to the mainframe.
 * 
 * \param client Client pointer
 * \param command Raw command data
 * \param command_len Length of command data
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_client_send_command(
    zig3270_client_t* client,
    const uint8_t* command,
    size_t command_len
);

/**
 * Read response from mainframe (blocking).
 * 
 * \param client Client pointer
 * \param buffer Output buffer for response
 * \param buffer_len Size of output buffer
 * \param timeout_ms Timeout in milliseconds (0 = no timeout)
 * \return Number of bytes read, or negative error code
 */
int32_t zig3270_client_read_response(
    zig3270_client_t* client,
    uint8_t* buffer,
    size_t buffer_len,
    uint32_t timeout_ms
);

/* ========================================================================== */
/* Screen Functions                                                         */
/* ========================================================================== */

/**
 * Create a new screen (24x80).
 * 
 * \return 0 on success, negative error code on failure
 * 
 * The returned screen pointer must be freed with zig3270_screen_free().
 */
int32_t zig3270_screen_new(void);

/**
 * Free a screen.
 * 
 * \param screen Screen pointer returned by zig3270_screen_new()
 */
void zig3270_screen_free(zig3270_screen_t* screen);

/**
 * Clear the screen (fill with spaces).
 * 
 * \param screen Screen pointer
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_screen_clear(zig3270_screen_t* screen);

/**
 * Write text to screen at position.
 * 
 * \param screen Screen pointer
 * \param row Row position (0-23)
 * \param col Column position (0-79)
 * \param text Text to write
 * \param text_len Length of text
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_screen_write(
    zig3270_screen_t* screen,
    uint8_t row,
    uint8_t col,
    const uint8_t* text,
    size_t text_len
);

/**
 * Read text from screen at position.
 * 
 * \param screen Screen pointer
 * \param row Row position (0-23)
 * \param col Column position (0-79)
 * \param buffer Output buffer
 * \param buffer_len Size of output buffer
 * \return Number of bytes read, or negative error code
 */
int32_t zig3270_screen_read(
    zig3270_screen_t* screen,
    uint8_t row,
    uint8_t col,
    uint8_t* buffer,
    size_t buffer_len
);

/**
 * Get entire screen as string.
 * 
 * \param screen Screen pointer
 * \return Null-terminated string containing screen content, or NULL on error
 * 
 * The returned string must be freed with zig3270_string_free().
 */
char* zig3270_screen_to_string(zig3270_screen_t* screen);

/**
 * Get current cursor position.
 * 
 * \param screen Screen pointer
 * \param addr Output parameter for address
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_screen_get_cursor(zig3270_screen_t* screen, zig3270_address_t* addr);

/* ========================================================================== */
/* Field Functions                                                          */
/* ========================================================================== */

/**
 * Create a new field manager.
 * 
 * \return 0 on success, negative error code on failure
 * 
 * The returned field manager pointer must be freed with zig3270_fields_free().
 */
int32_t zig3270_fields_new(void);

/**
 * Free a field manager.
 * 
 * \param fields Field manager pointer returned by zig3270_fields_new()
 */
void zig3270_fields_free(zig3270_field_manager_t* fields);

/**
 * Add a field to the manager.
 * 
 * \param fields Field manager pointer
 * \param offset Screen offset (0-1919)
 * \param length Field length in characters
 * \param attr Field attributes
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_fields_add(
    zig3270_field_manager_t* fields,
    uint16_t offset,
    uint16_t length,
    zig3270_field_attr_t attr
);

/**
 * Get number of fields.
 * 
 * \param fields Field manager pointer
 * \return Field count
 */
uint32_t zig3270_fields_count(zig3270_field_manager_t* fields);

/**
 * Get field information by index.
 * 
 * \param fields Field manager pointer
 * \param index Field index (0-based)
 * \param offset Output parameter for field offset
 * \param length Output parameter for field length
 * \return 0 on success, negative error code on failure
 */
int32_t zig3270_fields_get(
    zig3270_field_manager_t* fields,
    uint32_t index,
    uint16_t* offset,
    uint16_t* length
);

/* ========================================================================== */
/* Version & Info                                                           */
/* ========================================================================== */

/**
 * Get library version string.
 * 
 * \return Version string (e.g., "0.11.1-beta")
 */
const char* zig3270_version(void);

/**
 * Get TN3270 protocol version.
 * 
 * \return Protocol version string (e.g., "TN3270E")
 */
const char* zig3270_protocol_version(void);

#ifdef __cplusplus
}
#endif

#endif /* ZIG3270_H */
