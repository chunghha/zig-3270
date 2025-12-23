# Banking Integration Guide

**Version**: v0.11.3  
**Last Updated**: Dec 23, 2025

This guide covers integration of zig-3270 with banking mainframe systems, including account inquiry, fund transfers, and compliance requirements.

---

## Table of Contents

1. [TN3270 Protocol in Banking](#tn3270-protocol-in-banking)
2. [Account Inquiry Transaction Flow](#account-inquiry-transaction-flow)
3. [Fund Transfer Authorization Flow](#fund-transfer-authorization-flow)
4. [Error Handling for Financial Operations](#error-handling-for-financial-operations)
5. [Security Considerations](#security-considerations)
6. [Compliance Requirements](#compliance-requirements)
7. [Connection Pooling for Concurrent Transactions](#connection-pooling-for-concurrent-transactions)
8. [Performance Optimization](#performance-optimization)
9. [Monitoring and Alerting](#monitoring-and-alerting)
10. [Real-World Example: Account Balance Inquiry System](#real-world-example-account-balance-inquiry-system)

---

## TN3270 Protocol in Banking

### Historical Context

Banking institutions have used TN3270 protocol for decades due to:

1. **Mainframe Reliability**: IBM mainframes running CICS transaction servers
2. **ACID Guarantees**: Transactional consistency for financial data
3. **Legacy Integration**: Decades of business logic and compliance built into mainframe systems
4. **Proven Security**: End-to-end encryption and secure protocols

### Banking-Specific Protocol Features

```zig
// Banking typically uses:
// - TLS 1.2+ for encryption (PCI-DSS requirement)
// - EBCDIC encoding for mainframe character compatibility
// - Structured fields for banking-specific operations
// - Extended attributes for field validation (numeric, protected)

const banking_config = struct {
    host: []const u8 = "mainframe.bank.local",
    port: u16 = 992,  // TLS port (23 is plain text, rarely used in banking)
    use_tls: bool = true,
    tls_version: []const u8 = "1.2",
    cipher_suites: []const u8 = "HIGH:!aNULL:!MD5",
    read_timeout_ms: u32 = 30000,  // Financial operations may be slow
    write_timeout_ms: u32 = 5000,
};
```

---

## Account Inquiry Transaction Flow

### Typical Flow

```
Client            Mainframe (CICS)
  |                     |
  |---[CONNECT]-------->|  Establish TLS connection
  |<-----[WELCOME]------|  Display login screen
  |                     |
  |---[LOGIN]---------->|  Send credentials (EBCDIC)
  |<-----[MAIN MENU]----|  Authentication successful
  |                     |
  |---[ACCOUNT INQUIRY]-|  Select inquiry option
  |<-----[ACCOUNT FORM]-|  Screen with account number field
  |                     |
  |---[ENTER ACCOUNT]-->|  Input account number
  |<-----[BALANCE]------|  Display account balance
  |                     |
  |---[DISCONNECT]---->|  Close session
  |                     |
```

### Implementation Example

```zig
const std = @import("std");
const zig3270 = @import("zig-3270");

const Client = zig3270.client.Client;
const Screen = zig3270.screen.Screen;
const Parser = zig3270.protocol_layer.Parser;
const ebcdic = zig3270.ebcdic;

pub fn inquiry_account(
    allocator: std.mem.Allocator,
    client: *Client,
    account_number: []const u8,
) !struct {
    account: []const u8,
    balance: f64,
    currency: []const u8,
} {
    // Step 1: Wait for login prompt
    var screen = Screen.init();
    var data = try client.read();
    defer allocator.free(data);
    
    // Parse login screen
    var parser = Parser.init(allocator, data);
    var cmd = try parser.parse_command();
    
    // Step 2: Send login credentials
    var encoded_creds = try ebcdic.encode_alloc(allocator, "LOGIN USERNAME PASSWORD");
    defer allocator.free(encoded_creds);
    try client.write(encoded_creds);
    
    // Step 3: Wait for main menu
    data = try client.read();
    defer allocator.free(data);
    
    // Step 4: Send "Account Inquiry" command
    var inquiry_cmd = try ebcdic.encode_alloc(allocator, "ACCT");
    defer allocator.free(inquiry_cmd);
    try client.write(inquiry_cmd);
    
    // Step 5: Wait for account form
    data = try client.read();
    defer allocator.free(data);
    
    // Step 6: Send account number
    var account_ebcdic = try ebcdic.encode_alloc(allocator, account_number);
    defer allocator.free(account_ebcdic);
    try client.write(account_ebcdic);
    
    // Step 7: Read balance response
    data = try client.read();
    defer allocator.free(data);
    
    // Step 8: Parse response and extract balance
    var balance_str = extract_balance(data);
    var balance = try std.fmt.parseFloat(f64, balance_str);
    
    return .{
        .account = try allocator.dupe(u8, account_number),
        .balance = balance,
        .currency = "USD",
    };
}

fn extract_balance(data: []const u8) []const u8 {
    // Parse EBCDIC response and extract balance field
    // Typical format: "BALANCE: $1,234.56"
    return data;
}
```

---

## Fund Transfer Authorization Flow

### Authentication & Authorization

```zig
pub const TransferAuthorization = struct {
    from_account: []const u8,
    to_account: []const u8,
    amount: f64,
    currency: []const u8,
    authorization_code: []const u8,
    timestamp: i64,
    verified: bool = false,
};

pub fn authorize_transfer(
    allocator: std.mem.Allocator,
    client: *Client,
    auth: *TransferAuthorization,
) !void {
    // Step 1: Initiate transfer screen
    var transfer_init = try ebcdic.encode_alloc(allocator, "XFER");
    defer allocator.free(transfer_init);
    try client.write(transfer_init);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Step 2: Enter source account
    var from_account = try ebcdic.encode_alloc(allocator, auth.from_account);
    defer allocator.free(from_account);
    try client.write(from_account);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 3: Enter destination account
    var to_account = try ebcdic.encode_alloc(allocator, auth.to_account);
    defer allocator.free(to_account);
    try client.write(to_account);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 4: Enter amount
    var amount_str = try std.fmt.allocPrint(allocator, "{d:.2}", .{auth.amount});
    defer allocator.free(amount_str);
    var amount_ebcdic = try ebcdic.encode_alloc(allocator, amount_str);
    defer allocator.free(amount_ebcdic);
    try client.write(amount_ebcdic);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 5: Review and confirm
    var confirm = try ebcdic.encode_alloc(allocator, "CONFIRM");
    defer allocator.free(confirm);
    try client.write(confirm);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 6: Verify authorization (multi-factor auth)
    var auth_code = try ebcdic.encode_alloc(allocator, auth.authorization_code);
    defer allocator.free(auth_code);
    try client.write(auth_code);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 7: Confirm transfer submitted
    if (contains_success_message(data)) {
        auth.verified = true;
        auth.timestamp = std.time.milliTimestamp();
    } else {
        return error.TransferAuthorizationFailed;
    }
}

fn contains_success_message(data: []const u8) bool {
    // Check for "TRANSFER AUTHORIZED" or similar
    return std.mem.indexOf(u8, data, "AUTHORIZED") != null;
}
```

---

## Error Handling for Financial Operations

### Critical Error Codes

Banking systems use specific error codes that must be handled carefully:

```zig
pub const BankingError = enum {
    InvalidAccount = 0x1001,        // Account not found
    InsufficientFunds = 0x1002,     // Balance too low
    TransferLimitExceeded = 0x1003, // Daily limit reached
    AccountLocked = 0x1004,         // Account is locked
    AuthorizationFailed = 0x1005,   // Invalid credentials
    SystemUnavailable = 0x1006,     // Mainframe unavailable
    TransactionTimeout = 0x1007,    // Operation timed out
    DuplicateTransaction = 0x1008,  // Transaction already submitted
    SecurityViolation = 0x1009,     // Unauthorized access attempt
};

pub fn handle_banking_error(err: BankingError) !void {
    switch (err) {
        .InvalidAccount => {
            // Recovery: Prompt for correct account number
            return error.InvalidAccountNumber;
        },
        .InsufficientFunds => {
            // Recovery: Suggest lower transfer amount
            return error.BalanceTooLow;
        },
        .TransferLimitExceeded => {
            // Recovery: Inform user of daily limit
            return error.DailyLimitReached;
        },
        .AccountLocked => {
            // Recovery: Contact bank support
            return error.AccountLockedContactSupport;
        },
        .AuthorizationFailed => {
            // Recovery: Retry authentication (max 3 attempts)
            return error.InvalidCredentialsRetry;
        },
        .SystemUnavailable => {
            // Recovery: Retry with exponential backoff
            return error.SystemTemporarilyUnavailable;
        },
        .TransactionTimeout => {
            // Recovery: Check transaction status before retrying
            return error.OperationTimedOutCheckStatus;
        },
        .DuplicateTransaction => {
            // Recovery: Check transaction history
            return error.TransactionAlreadySubmitted;
        },
        .SecurityViolation => {
            // Recovery: Lock session and alert security team
            return error.SecurityViolationAlertRequired;
        },
    }
}
```

### Retry Logic for Transient Failures

```zig
pub fn retry_with_backoff(
    allocator: std.mem.Allocator,
    operation: fn (*Client) !void,
    client: *Client,
    max_retries: u32,
) !void {
    var attempt: u32 = 0;
    var backoff_ms: u32 = 100;
    
    while (attempt < max_retries) {
        operation(client) catch |err| {
            switch (err) {
                error.TransactionTimeout,
                error.SystemTemporarilyUnavailable,
                error.ConnectionLost => {
                    // Transient error, retry
                    attempt += 1;
                    if (attempt < max_retries) {
                        std.time.sleep(backoff_ms * std.time.ns_per_ms);
                        backoff_ms = @min(backoff_ms * 2, 30000); // Cap at 30 seconds
                        continue;
                    }
                },
                else => {
                    // Non-transient error, fail immediately
                    return err;
                },
            }
        };
        return; // Success
    }
    
    return error.MaxRetriesExceeded;
}
```

---

## Security Considerations

### Credential Handling

```zig
pub const SecureCredentials = struct {
    username: []u8,  // Will be overwritten
    password: []u8,  // Will be overwritten
    
    pub fn init(allocator: std.mem.Allocator, user: []const u8, pass: []const u8) !SecureCredentials {
        return .{
            .username = try allocator.dupe(u8, user),
            .password = try allocator.dupe(u8, pass),
        };
    }
    
    pub fn deinit(self: *SecureCredentials, allocator: std.mem.Allocator) void {
        // Overwrite credentials in memory before freeing
        std.mem.set(u8, self.username, 0);
        std.mem.set(u8, self.password, 0);
        allocator.free(self.username);
        allocator.free(self.password);
    }
    
    pub fn send_to_mainframe(
        self: *SecureCredentials,
        client: *Client,
        allocator: std.mem.Allocator,
    ) !void {
        // Encode in EBCDIC (required for mainframe)
        var encoded = try ebcdic.encode_alloc(
            allocator,
            try std.fmt.allocPrint(allocator, "{s}|{s}", .{ self.username, self.password }),
        );
        defer allocator.free(encoded);
        
        // Send over TLS connection
        try client.write(encoded);
        
        // Overwrite encoded copy
        std.mem.set(u8, encoded, 0);
    }
};
```

### Encryption & TLS

```zig
pub const BankingTLSConfig = struct {
    // PCI-DSS compliance requires TLS 1.2+
    min_tls_version: []const u8 = "1.2",
    max_tls_version: []const u8 = "1.3",
    
    // Cipher suites for financial systems
    cipher_suites: []const u8 = 
        "ECDHE-RSA-AES256-GCM-SHA384:" ++
        "ECDHE-RSA-AES128-GCM-SHA256:" ++
        "ECDHE-RSA-CHACHA20-POLY1305",
    
    // Certificate validation
    verify_hostname: bool = true,
    verify_certificate: bool = true,
    ca_bundle: ?[]const u8 = null,  // Path to CA bundle
    
    // Session security
    session_timeout_ms: u32 = 300000,  // 5 minutes
    idle_timeout_ms: u32 = 60000,      // 1 minute
};

pub fn create_secure_client(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    tls_config: BankingTLSConfig,
) !Client {
    var client = try Client.init(allocator, host, port);
    client.set_read_timeout(tls_config.session_timeout_ms);
    client.set_write_timeout(tls_config.session_timeout_ms);
    return client;
}
```

---

## Compliance Requirements

### PCI-DSS (Payment Card Industry)

```zig
pub const PCIDSSCompliance = struct {
    // 1. Firewall configuration (network level)
    // 2. No default credentials
    // 3. Protect cardholder data (encryption)
    // 4. Secure transmission (TLS 1.2+)
    // 5. Anti-virus software
    // 6. Secure development practices
    // 7. Restrict access by business need (field-level)
    // 8. Authenticate access (strong passwords)
    // 9. Restrict access by IP (network segmentation)
    // 10. Track and monitor network access (logging)
    // 11. Regular security testing
    // 12. Information security policy
    
    pub fn validate_compliance() !void {
        // Check TLS version
        // Verify authentication is enabled
        // Confirm logging is active
        // Validate firewall rules
        // Ensure data encryption at rest
    }
};
```

### HIPAA (Healthcare, but applies to banking records)

```zig
pub const AuditLog = struct {
    timestamp: i64,
    user_id: []const u8,
    operation: []const u8,
    account: []const u8,
    amount: f64,
    status: []const u8,
    ip_address: []const u8,
    
    pub fn log_transaction(self: AuditLog, allocator: std.mem.Allocator) !void {
        // Log to secure, immutable audit trail
        // Include timestamp, user, operation, account, result
        // Retention: minimum 7 years for banking
    }
};
```

---

## Connection Pooling for Concurrent Transactions

### SessionPool for Banking

```zig
pub fn create_banking_pool(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    pool_size: usize,
) !SessionPool {
    var pool = try SessionPool.init(allocator, pool_size);
    
    // Pre-warm connections (establish at startup)
    var i: usize = 0;
    while (i < pool_size) : (i += 1) {
        var client = try Client.init(allocator, host, port);
        try client.connect();
        try pool.add_session(client);
    }
    
    return pool;
}

pub fn execute_transaction(
    pool: *SessionPool,
    transaction_fn: fn (*Client) !void,
) !void {
    // Acquire connection from pool
    var client = try pool.acquire();
    defer pool.release(client);
    
    // Execute transaction
    try transaction_fn(client);
}
```

### Load Balancing Across Mainframes

```zig
pub fn create_load_balanced_pool(
    allocator: std.mem.Allocator,
    endpoints: []const struct { host: []const u8, port: u16 },
) !LoadBalancer {
    var lb = try LoadBalancer.init(.LeastConnections, endpoints);
    return lb;
}
```

---

## Performance Optimization

### Pipelining Queries

```zig
pub fn pipeline_transactions(
    client: *Client,
    allocator: std.mem.Allocator,
    accounts: []const []const u8,
) ![]struct { account: []const u8, balance: f64 } {
    var results = std.ArrayList(struct { account: []const u8, balance: f64 }).init(allocator);
    defer results.deinit();
    
    // Send all queries at once
    for (accounts) |account| {
        var query = try ebcdic.encode_alloc(allocator, 
            try std.fmt.allocPrint(allocator, "ACCT:{s}", .{account}));
        defer allocator.free(query);
        try client.write(query);
    }
    
    // Read all responses
    for (accounts) |account| {
        var data = try client.read();
        defer allocator.free(data);
        
        var balance = try parse_balance(data);
        try results.append(.{
            .account = try allocator.dupe(u8, account),
            .balance = balance,
        });
    }
    
    return results.items;
}

fn parse_balance(data: []const u8) !f64 {
    // Extract balance from response
    return 0.0;
}
```

### Field Caching

```zig
pub const BankingScreenCache = struct {
    last_screen: ?Screen = null,
    last_update: i64 = 0,
    cache_ttl_ms: u32 = 5000,
    
    pub fn get_cached_screen(self: *BankingScreenCache, client: *Client, allocator: std.mem.Allocator) !Screen {
        var now = std.time.milliTimestamp();
        
        if (self.last_screen != null and (now - self.last_update) < self.cache_ttl_ms) {
            // Return cached screen
            return self.last_screen.?;
        }
        
        // Fetch fresh screen
        var data = try client.read();
        defer allocator.free(data);
        
        var screen = try parse_screen(data);
        self.last_screen = screen;
        self.last_update = now;
        
        return screen;
    }
    
    fn parse_screen(data: []const u8) !Screen {
        return Screen.init();
    }
};
```

---

## Monitoring and Alerting

### Transaction Metrics

```zig
pub const TransactionMetrics = struct {
    total_transactions: u64 = 0,
    successful_transactions: u64 = 0,
    failed_transactions: u64 = 0,
    total_amount: f64 = 0.0,
    avg_latency_ms: f64 = 0.0,
    
    pub fn record_success(self: *TransactionMetrics, latency_ms: u32, amount: f64) void {
        self.total_transactions += 1;
        self.successful_transactions += 1;
        self.total_amount += amount;
        self.avg_latency_ms = (self.avg_latency_ms + @intToFloat(f64, latency_ms)) / 2.0;
    }
    
    pub fn record_failure(self: *TransactionMetrics) void {
        self.total_transactions += 1;
        self.failed_transactions += 1;
    }
    
    pub fn success_rate(self: *TransactionMetrics) f64 {
        if (self.total_transactions == 0) return 0.0;
        return @intToFloat(f64, self.successful_transactions) / @intToFloat(f64, self.total_transactions);
    }
};
```

### Health Checks

```zig
pub fn health_check_mainframe(client: *Client, allocator: std.mem.Allocator) !bool {
    // Send simple query to verify connectivity
    var ping = try ebcdic.encode_alloc(allocator, "PING");
    defer allocator.free(ping);
    
    client.write(ping) catch return false;
    
    var response = client.read() catch return false;
    defer allocator.free(response);
    
    return std.mem.indexOf(u8, response, "PONG") != null;
}
```

---

## Real-World Example: Account Balance Inquiry System

### Complete System

```zig
const std = @import("std");
const zig3270 = @import("zig-3270");

const Client = zig3270.client.Client;
const SessionPool = zig3270.session_pool.SessionPool;
const AuditLog = zig3270.audit_log.AuditLog;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Setup connection pool
    var pool = try create_banking_pool(
        allocator,
        "mainframe.bank.local",
        992,
        10,  // 10 concurrent connections
    );
    defer pool.deinit();
    
    // Setup audit logging
    var audit = try AuditLog.init(allocator);
    defer audit.deinit();
    
    // Setup metrics
    var metrics = TransactionMetrics{};
    
    // Process accounts
    var accounts = [_][]const u8{ "123456789", "987654321", "555555555" };
    
    for (accounts) |account| {
        var start = std.time.milliTimestamp();
        
        inquire_account(&pool, &audit, account, allocator) catch |err| {
            metrics.record_failure();
            try audit.log_event(.ErrorOccurred, .{
                .message = try std.fmt.allocPrint(allocator, "Failed to inquire account {s}: {}", .{ account, err }),
            });
            continue;
        };
        
        var latency = @intCast(u32, std.time.milliTimestamp() - start);
        metrics.record_success(latency, 0.0);
    }
    
    // Report metrics
    std.debug.print("Success rate: {d:.2}%\n", .{metrics.success_rate() * 100.0});
    std.debug.print("Average latency: {d:.2}ms\n", .{metrics.avg_latency_ms});
}

fn inquire_account(
    pool: *SessionPool,
    audit: *AuditLog,
    account: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var client = try pool.acquire();
    defer pool.release(client);
    
    // Execute inquiry
    var result = try inquiry_account(allocator, client, account);
    defer allocator.free(result.account);
    
    // Audit log
    try audit.log_event(.CommandExecuted, .{
        .message = try std.fmt.allocPrint(allocator, "Inquired account {s}: balance {d:.2}", .{ account, result.balance }),
    });
}
```

---

## Best Practices

1. **Always use TLS 1.2+** for banking connections
2. **Never log credentials** in audit trails
3. **Implement transaction verification** before committing
4. **Use connection pooling** to reduce latency
5. **Monitor response times** for degraded performance
6. **Implement circuit breakers** for failing endpoints
7. **Validate all user input** before sending to mainframe
8. **Maintain audit trails** for compliance
9. **Test error scenarios** thoroughly
10. **Keep credentials secure** with proper memory handling

---

## Additional Resources

- PCI-DSS Compliance: https://www.pcisecuritystandards.org/
- CICS Transaction Server: https://www.ibm.com/cloud/cics
- TN3270 Protocol: RFC 1572
- Mainframe Security: IBM System z Security

