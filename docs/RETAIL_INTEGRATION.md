# Retail Integration Guide

**Version**: v0.11.3  
**Last Updated**: Dec 23, 2025

This guide covers integration of zig-3270 with retail point-of-sale (POS), inventory management, and transaction processing systems.

---

## Table of Contents

1. [TN3270 in Retail Point-of-Sale](#tn3270-in-retail-point-of-sale)
2. [Inventory Management](#inventory-management)
3. [Transaction Processing](#transaction-processing)
4. [Customer Lookup](#customer-lookup)
5. [Performance Under Load](#performance-under-load)
6. [Failover for POS Systems](#failover-for-pos-systems)
7. [Real-Time Synchronization](#real-time-synchronization)
8. [Reporting and Reconciliation](#reporting-and-reconciliation)

---

## TN3270 in Retail Point-of-Sale

### Retail System Overview

Modern retail chains use TN3270 for:

1. **Point-of-Sale**: Transaction processing at checkout
2. **Inventory**: Real-time stock levels and updates
3. **Customer Management**: Loyalty programs, returns
4. **Pricing**: Dynamic pricing and promotions
5. **Reporting**: Daily sales, inventory, and financial reports

### POS Configuration

```zig
pub const RetailPOSConfig = struct {
    // Connection
    host: []const u8 = "mainframe.retail.local",
    port: u16 = 23,  // Plain telnet for POS speed
    use_tls: bool = false,  // Most retail POS uses unencrypted for speed
    
    // Performance
    read_timeout_ms: u32 = 5000,    // Faster timeouts for retail
    write_timeout_ms: u32 = 2000,
    
    // POS-specific
    store_id: []const u8,
    register_id: []const u8,
    shift_id: []const u8,
};

pub fn create_pos_client(
    allocator: std.mem.Allocator,
    config: RetailPOSConfig,
) !Client {
    var client = try Client.init(allocator, config.host, config.port);
    client.set_read_timeout(config.read_timeout_ms);
    client.set_write_timeout(config.write_timeout_ms);
    return client;
}
```

---

## Inventory Management

### Real-Time Stock Checking

```zig
pub const InventoryItem = struct {
    sku: [12]u8,              // Stock Keeping Unit
    upc: [13]u8,              // Universal Product Code
    description: []const u8,
    on_hand: u32,
    allocated: u32,
    available: u32,
    reorder_point: u32,
    reorder_quantity: u32,
    last_updated: i64,
};

pub fn check_inventory(
    allocator: std.mem.Allocator,
    client: *Client,
    sku: []const u8,
) !InventoryItem {
    // Send inventory lookup command
    var lookup_cmd = try std.fmt.allocPrint(allocator, "INV:{s}", .{sku});
    defer allocator.free(lookup_cmd);
    
    var lookup_ebcdic = try ebcdic.encode_alloc(allocator, lookup_cmd);
    defer allocator.free(lookup_ebcdic);
    try client.write(lookup_ebcdic);
    
    // Read response
    var data = try client.read();
    defer allocator.free(data);
    
    // Parse inventory response
    var item = try parse_inventory_item(allocator, data);
    return item;
}

pub fn update_inventory(
    allocator: std.mem.Allocator,
    client: *Client,
    sku: []const u8,
    quantity_sold: u32,
) !void {
    // Send inventory update
    var update_cmd = try std.fmt.allocPrint(
        allocator,
        "UPDINV:{s}:{d}",
        .{ sku, quantity_sold },
    );
    defer allocator.free(update_cmd);
    
    var update_ebcdic = try ebcdic.encode_alloc(allocator, update_cmd);
    defer allocator.free(update_ebcdic);
    try client.write(update_ebcdic);
    
    var data = try client.read();
    defer allocator.free(data);
    
    if (std.mem.indexOf(u8, data, "OK") == null) {
        return error.InventoryUpdateFailed;
    }
}

fn parse_inventory_item(
    allocator: std.mem.Allocator,
    data: []const u8,
) !InventoryItem {
    // Parse inventory response from mainframe
    var item: InventoryItem = undefined;
    // Parse SKU, UPC, on-hand, allocated, etc.
    return item;
}
```

---

## Transaction Processing

### Point-of-Sale Transaction

```zig
pub const POSTransaction = struct {
    transaction_id: []const u8,
    timestamp: i64,
    store_id: []const u8,
    register_id: []const u8,
    items: std.ArrayList(LineItem),
    subtotal: f64,
    tax: f64,
    total: f64,
    payment_method: enum { Cash, Card, Check, Other },
    status: enum { Pending, Complete, Voided },
};

pub const LineItem = struct {
    sku: []const u8,
    quantity: u32,
    unit_price: f64,
    line_total: f64,
};

pub fn process_transaction(
    allocator: std.mem.Allocator,
    client: *Client,
    txn: *POSTransaction,
) !void {
    // Step 1: Send transaction header
    var header = try std.fmt.allocPrint(
        allocator,
        "TXNHDR:{s}:{s}:{s}",
        .{ txn.store_id, txn.register_id, txn.transaction_id },
    );
    defer allocator.free(header);
    
    var header_ebcdic = try ebcdic.encode_alloc(allocator, header);
    defer allocator.free(header_ebcdic);
    try client.write(header_ebcdic);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Step 2: Send line items
    for (txn.items.items) |item| {
        var line = try std.fmt.allocPrint(
            allocator,
            "ITEM:{s}:{d}:{d:.2}",
            .{ item.sku, item.quantity, item.unit_price },
        );
        defer allocator.free(line);
        
        var line_ebcdic = try ebcdic.encode_alloc(allocator, line);
        defer allocator.free(line_ebcdic);
        try client.write(line_ebcdic);
        
        data = try client.read();
        defer allocator.free(data);
    }
    
    // Step 3: Send totals
    var totals = try std.fmt.allocPrint(
        allocator,
        "TOTAL:{d:.2}:{d:.2}:{d:.2}",
        .{ txn.subtotal, txn.tax, txn.total },
    );
    defer allocator.free(totals);
    
    var totals_ebcdic = try ebcdic.encode_alloc(allocator, totals);
    defer allocator.free(totals_ebcdic);
    try client.write(totals_ebcdic);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 4: Send payment method
    var payment = try std.fmt.allocPrint(
        allocator,
        "PAYMENT:{}",
        .{@tagName(txn.payment_method)},
    );
    defer allocator.free(payment);
    
    var payment_ebcdic = try ebcdic.encode_alloc(allocator, payment);
    defer allocator.free(payment_ebcdic);
    try client.write(payment_ebcdic);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 5: Complete transaction
    var complete = try ebcdic.encode_alloc(allocator, "COMPLETE");
    defer allocator.free(complete);
    try client.write(complete);
    
    data = try client.read();
    defer allocator.free(data);
    
    if (std.mem.indexOf(u8, data, "OK") != null) {
        txn.status = .Complete;
    } else {
        return error.TransactionFailed;
    }
}
```

---

## Customer Lookup

### Loyalty Program Integration

```zig
pub const Customer = struct {
    customer_id: []const u8,
    loyalty_number: []const u8,
    first_name: []const u8,
    last_name: []const u8,
    email: []const u8,
    phone: []const u8,
    loyalty_points: u32,
    total_purchases: f64,
    member_since: i64,
};

pub fn lookup_customer(
    allocator: std.mem.Allocator,
    client: *Client,
    loyalty_number: []const u8,
) !?Customer {
    // Send customer lookup
    var lookup = try std.fmt.allocPrint(
        allocator,
        "CUST:{s}",
        .{loyalty_number},
    );
    defer allocator.free(lookup);
    
    var lookup_ebcdic = try ebcdic.encode_alloc(allocator, lookup);
    defer allocator.free(lookup_ebcdic);
    try client.write(lookup_ebcdic);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Parse customer record
    if (std.mem.indexOf(u8, data, "NOTFOUND") != null) {
        return null;
    }
    
    var customer = try parse_customer(allocator, data);
    return customer;
}

pub fn update_loyalty_points(
    allocator: std.mem.Allocator,
    client: *Client,
    customer_id: []const u8,
    points_to_add: u32,
) !void {
    var update = try std.fmt.allocPrint(
        allocator,
        "ADDPTS:{s}:{d}",
        .{ customer_id, points_to_add },
    );
    defer allocator.free(update);
    
    var update_ebcdic = try ebcdic.encode_alloc(allocator, update);
    defer allocator.free(update_ebcdic);
    try client.write(update_ebcdic);
    
    var data = try client.read();
    defer allocator.free(data);
}

fn parse_customer(
    allocator: std.mem.Allocator,
    data: []const u8,
) !Customer {
    // Parse customer record from response
    return .{
        .customer_id = "",
        .loyalty_number = "",
        .first_name = "",
        .last_name = "",
        .email = "",
        .phone = "",
        .loyalty_points = 0,
        .total_purchases = 0.0,
        .member_since = 0,
    };
}
```

---

## Performance Under Load

### Connection Pooling for High-Throughput

```zig
pub fn create_pos_pool(
    allocator: std.mem.Allocator,
    config: RetailPOSConfig,
    pool_size: usize,
) !SessionPool {
    var pool = try SessionPool.init(allocator, pool_size);
    
    // Pre-warm connections
    var i: usize = 0;
    while (i < pool_size) : (i += 1) {
        var client = try create_pos_client(allocator, config);
        try client.connect();
        try pool.add_session(client);
    }
    
    return pool;
}

pub fn process_transaction_from_pool(
    pool: *SessionPool,
    txn: *POSTransaction,
    allocator: std.mem.Allocator,
) !void {
    var client = try pool.acquire();
    defer pool.release(client);
    
    try process_transaction(allocator, client, txn);
}
```

### Caching for Frequent Lookups

```zig
pub const CatalogCache = struct {
    items: std.AutoHashMap([]const u8, InventoryItem),
    last_refresh: i64,
    ttl_ms: u32,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) CatalogCache {
        return .{
            .items = std.AutoHashMap([]const u8, InventoryItem).init(allocator),
            .last_refresh = 0,
            .ttl_ms = 60000,  // 1 minute cache
            .allocator = allocator,
        };
    }
    
    pub fn get_item(self: *CatalogCache, client: *Client, sku: []const u8) !InventoryItem {
        var now = std.time.milliTimestamp();
        
        // Check cache
        if (self.items.get(sku)) |cached_item| {
            if ((now - self.last_refresh) < self.ttl_ms) {
                return cached_item;
            }
        }
        
        // Fetch from mainframe
        var item = try check_inventory(self.allocator, client, sku);
        try self.items.put(sku, item);
        self.last_refresh = now;
        
        return item;
    }
    
    pub fn deinit(self: *CatalogCache) void {
        self.items.deinit();
    }
};
```

---

## Failover for POS Systems

### Load Balancing Multiple Mainframes

```zig
pub fn create_failover_pool(
    allocator: std.mem.Allocator,
    endpoints: []const struct { host: []const u8, port: u16 },
) !LoadBalancer {
    // Create load balancer with least-connections strategy
    var lb = try LoadBalancer.init(.LeastConnections, endpoints);
    return lb;
}

pub fn process_with_failover(
    allocator: std.mem.Allocator,
    lb: *LoadBalancer,
    operation: fn (*Client) !void,
) !void {
    var endpoint = try lb.select_endpoint();
    
    var client = try Client.init(allocator, endpoint.host, endpoint.port);
    defer client.disconnect();
    
    operation(&client) catch |err| {
        // Report failure to load balancer
        lb.report_failure(endpoint);
        
        // Try next endpoint
        endpoint = try lb.select_endpoint();
        client = try Client.init(allocator, endpoint.host, endpoint.port);
        defer client.disconnect();
        
        try operation(&client);
        lb.report_success(endpoint);
        return;
    };
    
    lb.report_success(endpoint);
}
```

---

## Real-Time Synchronization

### Inventory Sync During Day

```zig
pub fn sync_inventory(
    allocator: std.mem.Allocator,
    client: *Client,
    skus: []const []const u8,
) !void {
    // Send batch inventory sync
    var sync_header = try ebcdic.encode_alloc(allocator, "SYNCINV");
    defer allocator.free(sync_header);
    try client.write(sync_header);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Send each SKU's update
    for (skus) |sku| {
        var item = try check_inventory(allocator, client, sku);
        
        // Process item updates
    }
    
    // Finalize sync
    var sync_end = try ebcdic.encode_alloc(allocator, "SYNCEND");
    defer allocator.free(sync_end);
    try client.write(sync_end);
    
    data = try client.read();
    defer allocator.free(data);
}
```

---

## Reporting and Reconciliation

### End-of-Day Reporting

```zig
pub const DailySalesReport = struct {
    report_date: []const u8,
    store_id: []const u8,
    total_sales: f64,
    total_transactions: u32,
    total_customers: u32,
    total_discounts: f64,
    total_tax: f64,
    inventory_variance: f64,
};

pub fn generate_daily_report(
    allocator: std.mem.Allocator,
    client: *Client,
    store_id: []const u8,
    report_date: []const u8,
) !DailySalesReport {
    // Request daily report
    var report_cmd = try std.fmt.allocPrint(
        allocator,
        "REPORT:{s}:{s}",
        .{ store_id, report_date },
    );
    defer allocator.free(report_cmd);
    
    var report_ebcdic = try ebcdic.encode_alloc(allocator, report_cmd);
    defer allocator.free(report_ebcdic);
    try client.write(report_ebcdic);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Parse report
    var report = try parse_daily_report(allocator, data, store_id, report_date);
    return report;
}

fn parse_daily_report(
    allocator: std.mem.Allocator,
    data: []const u8,
    store_id: []const u8,
    report_date: []const u8,
) !DailySalesReport {
    return .{
        .report_date = try allocator.dupe(u8, report_date),
        .store_id = try allocator.dupe(u8, store_id),
        .total_sales = 0.0,
        .total_transactions = 0,
        .total_customers = 0,
        .total_discounts = 0.0,
        .total_tax = 0.0,
        .inventory_variance = 0.0,
    };
}
```

---

## Complete Retail POS Example

```zig
const std = @import("std");
const zig3270 = @import("zig-3270");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var config = RetailPOSConfig{
        .store_id = "STORE-001",
        .register_id = "REG-001",
        .shift_id = "SHIFT-001",
    };
    
    // Create POS client
    var client = try create_pos_client(allocator, config);
    defer client.disconnect();
    
    // Example: Process a sale
    var txn = POSTransaction{
        .transaction_id = "TXN123456",
        .timestamp = std.time.milliTimestamp(),
        .store_id = config.store_id,
        .register_id = config.register_id,
        .items = std.ArrayList(LineItem).init(allocator),
        .subtotal = 0.0,
        .tax = 0.0,
        .total = 0.0,
        .payment_method = .Card,
        .status = .Pending,
    };
    defer txn.items.deinit();
    
    // Add items
    try txn.items.append(.{
        .sku = "SKU-001",
        .quantity = 2,
        .unit_price = 29.99,
        .line_total = 59.98,
    });
    
    try txn.items.append(.{
        .sku = "SKU-002",
        .quantity = 1,
        .unit_price = 49.99,
        .line_total = 49.99,
    });
    
    txn.subtotal = 109.97;
    txn.tax = 8.79;
    txn.total = 118.76;
    
    // Process transaction
    try process_transaction(allocator, &client, &txn);
    
    std.debug.print("Transaction {} completed\n", .{txn.transaction_id});
    std.debug.print("Total: ${d:.2}\n", .{txn.total});
}
```

---

## Best Practices

1. **Use connection pooling** for high-throughput POS systems
2. **Implement local caching** for frequently accessed items
3. **Validate SKU and pricing** before submission
4. **Handle inventory updates** atomically
5. **Log all transactions** for reconciliation
6. **Implement failover** to multiple mainframes
7. **Monitor response times** to detect issues
8. **Batch inventory updates** for efficiency
9. **Verify payment processing** before completing transaction
10. **Archive transaction logs** for audit trail

