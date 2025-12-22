# zig-3270 Deployment Guide

Complete guide for deploying zig-3270 in enterprise environments with production-grade reliability and monitoring.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation](#installation)
3. [Network Configuration](#network-configuration)
4. [Logging and Monitoring](#logging-and-monitoring)
5. [Performance Tuning](#performance-tuning)
6. [Troubleshooting](#troubleshooting)
7. [Security Considerations](#security-considerations)
8. [Backup and Recovery](#backup-and-recovery)
9. [Multi-User Deployment](#multi-user-deployment)
10. [Systemd Service Configuration](#systemd-service-configuration)

---

## System Requirements

### Minimum Requirements

- **CPU**: Single core, 2+ GHz processor
- **Memory**: 512 MB RAM minimum
- **Disk**: 50 MB for installation, 100 MB+ for session logs
- **Network**: Stable internet connection with low latency preferred
- **OS**: Linux (glibc or musl), macOS, or BSD with Zig 0.13.0+

### Recommended Requirements

- **CPU**: 2+ cores for concurrent sessions
- **Memory**: 2-4 GB RAM
- **Disk**: SSD with 500 MB+ available
- **Network**: Dedicated network segment or VLAN
- **OS**: Linux with systemd (RHEL 8+, Ubuntu 20.04+, Debian 11+)

### Supported Mainframe Systems

- **CICS**: Transaction Server 5.4+
- **IMS**: 14.1+
- **TSO/ISPF**: z/OS 2.3+
- **MVS Batch**: All recent versions
- **Custom Applications**: Supporting TN3270 protocol

---

## Installation

### From Pre-Built Binaries

```bash
# Download latest release
wget https://github.com/chunghha/zig-3270/releases/download/v0.8.0/zig-3270-linux-x86_64
chmod +x zig-3270-linux-x86_64

# Install system-wide
sudo mv zig-3270-linux-x86_64 /usr/local/bin/zig-3270

# Verify installation
zig-3270 --version
```

### From Source

```bash
# Clone repository
git clone https://github.com/chunghha/zig-3270.git
cd zig-3270

# Install Zig (if not already installed)
# See: https://ziglang.org/download/

# Build release binary
zig build -Doptimize=ReleaseFast

# Install
sudo cp zig-out/bin/zig-3270 /usr/local/bin/

# Verify
zig-3270 --version
```

### Directory Structure

```
/opt/zig-3270/
├── bin/
│   └── zig-3270              # Main executable
├── etc/
│   ├── profiles.json         # Connection profiles
│   ├── keyboard.json         # Key bindings
│   └── logging.conf          # Logging configuration
├── var/
│   ├── log/                  # Application logs
│   ├── sessions/             # Session recordings
│   └── cache/                # Temporary data
└── docs/                     # Documentation
```

### Create Standard Directories

```bash
# Create directory structure
sudo mkdir -p /opt/zig-3270/{bin,etc,var/{log,sessions,cache}}

# Set permissions
sudo chown -R zig-3270:zig-3270 /opt/zig-3270
sudo chmod 755 /opt/zig-3270/{bin,etc}
sudo chmod 755 /opt/zig-3270/var/{log,sessions,cache}
```

---

## Network Configuration

### Firewall Rules

#### For Outbound Connections (Standard)

```bash
# Allow outbound Telnet (port 23) to mainframe
sudo firewall-cmd --add-rich-rule='rule family="ipv4" destination address="10.0.0.0/8" port protocol="tcp" port="23" accept' --permanent

# Or with iptables
sudo iptables -A OUTPUT -p tcp --dport 23 -d 10.0.0.0/8 -j ACCEPT
```

#### For Reverse SSH Tunnels (Recommended)

```bash
# If mainframe is on closed network, use SSH tunneling
ssh -N -L 3270:mainframe-host:23 jump-host &
# Then connect to localhost:3270
```

### Connection Pooling Configuration

Edit `/opt/zig-3270/etc/network.conf`:

```ini
[network]
# Connection pool settings
pool_size = 10
idle_timeout_ms = 30000
connection_timeout_ms = 15000

# Retry settings
max_retries = 3
retry_delay_ms = 1000
max_retry_delay_ms = 30000

# Timeout settings
read_timeout_ms = 10000
write_timeout_ms = 5000
```

### Proxy Configuration

For organizations using HTTP/HTTPS proxies:

```bash
# Set proxy environment variables
export HTTP_PROXY=http://proxy.example.com:8080
export HTTPS_PROXY=https://proxy.example.com:8443
export NO_PROXY=mainframe.internal

# Then run zig-3270
zig-3270 connect mainframe.example.com 23
```

### TLS/SSL Configuration (Optional)

For secure Telnet connections over TLS:

```bash
# Generate certificate (if using TLS)
openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -days 365 -nodes

# Configure in connection profile
zig-3270 connect --tls mainframe.example.com 992
```

---

## Logging and Monitoring

### Logging Configuration

Edit `/opt/zig-3270/etc/logging.conf`:

```ini
[logging]
# Log level: disabled, error, warn, info, debug, trace
global_level = info

# Per-module levels
protocol_level = info
parser_level = warn
network_level = info
monitor_level = info

# Log file location
log_file = /opt/zig-3270/var/log/zig-3270.log
log_format = json
log_rotation = daily
log_retention_days = 30
max_log_size_mb = 100
```

### Enable Debug Logging

```bash
# Temporary override
zig-3270 --log-level debug connect mainframe.example.com 23

# Or set environment variable
export ZIG_3270_LOG_LEVEL=debug
```

### View Logs

```bash
# Real-time log viewing
tail -f /opt/zig-3270/var/log/zig-3270.log

# Filter logs by severity
grep "ERROR" /opt/zig-3270/var/log/zig-3270.log

# JSON-formatted logs for parsing
cat /opt/zig-3270/var/log/zig-3270.log | jq '.'
```

### Monitor Connection Health

```bash
# Check connection metrics
zig-3270 diag connect mainframe.example.com 23

# Get real-time metrics
zig-3270 metrics --host mainframe.example.com --port 23

# Export metrics in Prometheus format
zig-3270 metrics --format prometheus > metrics.prom
```

### Integration with Monitoring Systems

#### Prometheus Integration

Add scrape configuration to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'zig-3270'
    static_configs:
      - targets: ['localhost:9270']
    scrape_interval: 30s
```

#### Grafana Dashboard

Export metrics to Prometheus and create dashboard:

```bash
# Get current metrics
curl http://localhost:9270/metrics

# Import dashboard JSON from docs/dashboards/zig-3270-grafana.json
```

---

## Performance Tuning

### Parser Optimization

```bash
# Enable streaming parser (large datasets)
export ZIG_3270_PARSER_MODE=streaming
export ZIG_3270_BUFFER_SIZE=65536

# Enable memory pooling
export ZIG_3270_POOL_SIZE=10
```

### Memory Management

```bash
# Set field storage allocation
export ZIG_3270_FIELD_STORAGE_CAPACITY=1000000

# Enable field cache
export ZIG_3270_FIELD_CACHE_SIZE=5000
```

### Network Performance

```bash
# Increase connection pool
zig-3270 --pool-size 50

# Set TCP buffer sizes
export ZIG_3270_TCP_SEND_BUFFER=131072
export ZIG_3270_TCP_RECV_BUFFER=131072
```

### Benchmarking

```bash
# Run performance baseline
zig-3270 benchmark --duration 60 --connections 10

# Profile memory usage
zig-3270 profile --mode memory mainframe.example.com 23

# Profile latency
zig-3270 profile --mode latency --duration 300 mainframe.example.com 23
```

---

## Troubleshooting

### Common Issues

#### Connection Timeout

**Symptom**: `Connection timeout after 15000ms`

**Solutions**:
```bash
# 1. Check network connectivity
ping mainframe.example.com

# 2. Verify firewall
telnet mainframe.example.com 23

# 3. Increase timeout
zig-3270 connect --timeout 30000 mainframe.example.com 23

# 4. Run diagnostics
zig-3270 diag connect mainframe.example.com 23
```

#### Memory Growth

**Symptom**: Memory usage continually increasing

**Solutions**:
```bash
# 1. Check session size
zig-3270 diag performance mainframe.example.com 23

# 2. Enable field cache
export ZIG_3270_FIELD_CACHE_SIZE=10000

# 3. Monitor allocation patterns
zig-3270 profile --mode memory --duration 60 mainframe.example.com 23
```

#### Slow Response Times

**Symptom**: Commands take 10+ seconds to complete

**Solutions**:
```bash
# 1. Check network latency
ping -c 10 mainframe.example.com

# 2. Verify parser efficiency
zig-3270 diag performance mainframe.example.com 23

# 3. Enable streaming parser
export ZIG_3270_PARSER_MODE=streaming

# 4. Reduce batch size
zig-3270 connect --batch-size 1 mainframe.example.com 23
```

#### Protocol Errors

**Symptom**: `Protocol parsing error: invalid command code`

**Solutions**:
```bash
# 1. Enable protocol snooper
zig-3270 connect --snoop mainframe.example.com 23

# 2. Capture protocol data
zig-3270 connect --capture protocol.bin mainframe.example.com 23

# 3. Analyze with hex viewer
zig-3270 hex-viewer protocol.bin

# 4. Check mainframe logs for corresponding errors
```

### Diagnostic Commands

```bash
# Full system diagnostics
zig-3270 diag all

# Connection diagnostics
zig-3270 diag connect mainframe.example.com 23

# Protocol compliance check
zig-3270 diag protocol

# Network configuration
zig-3270 diag network

# Performance baseline
zig-3270 diag performance mainframe.example.com 23
```

### Log Analysis

```bash
# Find recent errors
tail -100 /opt/zig-3270/var/log/zig-3270.log | grep ERROR

# Count errors by type
grep ERROR /opt/zig-3270/var/log/zig-3270.log | cut -d: -f3 | sort | uniq -c

# Timeline of events
awk '{print $1}' /opt/zig-3270/var/log/zig-3270.log | sort | uniq -c

# Export logs for analysis
awk '$0 ~ /ERROR|WARN/ {print}' /opt/zig-3270/var/log/zig-3270.log > analysis.log
```

---

## Security Considerations

### Access Control

```bash
# Restrict executable permissions
chmod 750 /usr/local/bin/zig-3270
chown root:zig-3270 /usr/local/bin/zig-3270

# Create service user
useradd -r -s /bin/false zig-3270

# Set file permissions
chown -R zig-3270:zig-3270 /opt/zig-3270
chmod 750 /opt/zig-3270/etc
chmod 700 /opt/zig-3270/var/sessions
chmod 700 /opt/zig-3270/var/log
```

### Credential Management

**Never store passwords in plaintext:**

```bash
# Use environment variables
export ZIG_3270_MAINFRAME_USER=userid
export ZIG_3270_MAINFRAME_PASS=password

# Or use credential file (restricted permissions)
echo "userid:password" > ~/.zig-3270-creds
chmod 600 ~/.zig-3270-creds
```

### Network Security

```bash
# Use VPN/SSH tunnel instead of direct connection
ssh -N -L 3270:mainframe.internal:23 ssh-gateway &

# Configure firewall to restrict source IPs
sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.0.1.100/32" port protocol="tcp" port="3270" accept' --permanent
```

### Audit Logging

```bash
# Enable session recording
zig-3270 connect --record session.log mainframe.example.com 23

# Archive recorded sessions
gzip /opt/zig-3270/var/sessions/*.log

# Retention policy
find /opt/zig-3270/var/sessions -type f -mtime +90 -delete
```

---

## Backup and Recovery

### Session Backup

```bash
# Backup current sessions
tar czf sessions-backup-$(date +%Y%m%d).tar.gz /opt/zig-3270/var/sessions/

# Backup configuration
tar czf config-backup-$(date +%Y%m%d).tar.gz /opt/zig-3270/etc/

# Schedule daily backups
crontab -e
# Add: 0 2 * * * tar czf /backups/zig-3270-$(date +\%Y\%m\%d).tar.gz /opt/zig-3270/
```

### Configuration Backup

```bash
# Export current configuration
zig-3270 config export config-backup.json

# Restore from backup
zig-3270 config import config-backup.json

# Version control for profiles
git init /opt/zig-3270/etc
git -C /opt/zig-3270/etc add profiles.json
git -C /opt/zig-3270/etc commit -m "Configuration snapshot"
```

### Recovery Procedures

```bash
# In case of corruption, restore from backup
tar xzf config-backup-20240101.tar.gz

# Restart service
sudo systemctl restart zig-3270

# Verify recovery
zig-3270 diag all
```

---

## Multi-User Deployment

### Shared Installation

```bash
# Install for all users
sudo cp /usr/local/bin/zig-3270 /usr/local/bin/
sudo chmod 755 /usr/local/bin/zig-3270

# Create shared profile directory
sudo mkdir -p /etc/zig-3270
sudo cp profiles.json /etc/zig-3270/
```

### Per-User Configuration

```bash
# Each user has personal configuration
mkdir -p ~/.config/zig-3270
cp /etc/zig-3270/profiles.json ~/.config/zig-3270/

# User-specific logs
mkdir -p ~/.local/share/zig-3270/log
```

### Environment Variables

```bash
# System-wide (/etc/profile.d/zig-3270.sh)
export ZIG_3270_CONFIG_DIR=/etc/zig-3270
export ZIG_3270_DATA_DIR=/var/lib/zig-3270
export ZIG_3270_LOG_DIR=/var/log/zig-3270

# User-specific (~/.bashrc)
export ZIG_3270_PROFILE_DIR=~/.config/zig-3270
export ZIG_3270_SESSION_DIR=~/.local/share/zig-3270/sessions
```

---

## Systemd Service Configuration

### Create Service File

Create `/etc/systemd/system/zig-3270.service`:

```ini
[Unit]
Description=zig-3270 TN3270 Terminal Emulator
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=zig-3270
Group=zig-3270
ExecStart=/usr/local/bin/zig-3270 connect mainframe.example.com 23
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=zig-3270

# Resource limits
MemoryLimit=2G
CPUQuota=80%
PrivateTmp=yes

# Security
NoNewPrivileges=true
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=/opt/zig-3270/var

[Install]
WantedBy=multi-user.target
```

### Enable and Start Service

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable zig-3270

# Start service
sudo systemctl start zig-3270

# Check status
sudo systemctl status zig-3270

# View logs
sudo journalctl -u zig-3270 -f
```

### Service Management

```bash
# Restart service
sudo systemctl restart zig-3270

# Stop service
sudo systemctl stop zig-3270

# View logs with filters
sudo journalctl -u zig-3270 -n 100
sudo journalctl -u zig-3270 --since "1 hour ago"
```

---

## Docker Deployment

### Dockerfile

```dockerfile
FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata

COPY zig-3270 /usr/local/bin/
RUN chmod +x /usr/local/bin/zig-3270

WORKDIR /opt/zig-3270
RUN mkdir -p var/{log,sessions,cache} etc

ENTRYPOINT ["/usr/local/bin/zig-3270"]
CMD ["--help"]
```

### Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  zig-3270:
    build: .
    container_name: zig-3270
    restart: unless-stopped
    environment:
      - ZIG_3270_LOG_LEVEL=info
      - ZIG_3270_MAINFRAME_HOST=mainframe.example.com
      - ZIG_3270_MAINFRAME_PORT=23
    volumes:
      - zig-3270-sessions:/opt/zig-3270/var/sessions
      - zig-3270-logs:/opt/zig-3270/var/log
    ports:
      - "3270:3270"
    networks:
      - zig-3270-net

volumes:
  zig-3270-sessions:
  zig-3270-logs:

networks:
  zig-3270-net:
    driver: bridge
```

### Build and Run

```bash
# Build container
docker-compose build

# Run container
docker-compose up -d

# View logs
docker-compose logs -f zig-3270

# Stop container
docker-compose down
```

---

## Kubernetes Deployment

### ConfigMap for Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: zig-3270-config
  namespace: default
data:
  profiles.json: |
    {
      "profiles": [
        {
          "name": "mainframe",
          "host": "mainframe.example.com",
          "port": 23
        }
      ]
    }
  logging.conf: |
    [logging]
    global_level=info
    log_format=json
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zig-3270
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: zig-3270
  template:
    metadata:
      labels:
        app: zig-3270
    spec:
      containers:
      - name: zig-3270
        image: zig-3270:v0.8.0
        ports:
        - containerPort: 3270
        env:
        - name: ZIG_3270_LOG_LEVEL
          value: "info"
        volumeMounts:
        - name: config
          mountPath: /opt/zig-3270/etc
        - name: sessions
          mountPath: /opt/zig-3270/var/sessions
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
      volumes:
      - name: config
        configMap:
          name: zig-3270-config
      - name: sessions
        emptyDir: {}
```

---

## Support and Resources

- **Documentation**: https://github.com/chunghha/zig-3270/docs
- **Issue Tracker**: https://github.com/chunghha/zig-3270/issues
- **Community Chat**: https://github.com/chunghha/zig-3270/discussions
- **Security Contact**: security@example.com

---

**Last Updated**: December 23, 2024  
**Version**: v0.8.0  
**Maintainer**: zig-3270 Development Team
