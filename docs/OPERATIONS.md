# Operations & Troubleshooting Guide for v0.10.x

## Table of Contents
1. [Installation & Setup](#installation--setup)
2. [Configuration Best Practices](#configuration-best-practices)
3. [Monitoring Setup](#monitoring-setup)
4. [Common Issues & Solutions](#common-issues--solutions)
5. [Troubleshooting Workflows](#troubleshooting-workflows)
6. [Log Analysis](#log-analysis)

---

## Installation & Setup

### System Requirements

**Minimum**:
- 64-bit processor (x86-64 or ARM64)
- 512 MB RAM
- 50 MB disk space

**Recommended for Production**:
- 2+ cores
- 2+ GB RAM
- 100 MB disk space
- Network connectivity (LAN/WAN to mainframe)

**Supported Operating Systems**:
- Linux (Ubuntu 18.04+, CentOS 7+, Debian 10+)
- macOS (10.13+)
- BSD variants
- Docker/Kubernetes

### Installation from Binary

1. Download the latest release from GitHub:
```bash
wget https://github.com/chunghha/zig-3270/releases/download/v0.10.0/zig-3270-linux-x86_64
chmod +x zig-3270-linux-x86_64
sudo mv zig-3270-linux-x86_64 /usr/local/bin/zig-3270
```

2. Verify installation:
```bash
zig-3270 --version
```

### Installation from Source

1. Clone repository:
```bash
git clone https://github.com/chunghha/zig-3270.git
cd zig-3270
```

2. Build using Zig:
```bash
zig build -Doptimize=ReleaseSafe
```

3. Install binary:
```bash
sudo cp zig-out/bin/zig-3270 /usr/local/bin/
```

### Docker Deployment

```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y wget
RUN wget https://github.com/chunghha/zig-3270/releases/download/v0.10.0/zig-3270-linux-x86_64 \
    && chmod +x zig-3270-linux-x86_64 \
    && mv zig-3270-linux-x86_64 /usr/local/bin/zig-3270
ENTRYPOINT ["zig-3270"]
```

---

## Configuration Best Practices

### Connection Configuration

Create a profile file `~/.zig-3270/default.profile`:

```ini
[connection]
host = mainframe.example.com
port = 23
timeout_ms = 5000
retry_count = 3
retry_delay_ms = 1000

[session]
screen_size = 24x80
use_ssl = false
ssl_verify = true

[logging]
level = info
format = text
```

### Network Configuration

#### Firewall Rules

Allow outbound TN3270 connections:
```bash
# Linux (ufw)
sudo ufw allow out 23/tcp

# Linux (iptables)
sudo iptables -A OUTPUT -p tcp --dport 23 -j ACCEPT

# macOS (pfctl)
echo "pass out proto tcp from any to any port 23" | sudo pfctl -f -
```

#### TCP Tuning

Optimize for high-frequency connections:
```bash
# Linux: Increase TCP backlog
sudo sysctl -w net.core.somaxconn=4096
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=4096

# macOS: Increase open files limit
ulimit -n 8192
```

### Proxy Configuration

If connecting through a proxy:

```ini
[proxy]
enabled = true
host = proxy.example.com
port = 3128
username = proxyuser
password = proxypass
```

### TLS/SSL Configuration

For secure connections:

```ini
[tls]
enabled = true
certificate_path = /etc/ssl/certs/ca-certificates.crt
verify_hostname = true
min_version = 1.2
```

---

## Monitoring Setup

### Prometheus Integration

Export metrics for Prometheus:

```ini
[metrics]
enabled = true
format = prometheus
listen_addr = 0.0.0.0
listen_port = 9090
scrape_interval = 15s
```

Create Prometheus configuration:

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'zig-3270'
    static_configs:
      - targets: ['localhost:9090']
```

Start Prometheus:
```bash
./prometheus --config.file=prometheus.yml
```

### Grafana Dashboard

Create dashboard with key metrics:

1. **Connection Health**
   - Connected sessions
   - Failed connections
   - Connection latency (p50, p95, p99)

2. **Performance**
   - Commands/sec throughput
   - Parser latency
   - Field lookup time
   - Memory usage

3. **Errors**
   - Parse error rate
   - Connection error rate
   - Protocol violations

Example metrics query:
```
rate(zig3270_commands_total[5m])
histogram_quantile(0.95, zig3270_latency_ms)
zig3270_memory_bytes_used
```

### JSON Logging for ELK Stack

Configure JSON logging:

```ini
[logging]
format = json
output = stdout
```

Send to Elasticsearch:
```bash
zig-3270 connect mainframe.example.com:23 | \
  filebeat -c filebeat.yml -
```

Filebeat configuration:
```yaml
filebeat.inputs:
- type: stdin
  enabled: true
  json.message_key: message
  json.keys_under_root: true

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
```

---

## Common Issues & Solutions

### Connection Timeouts

**Problem**: "Connection timeout after 5000ms"

**Root Causes**:
1. Network unreachable
2. Firewall blocking
3. Mainframe endpoint down
4. Timeout too short

**Solutions**:

1. **Test network connectivity**:
```bash
ping mainframe.example.com
telnet mainframe.example.com 23
ncat -v mainframe.example.com 23
```

2. **Increase timeout**:
```ini
[connection]
timeout_ms = 10000      # Increase from 5000 to 10000
```

3. **Check firewall rules**:
```bash
sudo iptables -L -n | grep 23
sudo ufw show added
```

4. **Enable debug logging**:
```bash
export ZIG_3270_LOG_LEVEL=debug
zig-3270 connect mainframe.example.com:23
```

### High Memory Usage

**Problem**: Process consuming 500MB+ memory

**Root Causes**:
1. Large screen buffers (multiple sessions)
2. Unbounded field data accumulation
3. Log files growing unchecked
4. Allocation leaks

**Solutions**:

1. **Check session count**:
```bash
# Monitor via metrics
curl http://localhost:9090/metrics | grep zig3270_sessions_active
```

2. **Reduce buffer sizes**:
```ini
[performance]
command_buffer_size = 4096      # Default
field_data_buffer_size = 102400 # 100KB per session
```

3. **Enable memory limits**:
```ini
[limits]
max_memory_mb = 512
max_sessions = 50
max_fields_per_session = 1000
```

4. **Monitor memory growth**:
```bash
watch -n 1 'ps aux | grep zig-3270 | grep -v grep'
```

### Slow Command Execution

**Problem**: Commands take 500ms+ to execute

**Root Causes**:
1. Network latency
2. Parser overhead
3. Field lookup O(n) behavior
4. Large screen updates

**Solutions**:

1. **Profile with built-in tools**:
```bash
ZIG_3270_LOG_LEVEL=debug \
ZIG_3270_PROFILER_ENABLED=true \
  zig-3270 connect mainframe.example.com:23
```

2. **Check network latency**:
```bash
ping -c 10 mainframe.example.com | tail -1
mtr -c 20 mainframe.example.com
```

3. **Enable field cache**:
```ini
[performance]
field_cache_enabled = true
field_cache_size = 100
```

4. **Reduce screen size** (if applicable):
```ini
[session]
screen_size = 12x40  # Smaller than default 24x80
```

### Session Loss / Unexpected Disconnection

**Problem**: "Connection lost: EOF"

**Root Causes**:
1. Network interruption
2. Mainframe endpoint timeout
3. Keepalive not working
4. Resource limit exceeded on mainframe

**Solutions**:

1. **Enable keepalive**:
```ini
[connection]
keepalive_enabled = true
keepalive_interval_s = 30
```

2. **Enable auto-reconnect**:
```ini
[network]
auto_reconnect = true
reconnect_delay_ms = 1000
max_reconnect_attempts = 5
```

3. **Check logs for errors**:
```bash
zig-3270 connect mainframe.example.com:23 2>&1 | grep -i "error\|disconnect"
```

4. **Increase server-side timeouts** (mainframe admin task):
   - Ask mainframe admin to increase session idle timeout
   - Request notification of impending session termination

### Parse Errors / Protocol Violations

**Problem**: "Parse error: invalid order code 0x5f"

**Root Causes**:
1. Incompatible mainframe version
2. Network corruption
3. Protocol implementation mismatch
4. Custom host writing extensions

**Solutions**:

1. **Enable protocol snooper**:
```bash
zig-3270 snoop mainframe.example.com:23 > protocol.log
```

2. **Examine raw bytes**:
```bash
zig-3270 hex-viewer protocol.log | head -50
```

3. **Check protocol compliance**:
```bash
zig-3270 diagnose --check-protocol mainframe.example.com:23
```

4. **Update to latest version**:
```bash
git pull
zig build -Doptimize=ReleaseSafe
```

---

## Troubleshooting Workflows

### Workflow 1: Diagnose Connection Issue

```bash
#!/bin/bash
set -e

MAINFRAME=$1
PORT=${2:-23}

echo "=== Step 1: Network Reachability ==="
ping -c 3 $MAINFRAME || exit 1

echo "=== Step 2: Port Connectivity ==="
nc -zv $MAINFRAME $PORT || exit 1

echo "=== Step 3: TN3270 Protocol ==="
timeout 5 zig-3270 diagnose --protocol $MAINFRAME:$PORT || echo "Protocol check failed"

echo "=== Step 4: Connection Latency ==="
mtr -c 10 -r $MAINFRAME | grep "Min\|Avg\|Max"

echo "=== Step 5: Try Connection ==="
timeout 10 zig-3270 connect $MAINFRAME:$PORT
```

### Workflow 2: Performance Analysis

```bash
#!/bin/bash

MAINFRAME=$1
DURATION=${2:-60}

echo "=== Collecting metrics for $DURATION seconds ==="

ZIG_3270_PROFILER_ENABLED=true \
ZIG_3270_LOG_LEVEL=info \
timeout $DURATION \
  zig-3270 connect $MAINFRAME:23 2>&1 | tee profile.log &

PID=$!
sleep 1

echo "=== Monitoring system resources ==="
watch -n 1 "ps -p $PID -o %cpu,%mem,vsz,rss"

wait $PID

echo "=== Performance Summary ==="
grep "throughput\|latency\|memory" profile.log | tail -20
```

### Workflow 3: Validate Configuration

```bash
#!/bin/bash

PROFILE=${1:-~/.zig-3270/default.profile}

echo "=== Validating configuration: $PROFILE ==="

# Check file exists
if [ ! -f "$PROFILE" ]; then
    echo "ERROR: Profile not found: $PROFILE"
    exit 1
fi

# Validate required fields
for field in host port timeout_ms; do
    if ! grep -q "^$field" "$PROFILE"; then
        echo "WARNING: Missing field: $field"
    fi
done

# Test connection with values from profile
HOST=$(grep "^host" "$PROFILE" | cut -d= -f2 | tr -d ' ')
PORT=$(grep "^port" "$PROFILE" | cut -d= -f2 | tr -d ' ')
TIMEOUT=$(grep "^timeout_ms" "$PROFILE" | cut -d= -f2 | tr -d ' ')

echo "=== Testing connection ==="
echo "  Host: $HOST"
echo "  Port: $PORT"
echo "  Timeout: ${TIMEOUT}ms"

timeout $((TIMEOUT/1000 + 2)) zig-3270 connect $HOST:$PORT && echo "✓ Connection successful" || echo "✗ Connection failed"
```

---

## Log Analysis

### Log Levels

- **disabled**: No logging
- **error**: Only error messages (startup issues)
- **warn**: Errors + warnings (unusual conditions)
- **info**: Errors + warnings + key events (default)
- **debug**: All above + detailed execution flow
- **trace**: All above + per-byte protocol details

### Environment Variables

```bash
# Set global log level
export ZIG_3270_LOG_LEVEL=debug

# Set per-module log levels
export ZIG_3270_LOG_MODULES="parser:trace,executor:debug,network:info"

# Change log format
export ZIG_3270_LOG_FORMAT=json
```

### Common Log Patterns

**Connection established**:
```
INFO [network] Connected to mainframe.example.com:23 (latency: 12ms)
```

**Command execution**:
```
DEBUG [executor] Executing command: 0x7b (Erase/Write)
DEBUG [parser] Parsed 5 fields from response
DEBUG [renderer] Updated 120 characters on screen
```

**Performance metrics**:
```
INFO [metrics] Parser: 450 MB/s, 200K ops/s (10µs latency)
INFO [metrics] Executor: 280 MB/s, 95K ops/s (20µs latency)
INFO [metrics] Memory: 2.3 MB allocated, 82% reuse rate
```

**Errors**:
```
ERROR [parser] Parse error at offset 42: invalid order code 0x5f (recovery: RESYNC_TO_FRAME_BOUNDARY)
ERROR [network] Connection lost: timeout
```

### Log Analysis Tools

**Extract errors only**:
```bash
zig-3270 connect mainframe.example.com:23 2>&1 | grep -i "error"
```

**Count error types**:
```bash
zig-3270 connect mainframe.example.com:23 2>&1 | grep "ERROR" | cut -d: -f2 | sort | uniq -c
```

**Monitor in real-time**:
```bash
zig-3270 connect mainframe.example.com:23 2>&1 | grep -v "^DEBUG" | tail -f
```

**JSON log parsing** (with jq):
```bash
export ZIG_3270_LOG_FORMAT=json
zig-3270 connect mainframe.example.com:23 2>&1 | \
  jq 'select(.level=="ERROR") | {timestamp, module, message}'
```

**Performance analysis**:
```bash
ZIG_3270_LOG_LEVEL=info \
zig-3270 connect mainframe.example.com:23 2>&1 | \
  grep -E "Parser:|Executor:|Memory:" | \
  awk '{print $3, $4, $5}' > metrics.csv
```

---

## Operational Checklists

### Startup Checklist

- [ ] System has sufficient free RAM (> 512 MB)
- [ ] Network connectivity verified (ping mainframe)
- [ ] Configuration file valid and accessible
- [ ] Log directory writable
- [ ] TLS certificates installed (if using SSL)
- [ ] Firewall allows outbound port 23 (or configured port)
- [ ] Process can be started without sudo
- [ ] Monitoring/alerting configured
- [ ] Documentation accessible to operations team

### Daily Operations Checklist

- [ ] Connection metrics within baseline (< 50ms latency)
- [ ] Error rate < 0.1% (< 1 error per 1000 commands)
- [ ] Memory usage stable (< 10% growth per hour)
- [ ] No unhandled exceptions in logs
- [ ] Backups completed successfully
- [ ] Monitoring dashboard healthy

### Incident Response Checklist

When user reports issue:
1. [ ] Collect diagnostics: `zig-3270 diagnose --full > diag.log`
2. [ ] Enable debug logging: `export ZIG_3270_LOG_LEVEL=debug`
3. [ ] Reproduce issue while logging
4. [ ] Analyze logs for errors or patterns
5. [ ] Check monitoring for baseline deviations
6. [ ] Verify network connectivity
7. [ ] Review recent configuration changes
8. [ ] Consult troubleshooting workflows above
9. [ ] Document issue and solution
10. [ ] Consider monitoring improvement

---

## Support Resources

- **GitHub Issues**: https://github.com/chunghha/zig-3270/issues
- **Documentation**: See docs/ directory
- **Performance Guide**: docs/PERFORMANCE_TUNING.md
- **API Reference**: docs/API_GUIDE.md
- **Configuration**: docs/CONFIG_REFERENCE.md
