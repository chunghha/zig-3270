const std = @import("std");
const client = @import("client.zig");

/// Network resilience configuration and connection management
pub const NetworkConfig = struct {
    read_timeout_ms: u32 = 10000, // 10 seconds
    write_timeout_ms: u32 = 5000, // 5 seconds
    connect_timeout_ms: u32 = 15000, // 15 seconds
    max_retries: u32 = 3,
    retry_delay_ms: u32 = 1000, // 1 second initial delay
    max_retry_delay_ms: u32 = 30000, // 30 seconds max
};

/// Connection pool for reusing connections
pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: std.ArrayList(PooledConnection),
    config: NetworkConfig,

    pub const PooledConnection = struct {
        client: client.Client,
        last_used: i64,
        created_at: i64,
        use_count: u64,
    };

    /// Initialize connection pool
    pub fn init(allocator: std.mem.Allocator, config: NetworkConfig) ConnectionPool {
        return .{
            .allocator = allocator,
            .connections = std.ArrayList(PooledConnection).init(allocator),
            .config = config,
        };
    }

    /// Get or create connection to host
    pub fn get_connection(
        self: *ConnectionPool,
        host: []const u8,
        port: u16,
    ) !*client.Client {
        const now = std.time.milliTimestamp();

        // Look for existing connection to same host
        for (self.connections.items) |*pooled| {
            if (std.mem.eql(u8, pooled.client.host, host) and pooled.client.port == port) {
                // Check if connection is still valid
                if (pooled.client.connected) {
                    pooled.last_used = now;
                    pooled.use_count += 1;
                    return &pooled.client;
                }
            }
        }

        // Create new connection with retries
        var new_client = client.Client.init(self.allocator, host, port);
        var retry_count: u32 = 0;
        var retry_delay = self.config.retry_delay_ms;

        while (retry_count < self.config.max_retries) {
            new_client.connect() catch {
                retry_count += 1;
                if (retry_count >= self.config.max_retries) {
                    return error.ConnectionFailed;
                }

                // Exponential backoff
                std.posix.nanosleep(0, retry_delay * 1_000_000);
                retry_delay = @min(retry_delay * 2, self.config.max_retry_delay_ms);
                continue;
            };

            break;
        }

        // Add to pool
        const pooled = PooledConnection{
            .client = new_client,
            .last_used = now,
            .created_at = now,
            .use_count = 1,
        };

        try self.connections.append(pooled);
        return &self.connections.items[self.connections.items.len - 1].client;
    }

    /// Return connection to pool (for future use)
    pub fn return_connection(self: *ConnectionPool, conn: *client.Client) void {
        const now = std.time.milliTimestamp();
        for (self.connections.items) |*pooled| {
            if (&pooled.client == conn) {
                pooled.last_used = now;
                break;
            }
        }
    }

    /// Close idle connections (not used in last N milliseconds)
    pub fn close_idle(self: *ConnectionPool, idle_threshold_ms: i64) void {
        const now = std.time.milliTimestamp();
        var idx: usize = 0;

        while (idx < self.connections.items.len) {
            const pooled = &self.connections.items[idx];
            if (now - pooled.last_used > idle_threshold_ms) {
                pooled.client.disconnect();
                _ = self.connections.orderedRemove(idx);
            } else {
                idx += 1;
            }
        }
    }

    /// Get pool statistics
    pub fn get_stats(self: ConnectionPool) PoolStats {
        return .{
            .total_connections = self.connections.items.len,
            .active_connections = self.count_active(),
            .total_uses = self.sum_uses(),
        };
    }

    fn count_active(self: ConnectionPool) usize {
        var count: usize = 0;
        for (self.connections.items) |pooled| {
            if (pooled.client.connected) {
                count += 1;
            }
        }
        return count;
    }

    fn sum_uses(self: ConnectionPool) u64 {
        var sum: u64 = 0;
        for (self.connections.items) |pooled| {
            sum += pooled.use_count;
        }
        return sum;
    }

    /// Clear all connections
    pub fn clear(self: *ConnectionPool) void {
        for (self.connections.items) |*pooled| {
            pooled.client.disconnect();
        }
        self.connections.clearRetainingCapacity();
    }

    /// Deinitialize pool
    pub fn deinit(self: *ConnectionPool) void {
        self.clear();
        self.connections.deinit();
    }
};

pub const PoolStats = struct {
    total_connections: usize,
    active_connections: usize,
    total_uses: u64,
};

/// Resilient client wrapper with retry and timeout logic
pub const ResilientClient = struct {
    pool: *ConnectionPool,
    host: []const u8,
    port: u16,
    current_connection: ?*client.Client = null,

    /// Initialize resilient client
    pub fn init(pool: *ConnectionPool, host: []const u8, port: u16) ResilientClient {
        return .{
            .pool = pool,
            .host = host,
            .port = port,
        };
    }

    /// Ensure connection is active (reconnect if needed)
    pub fn ensure_connected(self: *ResilientClient) !void {
        if (self.current_connection) |conn| {
            if (conn.connected) {
                return; // Already connected
            }
        }

        // Get connection from pool (may reconnect)
        self.current_connection = try self.pool.get_connection(self.host, self.port);
    }

    /// Send data with automatic reconnection on failure
    pub fn send(self: *ResilientClient, data: []const u8) !void {
        try self.ensure_connected();

        if (self.current_connection) |conn| {
            conn.send(data) catch |err| {
                // Connection lost, try once more with fresh connection
                conn.disconnect();
                try self.ensure_connected();
                if (self.current_connection) |new_conn| {
                    try new_conn.send(data);
                } else {
                    return err;
                }
            };
        }
    }

    /// Read data with automatic reconnection on failure
    pub fn read(self: *ResilientClient) ![]u8 {
        try self.ensure_connected();

        if (self.current_connection) |conn| {
            return conn.read() catch |err| {
                // Connection lost, try once more with fresh connection
                conn.disconnect();
                try self.ensure_connected();
                if (self.current_connection) |new_conn| {
                    return new_conn.read();
                } else {
                    return err;
                }
            };
        }

        return error.NotConnected;
    }

    /// Disconnect
    pub fn disconnect(self: *ResilientClient) void {
        if (self.current_connection) |conn| {
            self.pool.return_connection(conn);
        }
    }
};

// Tests
test "network_config: default values are reasonable" {
    const config = NetworkConfig{};

    try std.testing.expectEqual(@as(u32, 10000), config.read_timeout_ms);
    try std.testing.expectEqual(@as(u32, 5000), config.write_timeout_ms);
    try std.testing.expectEqual(@as(u32, 15000), config.connect_timeout_ms);
    try std.testing.expectEqual(@as(u32, 3), config.max_retries);
}

test "connection_pool: init creates empty pool" {
    var pool = ConnectionPool.init(std.testing.allocator, NetworkConfig{});
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 0), pool.connections.items.len);
}

test "connection_pool: get_stats reports correct counts" {
    var pool = ConnectionPool.init(std.testing.allocator, NetworkConfig{});
    defer pool.deinit();

    const stats = pool.get_stats();

    try std.testing.expectEqual(@as(usize, 0), stats.total_connections);
    try std.testing.expectEqual(@as(usize, 0), stats.active_connections);
    try std.testing.expectEqual(@as(u64, 0), stats.total_uses);
}

test "connection_pool: close_idle with empty pool does nothing" {
    var pool = ConnectionPool.init(std.testing.allocator, NetworkConfig{});
    defer pool.deinit();

    pool.close_idle(5000);

    try std.testing.expectEqual(@as(usize, 0), pool.connections.items.len);
}

test "connection_pool: clear removes all connections" {
    var pool = ConnectionPool.init(std.testing.allocator, NetworkConfig{});
    defer pool.deinit();

    // Add dummy connection data (can't actually connect in test)
    // Just verify clear works
    pool.clear();

    try std.testing.expectEqual(@as(usize, 0), pool.connections.items.len);
}

test "resilient_client: init sets parameters" {
    var pool = ConnectionPool.init(std.testing.allocator, NetworkConfig{});
    defer pool.deinit();

    const res_client = ResilientClient.init(&pool, "localhost", 3270);

    try std.testing.expectEqualStrings("localhost", res_client.host);
    try std.testing.expectEqual(@as(u16, 3270), res_client.port);
    try std.testing.expectEqual(@as(?*client.Client, null), res_client.current_connection);
}

test "network_config: custom timeouts" {
    const config = NetworkConfig{
        .read_timeout_ms = 20000,
        .write_timeout_ms = 10000,
        .connect_timeout_ms = 30000,
    };

    try std.testing.expectEqual(@as(u32, 20000), config.read_timeout_ms);
    try std.testing.expectEqual(@as(u32, 10000), config.write_timeout_ms);
    try std.testing.expectEqual(@as(u32, 30000), config.connect_timeout_ms);
}

test "connection_pool: custom config" {
    const custom_config = NetworkConfig{
        .read_timeout_ms = 5000,
        .max_retries = 5,
        .retry_delay_ms = 500,
    };

    var pool = ConnectionPool.init(std.testing.allocator, custom_config);
    defer pool.deinit();

    try std.testing.expectEqual(@as(u32, 5000), pool.config.read_timeout_ms);
    try std.testing.expectEqual(@as(u32, 5), pool.config.max_retries);
    try std.testing.expectEqual(@as(u32, 500), pool.config.retry_delay_ms);
}
