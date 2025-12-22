const std = @import("std");
const audit_log = @import("audit_log.zig");

pub const RuleType = enum {
    access_control,
    data_retention,
    encryption_required,
    audit_mandatory,
    timeout_required,
    password_policy,
    session_limit,
    data_classification,
};

pub const Severity = enum {
    info,
    warning,
    critical,
};

pub const ComplianceRule = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    rule_type: RuleType,
    severity: Severity,
    enabled: bool = true,
};

pub const ComplianceViolation = struct {
    rule_id: []const u8,
    rule_name: []const u8,
    timestamp: i64,
    details: []const u8,
    severity: Severity,
    remediation: ?[]const u8 = null,
};

pub const ComplianceFramework = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(ComplianceRule),
    violations: std.ArrayList(ComplianceViolation),
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) ComplianceFramework {
        return .{
            .allocator = allocator,
            .rules = std.ArrayList(ComplianceRule).init(allocator),
            .violations = std.ArrayList(ComplianceViolation).init(allocator),
        };
    }

    pub fn addRule(self: *ComplianceFramework, rule: ComplianceRule) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.rules.append(rule);
    }

    pub fn removeRule(self: *ComplianceFramework, rule_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items, 0..) |rule, i| {
            if (std.mem.eql(u8, rule.id, rule_id)) {
                _ = self.rules.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn checkRule(self: *ComplianceFramework, rule_id: []const u8, condition: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |rule| {
            if (std.mem.eql(u8, rule.id, rule_id)) {
                if (!rule.enabled) return;

                if (!condition) {
                    const now = std.time.milliTimestamp();
                    const violation = ComplianceViolation{
                        .rule_id = rule.id,
                        .rule_name = rule.name,
                        .timestamp = now,
                        .details = rule.description,
                        .severity = rule.severity,
                        .remediation = null,
                    };
                    try self.violations.append(violation);
                }
                return;
            }
        }
    }

    pub fn recordViolation(
        self: *ComplianceFramework,
        rule_id: []const u8,
        details: []const u8,
        remediation: ?[]const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |rule| {
            if (std.mem.eql(u8, rule.id, rule_id)) {
                const now = std.time.milliTimestamp();
                const violation = ComplianceViolation{
                    .rule_id = rule.id,
                    .rule_name = rule.name,
                    .timestamp = now,
                    .details = details,
                    .severity = rule.severity,
                    .remediation = remediation,
                };
                try self.violations.append(violation);
                return;
            }
        }
    }

    pub fn getViolations(self: *ComplianceFramework) []const ComplianceViolation {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.violations.items;
    }

    pub fn getViolationCount(self: *ComplianceFramework) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.violations.items.len;
    }

    pub fn getViolationsBySeverity(
        self: *ComplianceFramework,
        allocator: std.mem.Allocator,
        severity: Severity,
    ) !std.ArrayList(ComplianceViolation) {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList(ComplianceViolation).init(allocator);
        for (self.violations.items) |violation| {
            if (violation.severity == severity) {
                try result.append(violation);
            }
        }
        return result;
    }

    pub fn clearViolations(self: *ComplianceFramework) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.violations.clearRetainingCapacity();
    }

    pub fn generateReport(
        self: *ComplianceFramework,
        allocator: std.mem.Allocator,
    ) !ComplianceReport {
        self.mutex.lock();
        defer self.mutex.unlock();

        var critical_count: u32 = 0;
        var warning_count: u32 = 0;
        var info_count: u32 = 0;

        for (self.violations.items) |violation| {
            switch (violation.severity) {
                .critical => critical_count += 1,
                .warning => warning_count += 1,
                .info => info_count += 1,
            }
        }

        return .{
            .total_rules = self.rules.items.len,
            .total_violations = self.violations.items.len,
            .critical_violations = critical_count,
            .warning_violations = warning_count,
            .info_violations = info_count,
            .enabled_rules = countEnabledRules(self),
        };
    }

    fn countEnabledRules(self: *const ComplianceFramework) u32 {
        var count: u32 = 0;
        for (self.rules.items) |rule| {
            if (rule.enabled) count += 1;
        }
        return count;
    }

    pub fn deinit(self: *ComplianceFramework) void {
        self.rules.deinit();
        self.violations.deinit();
    }
};

pub const ComplianceReport = struct {
    total_rules: usize,
    enabled_rules: u32,
    total_violations: usize,
    critical_violations: u32,
    warning_violations: u32,
    info_violations: u32,
};

// Standard compliance frameworks
pub const SOC2Framework = struct {
    pub fn createRules(allocator: std.mem.Allocator) !std.ArrayList(ComplianceRule) {
        var rules = std.ArrayList(ComplianceRule).init(allocator);

        try rules.append(.{
            .id = "soc2_001",
            .name = "Access Control",
            .description = "All access must be authenticated and authorized",
            .rule_type = .access_control,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "soc2_002",
            .name = "Audit Logging",
            .description = "All access and modifications must be logged",
            .rule_type = .audit_mandatory,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "soc2_003",
            .name = "Encryption",
            .description = "Data in transit must be encrypted",
            .rule_type = .encryption_required,
            .severity = .critical,
        });

        return rules;
    }
};

pub const HIPAAFramework = struct {
    pub fn createRules(allocator: std.mem.Allocator) !std.ArrayList(ComplianceRule) {
        var rules = std.ArrayList(ComplianceRule).init(allocator);

        try rules.append(.{
            .id = "hipaa_001",
            .name = "Access Control",
            .description = "Unique user identification required",
            .rule_type = .access_control,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "hipaa_002",
            .name = "Audit Controls",
            .description = "Comprehensive audit trails required",
            .rule_type = .audit_mandatory,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "hipaa_003",
            .name = "Encryption",
            .description = "PHI must be encrypted",
            .rule_type = .encryption_required,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "hipaa_004",
            .name = "Retention",
            .description = "Retain audit logs for 6 years",
            .rule_type = .data_retention,
            .severity = .critical,
        });

        return rules;
    }
};

pub const PCIDSSFramework = struct {
    pub fn createRules(allocator: std.mem.Allocator) !std.ArrayList(ComplianceRule) {
        var rules = std.ArrayList(ComplianceRule).init(allocator);

        try rules.append(.{
            .id = "pci_001",
            .name = "Session Timeout",
            .description = "Enforce session timeout after 15 minutes",
            .rule_type = .timeout_required,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "pci_002",
            .name = "Access Control",
            .description = "Restrict access by business need-to-know",
            .rule_type = .access_control,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "pci_003",
            .name = "Audit Logging",
            .description = "Track and monitor access to cardholder data",
            .rule_type = .audit_mandatory,
            .severity = .critical,
        });

        try rules.append(.{
            .id = "pci_004",
            .name = "Encryption",
            .description = "Encrypt cardholder data in transit and at rest",
            .rule_type = .encryption_required,
            .severity = .critical,
        });

        return rules;
    }
};

// Tests
const testing = std.testing;

test "compliance: add rule" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = ComplianceFramework.init(allocator);
    defer framework.deinit();

    const rule = ComplianceRule{
        .id = "test_001",
        .name = "Test Rule",
        .description = "A test compliance rule",
        .rule_type = .access_control,
        .severity = .warning,
    };

    try framework.addRule(rule);
    try testing.expect(framework.rules.items.len == 1);
}

test "compliance: remove rule" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = ComplianceFramework.init(allocator);
    defer framework.deinit();

    const rule = ComplianceRule{
        .id = "test_001",
        .name = "Test Rule",
        .description = "A test compliance rule",
        .rule_type = .access_control,
        .severity = .warning,
    };

    try framework.addRule(rule);
    const removed = framework.removeRule("test_001");
    try testing.expect(removed);
    try testing.expect(framework.rules.items.len == 0);
}

test "compliance: record violation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = ComplianceFramework.init(allocator);
    defer framework.deinit();

    const rule = ComplianceRule{
        .id = "test_001",
        .name = "Test Rule",
        .description = "A test compliance rule",
        .rule_type = .access_control,
        .severity = .critical,
    };

    try framework.addRule(rule);
    try framework.recordViolation("test_001", "Unauthorized access detected", "Block user");

    try testing.expect(framework.getViolationCount() == 1);
}

test "compliance: violations by severity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = ComplianceFramework.init(allocator);
    defer framework.deinit();

    const rules = [_]ComplianceRule{
        .{
            .id = "critical_1",
            .name = "Critical Rule",
            .description = "Critical",
            .rule_type = .access_control,
            .severity = .critical,
        },
        .{
            .id = "warning_1",
            .name = "Warning Rule",
            .description = "Warning",
            .rule_type = .access_control,
            .severity = .warning,
        },
    };

    for (rules) |rule| {
        try framework.addRule(rule);
    }

    try framework.recordViolation("critical_1", "Critical issue", null);
    try framework.recordViolation("warning_1", "Warning issue", null);

    var critical_viols = try framework.getViolationsBySeverity(allocator, .critical);
    defer critical_viols.deinit();

    try testing.expect(critical_viols.items.len == 1);
}

test "compliance: generate report" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = ComplianceFramework.init(allocator);
    defer framework.deinit();

    const rules = [_]ComplianceRule{
        .{
            .id = "rule_1",
            .name = "Rule 1",
            .description = "Rule 1",
            .rule_type = .access_control,
            .severity = .critical,
        },
        .{
            .id = "rule_2",
            .name = "Rule 2",
            .description = "Rule 2",
            .rule_type = .access_control,
            .severity = .warning,
        },
    };

    for (rules) |rule| {
        try framework.addRule(rule);
    }

    try framework.recordViolation("rule_1", "Issue 1", null);
    try framework.recordViolation("rule_2", "Issue 2", null);

    const report = try framework.generateReport(allocator);

    try testing.expect(report.total_rules == 2);
    try testing.expect(report.total_violations == 2);
    try testing.expect(report.critical_violations == 1);
    try testing.expect(report.warning_violations == 1);
}

test "compliance: SOC2 framework" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rules = try SOC2Framework.createRules(allocator);
    defer rules.deinit();

    try testing.expect(rules.items.len == 3);
    try testing.expect(std.mem.eql(u8, rules.items[0].id, "soc2_001"));
}

test "compliance: HIPAA framework" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rules = try HIPAAFramework.createRules(allocator);
    defer rules.deinit();

    try testing.expect(rules.items.len == 4);
    try testing.expect(rules.items[0].severity == .critical);
}

test "compliance: check rule condition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var framework = ComplianceFramework.init(allocator);
    defer framework.deinit();

    const rule = ComplianceRule{
        .id = "test_001",
        .name = "Test Rule",
        .description = "Test",
        .rule_type = .access_control,
        .severity = .critical,
    };

    try framework.addRule(rule);
    try framework.checkRule("test_001", true);

    try testing.expect(framework.getViolationCount() == 0);
}
