const std = @import("std");

pub const HttpMethod = enum {
    get,
    post,
    put,
    delete,
    patch,
};

pub const HttpStatus = enum(u16) {
    ok = 200,
    created = 201,
    no_content = 204,
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    internal_error = 500,
    service_unavailable = 503,
};

pub const ApiRequest = struct {
    method: HttpMethod,
    path: []const u8,
    body: ?[]const u8 = null,
    headers: std.StringHashMap([]const u8),
};

pub const ApiResponse = struct {
    status: HttpStatus,
    body: []const u8,
    content_type: []const u8 = "application/json",
};

pub const SessionRequest = struct {
    host: []const u8,
    port: u16,
    application: ?[]const u8 = null,
    user: ?[]const u8 = null,
};

pub const SessionResponse = struct {
    id: []const u8,
    host: []const u8,
    port: u16,
    status: []const u8,
    created_at: i64,
};

pub const ScreenData = struct {
    rows: u32 = 24,
    cols: u32 = 80,
    content: []const u8,
};

pub const ScreenResponse = struct {
    session_id: []const u8,
    screen_data: ScreenData,
    cursor_row: u32 = 0,
    cursor_col: u32 = 0,
};

pub const ErrorResponse = struct {
    err: []const u8,
    message: []const u8,
    status: u16,
};

pub const AuthConfig = struct {
    enabled: bool = false,
    auth_type: enum { none, basic, bearer } = .none,
    token: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
};

pub const RateLimitConfig = struct {
    enabled: bool = false,
    max_requests: u32 = 1000,
    window_seconds: u32 = 60,
};

pub const RestApiConfig = struct {
    auth: AuthConfig = .{},
    rate_limit: RateLimitConfig = .{},
    enable_cors: bool = true,
    default_timeout_ms: u32 = 30000,
};

pub const RestAPI = struct {
    allocator: std.mem.Allocator,
    config: RestApiConfig,
    sessions: std.StringHashMap(SessionResponse),
    mutex: std.Thread.Mutex = .{},
    request_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, config: RestApiConfig) RestAPI {
        return .{
            .allocator = allocator,
            .config = config,
            .sessions = std.StringHashMap(SessionResponse).init(allocator),
        };
    }

    pub fn createSession(
        self: *RestAPI,
        req: SessionRequest,
        session_id: []const u8,
    ) !SessionResponse {
        self.mutex.lock();
        defer self.mutex.unlock();

        const response = SessionResponse{
            .id = session_id,
            .host = req.host,
            .port = req.port,
            .status = "connected",
            .created_at = std.time.milliTimestamp(),
        };

        try self.sessions.put(session_id, response);
        return response;
    }

    pub fn getSession(self: *RestAPI, session_id: []const u8) ?SessionResponse {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.sessions.get(session_id);
    }

    pub fn listSessions(self: *RestAPI) []const SessionResponse {
        self.mutex.lock();
        defer self.mutex.unlock();

        var result = std.ArrayList(SessionResponse).init(self.allocator);
        var it = self.sessions.valueIterator();
        while (it.next()) |session| {
            result.append(session.*) catch {};
        }
        return result.items;
    }

    pub fn deleteSession(self: *RestAPI, session_id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.sessions.remove(session_id);
    }

    pub fn checkAuth(self: *RestAPI, auth_header: ?[]const u8) bool {
        if (!self.config.auth.enabled) return true;
        if (auth_header == null) return false;

        switch (self.config.auth.auth_type) {
            .none => return true,
            .bearer => {
                if (self.config.auth.token) |token| {
                    return std.mem.eql(u8, auth_header.?, token);
                }
                return false;
            },
            .basic => {
                return std.mem.eql(u8, auth_header.?, "Basic authenticated");
            },
        }
    }

    pub fn incrementRequestCount(self: *RestAPI) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.request_count += 1;
    }

    pub fn checkRateLimit(self: *RestAPI) bool {
        if (!self.config.rate_limit.enabled) return true;

        self.mutex.lock();
        defer self.mutex.unlock();

        return self.request_count < self.config.rate_limit.max_requests;
    }

    pub fn deinit(self: *RestAPI) void {
        self.sessions.deinit();
    }
};

// Tests
const testing = std.testing;

test "rest_api: create session" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var api = RestAPI.init(allocator, .{});
    defer api.deinit();

    const req = SessionRequest{
        .host = "mainframe1.example.com",
        .port = 3270,
        .application = "CICS",
        .user = "testuser",
    };

    const session = try api.createSession(req, "sess_001");
    try testing.expect(std.mem.eql(u8, session.id, "sess_001"));
    try testing.expect(std.mem.eql(u8, session.host, "mainframe1.example.com"));
    try testing.expect(session.port == 3270);
}

test "rest_api: get session" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var api = RestAPI.init(allocator, .{});
    defer api.deinit();

    const req = SessionRequest{
        .host = "mainframe1.example.com",
        .port = 3270,
    };

    _ = try api.createSession(req, "sess_001");

    const session = api.getSession("sess_001");
    try testing.expect(session != null);
    try testing.expect(std.mem.eql(u8, session.?.id, "sess_001"));
}

test "rest_api: delete session" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var api = RestAPI.init(allocator, .{});
    defer api.deinit();

    const req = SessionRequest{
        .host = "mainframe1.example.com",
        .port = 3270,
    };

    _ = try api.createSession(req, "sess_001");
    const deleted = api.deleteSession("sess_001");
    try testing.expect(deleted);

    const session = api.getSession("sess_001");
    try testing.expect(session == null);
}

test "rest_api: list sessions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var api = RestAPI.init(allocator, .{});
    defer api.deinit();

    const req = SessionRequest{
        .host = "mainframe1.example.com",
        .port = 3270,
    };

    _ = try api.createSession(req, "sess_001");
    _ = try api.createSession(req, "sess_002");

    const sessions = api.listSessions();
    try testing.expect(sessions.len >= 2);
}

test "rest_api: authentication disabled" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var api = RestAPI.init(allocator, .{ .auth = .{ .enabled = false } });
    defer api.deinit();

    const result = api.checkAuth(null);
    try testing.expect(result);
}

test "rest_api: bearer token authentication" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var api = RestAPI.init(allocator, .{
        .auth = .{
            .enabled = true,
            .auth_type = .bearer,
            .token = "secret-token-123",
        },
    });
    defer api.deinit();

    const result = api.checkAuth("secret-token-123");
    try testing.expect(result);

    const invalid = api.checkAuth("wrong-token");
    try testing.expect(!invalid);
}

test "rest_api: rate limiting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var api = RestAPI.init(allocator, .{
        .rate_limit = .{
            .enabled = true,
            .max_requests = 5,
            .window_seconds = 60,
        },
    });
    defer api.deinit();

    for (0..5) |_| {
        api.incrementRequestCount();
    }

    const result = api.checkRateLimit();
    try testing.expect(!result);
}

test "rest_api: screen response" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const screen = ScreenResponse{
        .session_id = "sess_001",
        .screen_data = .{
            .rows = 24,
            .cols = 80,
            .content = "Hello World",
        },
        .cursor_row = 5,
        .cursor_col = 10,
    };

    try testing.expect(screen.screen_data.rows == 24);
    try testing.expect(screen.cursor_row == 5);
}

test "rest_api: error response" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const err_resp = ErrorResponse{
        .err = "SESSION_NOT_FOUND",
        .message = "The requested session does not exist",
        .status = 404,
    };

    try testing.expect(err_resp.status == 404);
    try testing.expect(std.mem.eql(u8, err_resp.err, "SESSION_NOT_FOUND"));
}
