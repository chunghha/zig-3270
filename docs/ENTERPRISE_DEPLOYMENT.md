# Enterprise Deployment Guide

**Version**: 0.9.3  
**Target Audience**: DevOps, System Administrators, Enterprise Architects  
**Last Updated**: December 22, 2025

## Executive Summary

This guide covers production deployment of zig-3270 in enterprise environments with requirements for high availability, audit compliance, and multi-region support.

---

## Table of Contents

1. [Architecture](#architecture)
2. [System Requirements](#system-requirements)
3. [Deployment Models](#deployment-models)
4. [Configuration](#configuration)
5. [Kubernetes](#kubernetes-deployment)
6. [Docker](#docker-deployment)
7. [Monitoring & Alerting](#monitoring--alerting)
8. [Disaster Recovery](#disaster-recovery)
9. [Performance Tuning](#performance-tuning)
10. [Security](#security)
11. [Troubleshooting](#troubleshooting)

---

## Architecture

### High Availability Setup

```
┌──────────────────────────────────────────────────────┐
│                   Load Balancer (HA)                 │
│              (HAProxy / NGINX / CloudLB)             │
└─────────────────────────────┬────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐
│  zig-3270 #1   │  │  zig-3270 #2    │  │  zig-3270 #3    │
│  (Instance)    │  │  (Instance)     │  │  (Instance)     │
└────────┬───────┘  └────────┬────────┘  └────────┬────────┘
         │                   │                    │
         └───────────────────┼────────────────────┘
                             │
         ┌───────────────────┼────────────────────┐
         │                   │                    │
    ┌────▼──────┐      ┌────▼──────┐      ┌─────▼──────┐
    │ Mainframe │      │ Mainframe │      │ Mainframe  │
    │  Primary  │      │ Backup 1  │      │ Backup 2   │
    │(3270 Port)│      │(3270 Port)│      │(3270 Port) │
    └───────────┘      └───────────┘      └────────────┘
```

### Session Distribution

The SessionPool and LoadBalancer distribute sessions across multiple zig-3270 instances:

- **Sticky Sessions**: Sessions maintain affinity to original instance
- **Auto-Migration**: Failed sessions migrate to healthy endpoints
- **Health Checks**: Continuous monitoring of all endpoints
- **Audit Trail**: Complete logging of all operations

---

## System Requirements

### Minimum (Small Deployment)

| Component | Specification |
|-----------|---------------|
| CPU | 4 cores (2+ GHz) |
| Memory | 8 GB RAM |
| Storage | 100 GB SSD |
| Network | 1 Gbps Ethernet |
| OS | Linux 4.15+ |

### Recommended (Production)

| Component | Specification |
|-----------|---------------|
| CPU | 16+ cores (2.5+ GHz) |
| Memory | 32+ GB RAM |
| Storage | 500+ GB SSD (fast I/O) |
| Network | 10 Gbps Ethernet |
| OS | Ubuntu 20.04+ / RHEL 8+ |

### Scaling (Enterprise)

| Component | Specification |
|-----------|---------------|
| CPU | 32+ cores per instance |
| Memory | 64+ GB RAM per instance |
| Storage | 1+ TB SSD per instance |
| Network | 25 Gbps (multi-instance) |
| Load Balancer | Dedicated hardware (NetScaler/F5) |

---

## Deployment Models

### Model 1: Single Instance (Development/Testing)

```
┌─────────────────────┐
│   zig-3270 Server   │
│   (Single Instance)  │
└────────┬────────────┘
         │
    ┌────▼────┐
    │Mainframe│
    │  3270   │
    └─────────┘
```

**Suitable for**: Dev, testing, small deployments (<10 users)

**Deployment**:
```bash
# Run directly
zig build
./zig-out/bin/zig-3270-server

# Or with systemd
systemctl start zig-3270
```

---

### Model 2: Active-Passive Failover

```
┌─────────────────────┐
│   Primary Node      │
│   zig-3270 (Active) │
└────────┬────────────┘
         │
         └─── VIP (Virtual IP)
         │
┌────────▼────────────┐
│   Backup Node       │
│  zig-3270 (Passive) │
└─────────────────────┘
```

**Suitable for**: Medium deployments (10-50 users)

**Failover time**: 10-30 seconds

**Setup**:
1. Run zig-3270 on two nodes
2. Configure floating IP with Keepalived
3. Enable session persistence

---

### Model 3: Active-Active Load Balanced (Recommended)

```
┌────────────────────┐
│  Load Balancer     │
│  (Round-Robin)     │
└─────────┬──────────┘
          │
    ┌─────┼─────┐
    │     │     │
┌───▼─┐ ┌─▼───┐ ┌─▼───┐
│ #1  │ │ #2  │ │ #3  │
└─────┘ └──────┘ └──────┘
```

**Suitable for**: Production (50+ users)

**Benefits**:
- No single point of failure
- Linear scalability
- Session mobility
- Automatic failover

---

### Model 4: Multi-Region Deployment

```
┌──────────────────────────────────────┐
│         Global Load Balancer         │
│      (Geo-Routing / DNS-based)       │
└──────────────┬───────────────────────┘
               │
    ┌──────────┴──────────┐
    │                     │
┌───▼──────────────┐  ┌──▼───────────────┐
│   Region 1       │  │   Region 2       │
│  (East Coast)    │  │  (West Coast)    │
│  Load Balancer   │  │  Load Balancer   │
└────┬──┬──┬───────┘  └──┬──┬──┬─────────┘
     │  │  │            │  │  │
   3x zig-3270       3x zig-3270
```

**Suitable for**: Global enterprises

**Features**:
- Geo-distributed sessions
- Local failover per region
- Cross-region replication
- Compliance with data residency

---

## Configuration

### Environment Variables

```bash
# Server Configuration
ZIG3270_PORT=3270                    # TN3270 port
ZIG3270_API_PORT=8080                # REST API port
ZIG3270_BIND_ADDRESS=0.0.0.0          # Bind address

# Session Management
ZIG3270_MAX_SESSIONS=1000             # Max concurrent sessions
ZIG3270_SESSION_TIMEOUT=3600          # Session timeout (seconds)
ZIG3270_IDLE_TIMEOUT=600              # Idle timeout (seconds)

# Authentication
ZIG3270_AUTH_ENABLED=true             # Enable authentication
ZIG3270_AUTH_TYPE=bearer              # none, basic, bearer
ZIG3270_AUTH_TOKEN=<token>            # Bearer token

# Rate Limiting
ZIG3270_RATE_LIMIT_ENABLED=true       # Enable rate limiting
ZIG3270_RATE_LIMIT_RPS=1000           # Requests per second

# Audit & Compliance
ZIG3270_AUDIT_LOG_PATH=/var/log/zig3270/audit.log
ZIG3270_AUDIT_RETENTION_DAYS=90       # Audit log retention
ZIG3270_COMPLIANCE_FRAMEWORK=SOC2     # SOC2, HIPAA, PCI-DSS

# Load Balancing
ZIG3270_LB_STRATEGY=round_robin        # round_robin, weighted, least_conn
ZIG3270_HEALTH_CHECK_INTERVAL=30       # Seconds between checks
ZIG3270_HEALTH_CHECK_TIMEOUT=5         # Timeout per check

# TLS/SSL
ZIG3270_TLS_ENABLED=true
ZIG3270_TLS_CERT=/etc/zig3270/cert.pem
ZIG3270_TLS_KEY=/etc/zig3270/key.pem

# Logging
ZIG3270_LOG_LEVEL=info                 # debug, info, warn, error
ZIG3270_LOG_FILE=/var/log/zig3270/server.log
ZIG3270_LOG_MAX_SIZE=100M              # Rotation size
```

### Configuration File (YAML)

```yaml
# /etc/zig3270/server.yaml
server:
  port: 3270
  api_port: 8080
  bind_address: 0.0.0.0
  
sessions:
  max_sessions: 1000
  timeout_seconds: 3600
  idle_timeout_seconds: 600

authentication:
  enabled: true
  type: bearer
  token: ${AUTH_TOKEN}  # Use env var

rate_limiting:
  enabled: true
  max_rps: 1000
  
audit:
  log_path: /var/log/zig3270/audit.log
  retention_days: 90
  framework: SOC2
  
load_balancer:
  strategy: round_robin
  health_check_interval: 30
  health_check_timeout: 5
  
endpoints:
  - name: primary
    host: mainframe1.example.com
    port: 3270
    priority: 1
  - name: backup
    host: mainframe2.example.com
    port: 3270
    priority: 2

tls:
  enabled: true
  cert_path: /etc/zig3270/cert.pem
  key_path: /etc/zig3270/key.pem
  
logging:
  level: info
  file: /var/log/zig3270/server.log
  max_size_mb: 100
  retention_days: 30
```

---

## Kubernetes Deployment

### Prerequisites

- Kubernetes 1.20+
- Helm 3.5+
- Docker registry access
- Persistent storage

### Namespace and RBAC

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: zig3270

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: zig3270
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: zig3270
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: zig3270
subjects:
- kind: ServiceAccount
  name: zig3270
  namespace: zig3270

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: zig3270
  namespace: zig3270
```

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: zig3270-config
  namespace: zig3270
data:
  server.yaml: |
    server:
      port: 3270
      api_port: 8080
    sessions:
      max_sessions: 1000
      timeout_seconds: 3600
    audit:
      retention_days: 90
```

### StatefulSet Deployment

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: zig3270
  namespace: zig3270
spec:
  serviceName: zig3270
  replicas: 3
  selector:
    matchLabels:
      app: zig3270
  template:
    metadata:
      labels:
        app: zig3270
    spec:
      serviceAccountName: zig3270
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - zig3270
              topologyKey: kubernetes.io/hostname
      containers:
      - name: zig3270
        image: zig3270:0.9.3
        imagePullPolicy: IfNotPresent
        ports:
        - name: tn3270
          containerPort: 3270
          protocol: TCP
        - name: api
          containerPort: 8080
          protocol: TCP
        env:
        - name: ZIG3270_MAX_SESSIONS
          value: "1000"
        - name: ZIG3270_LOG_LEVEL
          value: "info"
        volumeMounts:
        - name: config
          mountPath: /etc/zig3270
        - name: audit-logs
          mountPath: /var/log/zig3270
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /api/v1/health
            port: api
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/v1/health
            port: api
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: zig3270-config
  volumeClaimTemplates:
  - metadata:
      name: audit-logs
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

### Service

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: zig3270-tn3270
  namespace: zig3270
spec:
  type: LoadBalancer
  selector:
    app: zig3270
  ports:
  - name: tn3270
    port: 3270
    targetPort: tn3270

---
apiVersion: v1
kind: Service
metadata:
  name: zig3270-api
  namespace: zig3270
spec:
  type: ClusterIP
  selector:
    app: zig3270
  ports:
  - name: api
    port: 8080
    targetPort: api
```

---

## Docker Deployment

### Dockerfile

```dockerfile
FROM ubuntu:20.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy zig-3270 binary
COPY zig-out/bin/zig-3270 /usr/local/bin/zig-3270

# Create user
RUN useradd -m -s /sbin/nologin zig3270

# Create directories
RUN mkdir -p /var/log/zig3270 /etc/zig3270 && \
    chown -R zig3270:zig3270 /var/log/zig3270 /etc/zig3270

# Copy config
COPY docs/server.yaml /etc/zig3270/server.yaml

EXPOSE 3270 8080

USER zig3270

ENTRYPOINT ["/usr/local/bin/zig-3270"]
CMD ["--config", "/etc/zig3270/server.yaml"]
```

### Docker Compose

```yaml
version: '3.8'

services:
  zig3270-1:
    image: zig3270:0.9.3
    container_name: zig3270-1
    ports:
      - "3271:3270"
      - "8081:8080"
    volumes:
      - ./config/server.yaml:/etc/zig3270/server.yaml
      - zig3270-logs-1:/var/log/zig3270
    environment:
      ZIG3270_MAX_SESSIONS: "1000"
      ZIG3270_LOG_LEVEL: "info"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/v1/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  zig3270-2:
    image: zig3270:0.9.3
    container_name: zig3270-2
    ports:
      - "3272:3270"
      - "8082:8080"
    volumes:
      - ./config/server.yaml:/etc/zig3270/server.yaml
      - zig3270-logs-2:/var/log/zig3270
    environment:
      ZIG3270_MAX_SESSIONS: "1000"
      ZIG3270_LOG_LEVEL: "info"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/v1/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  nginx:
    image: nginx:latest
    container_name: zig3270-lb
    ports:
      - "80:80"
      - "3270:3270"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - zig3270-1
      - zig3270-2

volumes:
  zig3270-logs-1:
  zig3270-logs-2:
```

---

## Monitoring & Alerting

### Prometheus Metrics

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'zig3270'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
```

### Key Metrics

| Metric | Description |
|--------|-------------|
| `zig3270_sessions_active` | Currently active sessions |
| `zig3270_sessions_total` | Total sessions created |
| `zig3270_api_requests_total` | Total API requests |
| `zig3270_api_request_duration_ms` | API request latency |
| `zig3270_audit_events_total` | Total audit events |
| `zig3270_memory_bytes` | Process memory usage |
| `zig3270_cpu_seconds_total` | Process CPU time |

### Alerting Rules

```yaml
groups:
  - name: zig3270
    rules:
    - alert: HighSessionCount
      expr: zig3270_sessions_active > 800
      for: 5m
      annotations:
        summary: "High active session count"

    - alert: HighAPILatency
      expr: zig3270_api_request_duration_ms > 1000
      for: 5m
      annotations:
        summary: "API latency exceeds 1 second"

    - alert: EndpointDown
      expr: up{job="zig3270"} == 0
      for: 1m
      annotations:
        summary: "zig-3270 endpoint down"

    - alert: AuditLogFull
      expr: zig3270_audit_log_usage_percent > 90
      for: 10m
      annotations:
        summary: "Audit log storage near capacity"
```

---

## Disaster Recovery

### Backup Strategy

**Daily backups** of:
- Session state
- Configuration files
- Audit logs
- User data

```bash
#!/bin/bash
# /usr/local/bin/backup-zig3270.sh

BACKUP_DIR=/backups/zig3270
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p ${BACKUP_DIR}

# Backup audit logs
tar czf ${BACKUP_DIR}/audit_${DATE}.tar.gz \
  /var/log/zig3270/audit.log*

# Backup configs
tar czf ${BACKUP_DIR}/config_${DATE}.tar.gz \
  /etc/zig3270/

# Backup session state (if persisted)
tar czf ${BACKUP_DIR}/sessions_${DATE}.tar.gz \
  /var/lib/zig3270/sessions/ 2>/dev/null || true

# Cleanup old backups (keep 30 days)
find ${BACKUP_DIR} -name "*.tar.gz" -mtime +30 -delete

echo "Backup completed: ${DATE}"
```

### Recovery Procedure

1. **Restore Configuration**
   ```bash
   tar xzf /backups/zig3270/config_latest.tar.gz -C /
   ```

2. **Restore Session State**
   ```bash
   tar xzf /backups/zig3270/sessions_latest.tar.gz -C /
   ```

3. **Verify Audit Logs**
   ```bash
   tar xzf /backups/zig3270/audit_latest.tar.gz -C /
   ```

4. **Restart Services**
   ```bash
   systemctl restart zig3270
   systemctl restart zig3270-api
   ```

---

## Performance Tuning

### Connection Pool Sizing

```
Optimal Pool Size = (Num Cores × 2) + Effective Spindle Count
```

For 16-core system with SSD:
```bash
ZIG3270_CONNECTION_POOL_SIZE=32
```

### Buffer Optimization

```yaml
buffers:
  command_buffer_pool: 1000
  field_data_buffer: 10_000_000  # 10MB
  parser_ring_buffer: 100_000
```

### Memory Tuning

```bash
# Allocator settings
ZIG3270_ALLOCATOR_TYPE=arena        # arena, general_purpose
ZIG3270_ARENA_SIZE=1_000_000_000    # 1GB

# GC settings (if applicable)
ZIG3270_GC_INTERVAL_MS=5000
ZIG3270_GC_THRESHOLD_MB=512
```

### Network Optimization

```bash
# TCP tuning
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728

# Apply: sysctl -p
```

---

## Security

### TLS/SSL Configuration

```yaml
tls:
  enabled: true
  cert_path: /etc/zig3270/certs/server.crt
  key_path: /etc/zig3270/certs/server.key
  ca_cert_path: /etc/zig3270/certs/ca.crt
  min_version: "1.2"
  cipher_suites:
    - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
    - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

### Authentication

```yaml
authentication:
  enabled: true
  type: bearer
  token: ${ZIG3270_AUTH_TOKEN}
  token_expire_seconds: 3600
  require_https: true
```

### Network Security

```bash
# Firewall rules
ufw allow from 10.0.0.0/8 to any port 3270
ufw allow from 10.0.0.0/8 to any port 8080
ufw deny from any to any port 3270
ufw deny from any to any port 8080
```

### Audit & Compliance

```yaml
audit:
  enabled: true
  log_path: /var/log/zig3270/audit.log
  retention_days: 365
  secure_delete: true
  encrypt_logs: true

compliance:
  framework: SOC2  # SOC2, HIPAA, PCI-DSS
  enforce_mfa: true
  require_https: true
  log_retention_days: 365
```

---

## Troubleshooting

### High CPU Usage

```bash
# Check process
top -p $(pgrep zig3270)

# Check load balancer distribution
curl http://localhost:8080/api/v1/endpoints

# Adjust session limits
ZIG3270_MAX_SESSIONS=500
```

### Memory Leaks

```bash
# Monitor memory growth
watch -n 1 'ps aux | grep zig3270 | grep -v grep'

# Enable detailed logging
ZIG3270_LOG_LEVEL=debug

# Check allocation patterns
curl http://localhost:8080/api/v1/metrics | grep memory
```

### Connection Failures

```bash
# Test TN3270 connectivity
nc -zv mainframe.example.com 3270

# Check firewall
iptables -L | grep 3270

# Verify configuration
grep -A5 "endpoints:" /etc/zig3270/server.yaml
```

### Session Timeouts

```bash
# Increase timeouts
ZIG3270_SESSION_TIMEOUT=7200
ZIG3270_IDLE_TIMEOUT=1800

# Verify in logs
tail -f /var/log/zig3270/audit.log | grep timeout
```

---

## Support & Resources

- **Documentation**: /docs/
- **API Reference**: /docs/REST_API.md
- **Issue Tracking**: https://github.com/chunghha/zig-3270/issues
- **Community**: See README.md for community channels

---

**Last Updated**: December 22, 2025  
**Version**: 0.9.3  
**Status**: Production Ready
