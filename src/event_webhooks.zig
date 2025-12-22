const std = @import("std");

pub const EventType = enum {
    session_created,
    session_closed,
    session_suspended,
    session_resumed,
    authentication_success,
    authentication_failed,
    data_received,
    data_sent,
    error_occurred,
    connection_lost,
};

pub const WebhookEvent = struct {
    event_type: EventType,
    timestamp: i64,
    session_id: ?[]const u8 = null,
    data: ?[]const u8 = null,
};

pub const RetryConfig = struct {
    max_retries: u32 = 3,
    initial_delay_ms: u32 = 1000,
    max_delay_ms: u32 = 30000,
    backoff_multiplier: f32 = 2.0,
};

pub const Webhook = struct {
    id: []const u8,
    url: []const u8,
    events: std.ArrayList(EventType),
    secret: ?[]const u8 = null,
    active: bool = true,
    retry_config: RetryConfig = .{},
    created_at: i64 = 0,
};

pub const WebhookDelivery = struct {
    webhook_id: []const u8,
    event_type: EventType,
    timestamp: i64,
    status: DeliveryStatus,
    retry_count: u32 = 0,
    last_error: ?[]const u8 = null,
};

pub const DeliveryStatus = enum {
    pending,
    delivered,
    failed,
    retry,
};

pub const WebhookManager = struct {
    allocator: std.mem.Allocator,
    webhooks: std.StringHashMap(Webhook),
    deliveries: std.ArrayList(WebhookDelivery),
    event_queue: std.ArrayList(WebhookEvent),
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) WebhookManager {
        return .{
            .allocator = allocator,
            .webhooks = std.StringHashMap(Webhook).init(allocator),
            .deliveries = std.ArrayList(WebhookDelivery).init(allocator),
            .event_queue = std.ArrayList(WebhookEvent).init(allocator),
        };
    }

    pub fn registerWebhook(
        self: *WebhookManager,
        webhook_id: []const u8,
        url: []const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var webhook = Webhook{
            .id = webhook_id,
            .url = url,
            .events = std.ArrayList(EventType).init(self.allocator),
            .created_at = std.time.milliTimestamp(),
        };

        try self.webhooks.put(webhook_id, webhook);
    }

    pub fn subscribeToEvent(
        self: *WebhookManager,
        webhook_id: []const u8,
        event_type: EventType,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.webhooks.getPtr(webhook_id)) |webhook| {
            try webhook.events.append(event_type);
        }
    }

    pub fn unsubscribeFromEvent(
        self: *WebhookManager,
        webhook_id: []const u8,
        event_type: EventType,
    ) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.webhooks.getPtr(webhook_id)) |webhook| {
            for (webhook.events.items, 0..) |et, i| {
                if (et == event_type) {
                    _ = webhook.events.orderedRemove(i);
                    return true;
                }
            }
        }
        return false;
    }

    pub fn publishEvent(self: *WebhookManager, event: WebhookEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.event_queue.append(event);
    }

    pub fn processEvents(self: *WebhookManager) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.event_queue.items) |event| {
            var it = self.webhooks.valueIterator();
            while (it.next()) |webhook| {
                for (webhook.events.items) |subscribed_type| {
                    if (subscribed_type == event.event_type) {
                        const delivery = WebhookDelivery{
                            .webhook_id = webhook.id,
                            .event_type = event.event_type,
                            .timestamp = event.timestamp,
                            .status = .pending,
                        };
                        try self.deliveries.append(delivery);
                    }
                }
            }
        }

        self.event_queue.clearRetainingCapacity();
    }

    pub fn getWebhook(self: *WebhookManager, webhook_id: []const u8) ?Webhook {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.webhooks.get(webhook_id);
    }

    pub fn listWebhooks(self: *WebhookManager) []const Webhook {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList(Webhook).init(self.allocator);
        var it = self.webhooks.valueIterator();
        while (it.next()) |webhook| {
            result.append(webhook.*) catch {};
        }
        return result.items;
    }

    pub fn deactivateWebhook(self: *WebhookManager, webhook_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.webhooks.getPtr(webhook_id)) |webhook| {
            webhook.active = false;
            return true;
        }
        return false;
    }

    pub fn deleteWebhook(self: *WebhookManager, webhook_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.webhooks.remove(webhook_id);
    }

    pub fn getDeliveryStatus(
        self: *WebhookManager,
        webhook_id: []const u8,
    ) ?DeliveryStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.deliveries.items) |delivery| {
            if (std.mem.eql(u8, delivery.webhook_id, webhook_id)) {
                return delivery.status;
            }
        }
        return null;
    }

    pub fn deinit(self: *WebhookManager) void {
        var it = self.webhooks.valueIterator();
        while (it.next()) |webhook| {
            webhook.events.deinit();
        }
        self.webhooks.deinit();
        self.deliveries.deinit();
        self.event_queue.deinit();
    }
};

// Tests
const testing = std.testing;

test "webhook: register webhook" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = WebhookManager.init(allocator);
    defer manager.deinit();

    try manager.registerWebhook("wh_001", "https://example.com/webhook");

    const webhook = manager.getWebhook("wh_001");
    try testing.expect(webhook != null);
    try testing.expect(std.mem.eql(u8, webhook.?.url, "https://example.com/webhook"));
}

test "webhook: subscribe to event" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = WebhookManager.init(allocator);
    defer manager.deinit();

    try manager.registerWebhook("wh_001", "https://example.com/webhook");
    try manager.subscribeToEvent("wh_001", .session_created);

    const webhook = manager.getWebhook("wh_001");
    try testing.expect(webhook != null);
    try testing.expect(webhook.?.events.items.len == 1);
}

test "webhook: unsubscribe from event" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = WebhookManager.init(allocator);
    defer manager.deinit();

    try manager.registerWebhook("wh_001", "https://example.com/webhook");
    try manager.subscribeToEvent("wh_001", .session_created);

    const unsubscribed = manager.unsubscribeFromEvent("wh_001", .session_created);
    try testing.expect(unsubscribed);

    const webhook = manager.getWebhook("wh_001");
    try testing.expect(webhook != null);
    try testing.expect(webhook.?.events.items.len == 0);
}

test "webhook: publish and process events" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = WebhookManager.init(allocator);
    defer manager.deinit();

    try manager.registerWebhook("wh_001", "https://example.com/webhook");
    try manager.subscribeToEvent("wh_001", .session_created);

    const event = WebhookEvent{
        .event_type = .session_created,
        .timestamp = std.time.milliTimestamp(),
        .session_id = "sess_001",
    };

    try manager.publishEvent(event);
    try manager.processEvents();

    try testing.expect(manager.deliveries.items.len > 0);
}

test "webhook: deactivate webhook" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = WebhookManager.init(allocator);
    defer manager.deinit();

    try manager.registerWebhook("wh_001", "https://example.com/webhook");

    const deactivated = manager.deactivateWebhook("wh_001");
    try testing.expect(deactivated);

    const webhook = manager.getWebhook("wh_001");
    try testing.expect(webhook != null);
    try testing.expect(!webhook.?.active);
}

test "webhook: delete webhook" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = WebhookManager.init(allocator);
    defer manager.deinit();

    try manager.registerWebhook("wh_001", "https://example.com/webhook");

    const deleted = manager.deleteWebhook("wh_001");
    try testing.expect(deleted);

    const webhook = manager.getWebhook("wh_001");
    try testing.expect(webhook == null);
}

test "webhook: retry config" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const retry_config = RetryConfig{
        .max_retries = 5,
        .initial_delay_ms = 500,
        .max_delay_ms = 60000,
        .backoff_multiplier = 2.0,
    };

    try testing.expect(retry_config.max_retries == 5);
    try testing.expect(retry_config.initial_delay_ms == 500);
}
