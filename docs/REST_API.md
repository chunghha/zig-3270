# REST API Reference

**Version**: 0.9.3  
**Base URL**: `http://localhost:3270/api/v1`  
**Content-Type**: `application/json`

## Overview

The zig-3270 REST API provides programmatic access to session management, screen capture, and terminal emulation functionality. All endpoints require proper authentication if enabled and support JSON request/response formats.

## Authentication

### Disabled (Default)
No authentication required.

### Bearer Token
```http
Authorization: Bearer <token>
```

### Basic Auth
```http
Authorization: Basic <base64(username:password)>
```

## Rate Limiting

Rate limiting is optional. When enabled, responses include rate limit headers:

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1670000000
```

Error when limit exceeded:
```json
{
  "err": "RATE_LIMIT_EXCEEDED",
  "message": "Request limit exceeded. Retry after 60 seconds",
  "status": 429
}
```

## Sessions

### Create Session

**Endpoint**: `POST /sessions`

Creates a new TN3270 session.

**Request**:
```json
{
  "host": "mainframe.example.com",
  "port": 3270,
  "application": "CICS",
  "user": "john.doe"
}
```

**Response** (201):
```json
{
  "id": "sess_550e8400e29b41d4a716446655440000",
  "host": "mainframe.example.com",
  "port": 3270,
  "status": "connected",
  "created_at": 1670000000
}
```

**Errors**:
- `400` - Invalid request
- `401` - Unauthorized
- `500` - Connection failed

---

### List Sessions

**Endpoint**: `GET /sessions`

Lists all active sessions.

**Query Parameters**:
- `status` - Filter by status (connected, suspended, closed)
- `limit` - Number of results (default: 100)
- `offset` - Pagination offset (default: 0)

**Response** (200):
```json
{
  "sessions": [
    {
      "id": "sess_550e8400e29b41d4a716446655440000",
      "host": "mainframe.example.com",
      "port": 3270,
      "status": "connected",
      "created_at": 1670000000
    }
  ],
  "total": 1,
  "limit": 100,
  "offset": 0
}
```

---

### Get Session

**Endpoint**: `GET /sessions/{id}`

Gets details of a specific session.

**Response** (200):
```json
{
  "id": "sess_550e8400e29b41d4a716446655440000",
  "host": "mainframe.example.com",
  "port": 3270,
  "status": "connected",
  "created_at": 1670000000
}
```

**Errors**:
- `404` - Session not found
- `401` - Unauthorized

---

### Delete Session

**Endpoint**: `DELETE /sessions/{id}`

Closes and removes a session.

**Response** (204): No content

**Errors**:
- `404` - Session not found
- `401` - Unauthorized

---

### Get Screen

**Endpoint**: `GET /sessions/{id}/screen`

Captures the current terminal screen.

**Response** (200):
```json
{
  "session_id": "sess_550e8400e29b41d4a716446655440000",
  "screen_data": {
    "rows": 24,
    "cols": 80,
    "content": "Welcome to CICS\n..."
  },
  "cursor_row": 5,
  "cursor_col": 10
}
```

**Errors**:
- `404` - Session not found
- `401` - Unauthorized

---

### Send Input

**Endpoint**: `POST /sessions/{id}/input`

Sends keyboard input to the session.

**Request**:
```json
{
  "input": "SELECT OPTION ===> 5",
  "function_key": "ENTER"
}
```

**Response** (202): Accepted (processing asynchronously)

**Errors**:
- `404` - Session not found
- `401` - Unauthorized
- `400` - Invalid input

---

### Suspend Session

**Endpoint**: `POST /sessions/{id}/suspend`

Suspends a session without closing it.

**Request**:
```json
{
  "reason": "Manual pause"
}
```

**Response** (200):
```json
{
  "id": "sess_550e8400e29b41d4a716446655440000",
  "status": "suspended"
}
```

**Errors**:
- `404` - Session not found
- `409` - Session already suspended

---

### Resume Session

**Endpoint**: `POST /sessions/{id}/resume`

Resumes a suspended session.

**Response** (200):
```json
{
  "id": "sess_550e8400e29b41d4a716446655440000",
  "status": "connected"
}
```

**Errors**:
- `404` - Session not found
- `409` - Session not suspended

---

### Migrate Session

**Endpoint**: `PUT /sessions/{id}/migrate`

Migrates an active session to a different endpoint.

**Request**:
```json
{
  "target_endpoint": "mainframe-backup.example.com:3270"
}
```

**Response** (200):
```json
{
  "id": "sess_550e8400e29b41d4a716446655440000",
  "status": "migrating",
  "previous_host": "mainframe.example.com",
  "target_host": "mainframe-backup.example.com"
}
```

**Errors**:
- `404` - Session not found
- `503` - Target unavailable

---

## Endpoints

### List Endpoints

**Endpoint**: `GET /endpoints`

Lists all available connection endpoints.

**Response** (200):
```json
{
  "endpoints": [
    {
      "id": "ep_001",
      "host": "mainframe.example.com",
      "port": 3270,
      "status": "healthy",
      "active_sessions": 5,
      "last_check": 1670000000
    }
  ]
}
```

---

### Add Endpoint

**Endpoint**: `POST /endpoints`

Registers a new endpoint.

**Request**:
```json
{
  "host": "backup.example.com",
  "port": 3270,
  "name": "Backup Mainframe"
}
```

**Response** (201):
```json
{
  "id": "ep_002",
  "host": "backup.example.com",
  "port": 3270,
  "status": "pending"
}
```

---

### Check Endpoint Health

**Endpoint**: `GET /endpoints/{id}/health`

Performs a health check on an endpoint.

**Response** (200):
```json
{
  "id": "ep_001",
  "status": "healthy",
  "latency_ms": 25,
  "response_time": 1670000000
}
```

---

## Audit & Compliance

### Query Audit Logs

**Endpoint**: `GET /audit`

Retrieves audit logs with optional filtering.

**Query Parameters**:
- `event_type` - Filter by event type
- `session_id` - Filter by session ID
- `user` - Filter by user
- `since` - Timestamp filter (milliseconds since epoch)
- `limit` - Max results (default: 1000)

**Response** (200):
```json
{
  "events": [
    {
      "timestamp": 1670000000,
      "event_type": "session_created",
      "session_id": "sess_001",
      "user": "john.doe",
      "action": "connect",
      "status": "success"
    }
  ],
  "total": 150,
  "limit": 1000
}
```

---

### Get Compliance Report

**Endpoint**: `GET /compliance/report`

Generates a compliance report.

**Query Parameters**:
- `framework` - SOC2, HIPAA, or PCI-DSS
- `period` - 30, 90, or 365 days

**Response** (200):
```json
{
  "framework": "SOC2",
  "period_days": 90,
  "generated_at": 1670000000,
  "total_rules": 15,
  "violations": {
    "critical": 0,
    "warning": 2,
    "info": 5
  },
  "compliance_score": 98.5
}
```

---

## Webhooks

### Register Webhook

**Endpoint**: `POST /webhooks`

Registers a new webhook for event notifications.

**Request**:
```json
{
  "url": "https://your-app.example.com/webhooks/session-events",
  "events": ["session_created", "session_closed"],
  "secret": "whsec_abc123def456"
}
```

**Response** (201):
```json
{
  "id": "wh_550e8400e29b41d4a716446655440000",
  "url": "https://your-app.example.com/webhooks/session-events",
  "events": ["session_created", "session_closed"],
  "active": true,
  "created_at": 1670000000
}
```

---

### List Webhooks

**Endpoint**: `GET /webhooks`

Lists all registered webhooks.

**Response** (200):
```json
{
  "webhooks": [
    {
      "id": "wh_550e8400e29b41d4a716446655440000",
      "url": "https://your-app.example.com/webhooks/session-events",
      "events": ["session_created"],
      "active": true,
      "created_at": 1670000000
    }
  ]
}
```

---

### Delete Webhook

**Endpoint**: `DELETE /webhooks/{id}`

Unregisters a webhook.

**Response** (204): No content

---

## Webhook Payloads

### Session Event

```json
{
  "event_type": "session_created",
  "timestamp": 1670000000,
  "session_id": "sess_550e8400e29b41d4a716446655440000",
  "data": {
    "host": "mainframe.example.com",
    "port": 3270,
    "user": "john.doe"
  }
}
```

### Authentication Event

```json
{
  "event_type": "authentication_success",
  "timestamp": 1670000000,
  "session_id": "sess_550e8400e29b41d4a716446655440000",
  "data": {
    "user": "john.doe",
    "method": "mainframe"
  }
}
```

### Error Event

```json
{
  "event_type": "error_occurred",
  "timestamp": 1670000000,
  "session_id": "sess_550e8400e29b41d4a716446655440000",
  "data": {
    "error": "CONNECTION_LOST",
    "message": "Connection dropped after 5 minutes of inactivity"
  }
}
```

---

## Error Responses

All errors follow this format:

```json
{
  "err": "ERROR_CODE",
  "message": "Human-readable message",
  "status": 400
}
```

### Common Error Codes

| Code | Status | Description |
|------|--------|-------------|
| `INVALID_REQUEST` | 400 | Malformed request |
| `UNAUTHORIZED` | 401 | Missing/invalid authentication |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `SESSION_NOT_FOUND` | 404 | Session doesn't exist |
| `ENDPOINT_UNAVAILABLE` | 503 | Connection failed |
| `INTERNAL_ERROR` | 500 | Server error |

---

## Examples

### Create and Connect to Session (cURL)

```bash
# Create session
curl -X POST http://localhost:3270/api/v1/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "host": "mainframe.example.com",
    "port": 3270,
    "application": "CICS"
  }'

# Get response
# {"id": "sess_...", "status": "connected", ...}

# Send input
curl -X POST http://localhost:3270/api/v1/sessions/sess_.../input \
  -H "Content-Type: application/json" \
  -d '{
    "input": "SELECT OPTION ===> 5",
    "function_key": "ENTER"
  }'

# Get screen
curl http://localhost:3270/api/v1/sessions/sess_.../screen
```

### Python Client Example

```python
import requests
import json

BASE_URL = "http://localhost:3270/api/v1"

# Create session
response = requests.post(f"{BASE_URL}/sessions", json={
    "host": "mainframe.example.com",
    "port": 3270,
    "application": "CICS"
})
session = response.json()
session_id = session["id"]

# Get screen
response = requests.get(f"{BASE_URL}/sessions/{session_id}/screen")
screen = response.json()
print(screen["screen_data"]["content"])

# Send input
requests.post(f"{BASE_URL}/sessions/{session_id}/input", json={
    "input": "HELLO WORLD",
    "function_key": "ENTER"
})

# Close session
requests.delete(f"{BASE_URL}/sessions/{session_id}")
```

### JavaScript Client Example

```javascript
const BASE_URL = "http://localhost:3270/api/v1";

async function createSession() {
  const response = await fetch(`${BASE_URL}/sessions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      host: "mainframe.example.com",
      port: 3270,
      application: "CICS"
    })
  });
  return await response.json();
}

async function getScreen(sessionId) {
  const response = await fetch(
    `${BASE_URL}/sessions/${sessionId}/screen`
  );
  return await response.json();
}

async function sendInput(sessionId, input) {
  await fetch(`${BASE_URL}/sessions/${sessionId}/input`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      input: input,
      function_key: "ENTER"
    })
  });
}

// Usage
const session = await createSession();
const screen = await getScreen(session.id);
console.log(screen.screen_data.content);
await sendInput(session.id, "HELLO");
```

---

## Rate Limiting

When rate limiting is enabled, requests are limited per time window.

**Default**: 1000 requests per 60 seconds

**Response Headers**:
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1670000060
```

When limit exceeded:
```http
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1670000060
```

---

## Best Practices

1. **Connection Pooling**: Reuse sessions when possible
2. **Error Handling**: Implement exponential backoff for retries
3. **Rate Limiting**: Respect rate limit headers
4. **Timeouts**: Set reasonable timeouts on requests (30-60 seconds)
5. **Authentication**: Use bearer tokens in production
6. **HTTPS**: Always use HTTPS in production
7. **Webhooks**: Verify webhook signatures using the secret
8. **Monitoring**: Log all API calls for audit trail

---

## Version History

- **v0.9.3** (Dec 22, 2025): Initial REST API release
  - Session management (CRUD)
  - Screen capture
  - Input injection
  - Session migration
  - Endpoint management
  - Audit log querying
  - Compliance reporting
  - Webhook support
  - Rate limiting
  - Authentication support
