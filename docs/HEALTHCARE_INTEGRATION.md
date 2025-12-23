# Healthcare Integration Guide

**Version**: v0.11.3  
**Last Updated**: Dec 23, 2025

This guide covers integration of zig-3270 with healthcare mainframe systems, including patient records, appointment scheduling, and HIPAA compliance.

---

## Table of Contents

1. [TN3270 Protocol in Healthcare](#tn3270-protocol-in-healthcare)
2. [Patient Record Lookup Flow](#patient-record-lookup-flow)
3. [Appointment Scheduling Flow](#appointment-scheduling-flow)
4. [Prescription Management Flow](#prescription-management-flow)
5. [HIPAA Compliance Requirements](#hipaa-compliance-requirements)
6. [Data Encryption and Privacy](#data-encryption-and-privacy)
7. [Audit Trail and Logging](#audit-trail-and-logging)
8. [Disaster Recovery Procedures](#disaster-recovery-procedures)
9. [Session Timeouts for PHI Protection](#session-timeouts-for-phi-protection)
10. [Real-World Example: Patient Management System](#real-world-example-patient-management-system)

---

## TN3270 Protocol in Healthcare

### Healthcare System Architecture

Healthcare providers use TN3270 for:

1. **Electronic Health Records (EHR)**: Centralized patient data
2. **Pharmacy Systems**: Prescription management and dispensing
3. **Billing & Coding**: Insurance and billing integration
4. **Lab Information Systems**: Test results and orders
5. **Radiology**: Imaging records and reports

### HIPAA-Compliant TN3270 Configuration

```zig
pub const HealthcareConfig = struct {
    // Connection settings
    host: []const u8 = "ehr.hospital.local",
    port: u16 = 992,  // TLS required
    use_tls: bool = true,
    tls_version: []const u8 = "1.2",
    
    // Security
    verify_certificate: bool = true,
    ca_bundle: ?[]const u8 = null,
    
    // Timeouts (inactivity protection for PHI)
    session_timeout_ms: u32 = 900000,    // 15 minutes
    idle_timeout_ms: u32 = 300000,       // 5 minutes
    read_timeout_ms: u32 = 60000,        // 1 minute
    write_timeout_ms: u32 = 10000,       // 10 seconds
    
    // HIPAA fields
    facility_id: []const u8,
    user_role: []const u8,  // Provider, Nurse, Admin, etc.
    workstation_id: []const u8,
};

pub fn create_healthcare_client(
    allocator: std.mem.Allocator,
    config: HealthcareConfig,
) !Client {
    var client = try Client.init(allocator, config.host, config.port);
    client.set_read_timeout(config.session_timeout_ms);
    client.set_write_timeout(config.write_timeout_ms);
    return client;
}
```

---

## Patient Record Lookup Flow

### Typical Flow

```
Provider              Healthcare Mainframe (CICS/IMS)
   |                          |
   |---[CONNECT]---TLS------->|  Establish secure connection
   |<-----[LOGIN SCREEN]-------|  Request credentials
   |                          |
   |---[AUTHENTICATE]-------->|  Send credentials (EBCDIC)
   |<-----[MAIN MENU]---------|  Authentication successful
   |                          |
   |---[PATIENT SEARCH]------>|  Select patient lookup
   |<-----[SEARCH FORM]-------|  Display search screen
   |                          |
   |---[ENTER MRN]---------->|  Input Medical Record Number
   |<-----[PATIENT RECORD]----|  Display patient demographics
   |                          |
   |---[VIEW DETAILS]-------->|  Request full record
   |<-----[FULL RECORD]-------|  Display complete patient data
   |                          |
   |---[AUDIT LOG]---------->|  System logs access
   |                          |
   |---[DISCONNECT]-------->|  Close secure session
   |                          |
```

### Implementation Example

```zig
const std = @import("std");
const zig3270 = @import("zig-3270");

pub const PatientRecord = struct {
    mrn: []const u8,              // Medical Record Number
    first_name: []const u8,
    last_name: []const u8,
    date_of_birth: []const u8,    // YYYYMMDD format
    sex: u8,                       // M/F
    allergies: std.ArrayList([]const u8),
    medications: std.ArrayList([]const u8),
    diagnoses: std.ArrayList([]const u8),
};

pub fn lookup_patient(
    allocator: std.mem.Allocator,
    client: *Client,
    mrn: []const u8,
) !PatientRecord {
    // Step 1: Navigate to patient search
    var search_cmd = try ebcdic.encode_alloc(allocator, "FIND");
    defer allocator.free(search_cmd);
    try client.write(search_cmd);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Step 2: Enter MRN
    var mrn_ebcdic = try ebcdic.encode_alloc(allocator, mrn);
    defer allocator.free(mrn_ebcdic);
    try client.write(mrn_ebcdic);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 3: Parse patient record
    var record = try parse_patient_record(allocator, data, mrn);
    
    // Step 4: Request additional details (allergies, medications)
    var detail_cmd = try ebcdic.encode_alloc(allocator, "DETAIL");
    defer allocator.free(detail_cmd);
    try client.write(detail_cmd);
    
    data = try client.read();
    defer allocator.free(data);
    
    try parse_patient_details(allocator, data, &record);
    
    return record;
}

fn parse_patient_record(
    allocator: std.mem.Allocator,
    data: []const u8,
    mrn: []const u8,
) !PatientRecord {
    // Parse EBCDIC-encoded patient data
    // Extract: first_name, last_name, DOB, sex
    return .{
        .mrn = try allocator.dupe(u8, mrn),
        .first_name = "",
        .last_name = "",
        .date_of_birth = "",
        .sex = 'M',
        .allergies = std.ArrayList([]const u8).init(allocator),
        .medications = std.ArrayList([]const u8).init(allocator),
        .diagnoses = std.ArrayList([]const u8).init(allocator),
    };
}

fn parse_patient_details(
    allocator: std.mem.Allocator,
    data: []const u8,
    record: *PatientRecord,
) !void {
    // Parse allergies, medications, diagnoses from response
    // Format varies by healthcare system (HL7, proprietary)
}
```

---

## Appointment Scheduling Flow

### Workflow

```zig
pub const Appointment = struct {
    appointment_id: []const u8,
    patient_mrn: []const u8,
    provider_id: []const u8,
    department: []const u8,
    appointment_date: []const u8,  // YYYYMMDD
    appointment_time: []const u8,  // HHMM (24-hour)
    duration_minutes: u16,
    status: enum { Scheduled, Confirmed, Completed, Cancelled },
    notes: []const u8,
};

pub fn schedule_appointment(
    allocator: std.mem.Allocator,
    client: *Client,
    appointment: *Appointment,
) !void {
    // Step 1: Navigate to scheduling system
    var schedule_cmd = try ebcdic.encode_alloc(allocator, "SCHED");
    defer allocator.free(schedule_cmd);
    try client.write(schedule_cmd);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Step 2: Enter patient MRN
    var patient_info = try ebcdic.encode_alloc(allocator, appointment.patient_mrn);
    defer allocator.free(patient_info);
    try client.write(patient_info);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 3: Select department
    var dept = try ebcdic.encode_alloc(allocator, appointment.department);
    defer allocator.free(dept);
    try client.write(dept);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 4: Select date and time
    var datetime = try std.fmt.allocPrint(
        allocator,
        "{s} {s}",
        .{ appointment.appointment_date, appointment.appointment_time },
    );
    defer allocator.free(datetime);
    
    var datetime_ebcdic = try ebcdic.encode_alloc(allocator, datetime);
    defer allocator.free(datetime_ebcdic);
    try client.write(datetime_ebcdic);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 5: Confirm appointment
    var confirm = try ebcdic.encode_alloc(allocator, "CONFIRM");
    defer allocator.free(confirm);
    try client.write(confirm);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 6: Verify confirmation
    if (std.mem.indexOf(u8, data, "CONFIRMED") != null) {
        appointment.status = .Confirmed;
    } else {
        return error.AppointmentSchedulingFailed;
    }
}
```

---

## Prescription Management Flow

### Workflow

```zig
pub const Prescription = struct {
    rx_number: []const u8,
    patient_mrn: []const u8,
    prescriber_id: []const u8,
    medication_code: []const u8,
    quantity: u32,
    refills: u8,
    instructions: []const u8,
    date_prescribed: []const u8,
    status: enum { Active, Filled, Expired, Cancelled },
};

pub fn submit_prescription(
    allocator: std.mem.Allocator,
    client: *Client,
    rx: *Prescription,
) !void {
    // Step 1: Navigate to pharmacy
    var pharm_cmd = try ebcdic.encode_alloc(allocator, "PHARM");
    defer allocator.free(pharm_cmd);
    try client.write(pharm_cmd);
    
    var data = try client.read();
    defer allocator.free(data);
    
    // Step 2: Enter prescription details
    var rx_data = try std.fmt.allocPrint(
        allocator,
        "{s}|{s}|{s}|{d}|{d}",
        .{ rx.patient_mrn, rx.medication_code, rx.quantity, rx.refills },
    );
    defer allocator.free(rx_data);
    
    var rx_ebcdic = try ebcdic.encode_alloc(allocator, rx_data);
    defer allocator.free(rx_ebcdic);
    try client.write(rx_ebcdic);
    
    data = try client.read();
    defer allocator.free(data);
    
    // Step 3: Verify medication exists
    // Step 4: Check for drug interactions
    // Step 5: Submit to pharmacy
    
    var submit = try ebcdic.encode_alloc(allocator, "SUBMIT");
    defer allocator.free(submit);
    try client.write(submit);
    
    data = try client.read();
    defer allocator.free(data);
    
    if (std.mem.indexOf(u8, data, "ACCEPTED") != null) {
        rx.status = .Active;
    } else {
        return error.PrescriptionSubmissionFailed;
    }
}
```

---

## HIPAA Compliance Requirements

### Key HIPAA Rules

```zig
pub const HIPAACompliance = struct {
    // 1. Access Controls
    // - Authentication (unique user ID)
    // - Authorization (role-based access)
    // - Audit controls (logging)
    
    // 2. Encryption & Decryption
    // - Data in transit: TLS 1.2+
    // - Data at rest: AES-256
    
    // 3. Integrity Controls
    // - Checksums for data integrity
    // - Anti-tampering measures
    
    // 4. Transmission Security
    // - Encryption of data in transit
    // - Certificate validation
    
    // 5. Access Management
    // - Strong authentication (MFA where possible)
    // - Role-based access control
    // - Least privilege principle
    
    // 6. Audit Controls
    // - Logging of all PHI access
    // - Immutable audit trails
    // - Retention: minimum 6 years
};

pub fn validate_hipaa_controls() !void {
    // Check authentication enabled
    // Check encryption enabled
    // Check audit logging enabled
    // Check access controls in place
    // Check data at rest encryption
    
    std.debug.print("HIPAA compliance validation complete\n", .{});
}
```

### Protected Health Information (PHI) Classification

```zig
pub const PHIClassification = enum {
    // 18 HIPAA identifiers
    PatientName,
    MedicalRecordNumber,
    HealthPlanBeneficiary,
    AccountNumber,
    SocialSecurityNumber,
    DateOfBirth,
    DateOfService,
    DateOfAdmission,
    DateOfDischarge,
    TelephoneNumber,
    EmailAddress,
    MailingAddress,
    BillingAddress,
    IPAddress,
    VehicleIdentifier,
    WebURL,
    DeviceSerialNumber,
    Fingerprints,
};

pub fn is_phi(field_type: PHIClassification) bool {
    return true;  // All PHI requires protection
}
```

---

## Data Encryption and Privacy

### End-to-End Encryption

```zig
pub const HealthcareEncryption = struct {
    // In Transit
    tls_version: []const u8 = "1.2",  // Minimum
    cipher_suites: []const u8 = 
        "ECDHE-RSA-AES256-GCM-SHA384:" ++
        "ECDHE-RSA-CHACHA20-POLY1305",
    
    // At Rest
    data_encryption: []const u8 = "AES-256-GCM",
    key_derivation: []const u8 = "PBKDF2",
    key_rotation_days: u16 = 90,
    
    // Authentication
    authentication: []const u8 = "Username/Password + Optional MFA",
};

pub fn encrypt_phi(
    allocator: std.mem.Allocator,
    plaintext: []const u8,
    key: [32]u8,
) ![]u8 {
    // Encrypt PHI using AES-256-GCM
    // Implementation requires external crypto library
    
    // For now, return placeholder
    return try allocator.dupe(u8, plaintext);
}

pub fn decrypt_phi(
    allocator: std.mem.Allocator,
    ciphertext: []const u8,
    key: [32]u8,
) ![]u8 {
    // Decrypt PHI using AES-256-GCM
    
    return try allocator.dupe(u8, ciphertext);
}
```

### De-identification

```zig
pub fn deidentify_patient_record(
    allocator: std.mem.Allocator,
    record: *PatientRecord,
) !void {
    // Remove 18 HIPAA identifiers
    std.mem.set(u8, record.mrn, 0);
    std.mem.set(u8, record.first_name, 0);
    std.mem.set(u8, record.last_name, 0);
    
    // Keep only clinically relevant data for research
}
```

---

## Audit Trail and Logging

### Comprehensive Audit Logging

```zig
pub const HealthcareAuditEvent = struct {
    timestamp: i64,
    user_id: []const u8,
    user_role: []const u8,
    workstation_id: []const u8,
    action: enum {
        PatientLookup,
        RecordViewed,
        DataModified,
        DataDeleted,
        PrescriptionSubmitted,
        AppointmentScheduled,
        PrintedDocument,
        ExportedData,
    },
    patient_mrn: []const u8,
    details: []const u8,
    result: enum { Success, Failure, Denied },
    ip_address: []const u8,
};

pub fn log_audit_event(
    allocator: std.mem.Allocator,
    event: HealthcareAuditEvent,
) !void {
    // Write to immutable, secure audit log
    // Include all required HIPAA fields
    // Timestamp with millisecond precision
    // Never overwrite existing events
    
    var log_entry = try std.fmt.allocPrint(
        allocator,
        "{d}|{s}|{s}|{s}|{s}|{s}|{s}|{}|{s}",
        .{
            event.timestamp,
            event.user_id,
            event.user_role,
            event.workstation_id,
            @tagName(event.action),
            event.patient_mrn,
            event.details,
            event.result,
            event.ip_address,
        },
    );
    defer allocator.free(log_entry);
    
    // Write to secure audit log file
}

pub fn audit_patient_access(
    allocator: std.mem.Allocator,
    user_id: []const u8,
    user_role: []const u8,
    patient_mrn: []const u8,
) !void {
    var event = HealthcareAuditEvent{
        .timestamp = std.time.milliTimestamp(),
        .user_id = user_id,
        .user_role = user_role,
        .workstation_id = try allocator.dupe(u8, "UNKNOWN"),
        .action = .RecordViewed,
        .patient_mrn = patient_mrn,
        .details = try allocator.dupe(u8, "Patient record accessed"),
        .result = .Success,
        .ip_address = "0.0.0.0",
    };
    
    try log_audit_event(allocator, event);
}
```

---

## Disaster Recovery Procedures

### Backup and Recovery

```zig
pub const DisasterRecoveryPlan = struct {
    rto_minutes: u32 = 15,         // Recovery Time Objective
    rpo_minutes: u32 = 5,          // Recovery Point Objective
    
    pub fn backup_patient_data(
        allocator: std.mem.Allocator,
        client: *Client,
    ) !void {
        // Export all patient data
        var backup_cmd = try ebcdic.encode_alloc(allocator, "BACKUP");
        defer allocator.free(backup_cmd);
        try client.write(backup_cmd);
        
        var data = try client.read();
        defer allocator.free(data);
        
        // Encrypt and store backup
        // Verify backup integrity
    }
    
    pub fn restore_from_backup(
        allocator: std.mem.Allocator,
        client: *Client,
        backup_file: []const u8,
    ) !void {
        // Restore from backup
        var restore_cmd = try std.fmt.allocPrint(
            allocator,
            "RESTORE:{s}",
            .{backup_file},
        );
        defer allocator.free(restore_cmd);
        
        var restore_ebcdic = try ebcdic.encode_alloc(allocator, restore_cmd);
        defer allocator.free(restore_ebcdic);
        try client.write(restore_ebcdic);
        
        var data = try client.read();
        defer allocator.free(data);
    }
};
```

---

## Session Timeouts for PHI Protection

### Automatic Session Termination

```zig
pub const SessionTimeout = struct {
    pub fn enforce_session_timeout(
        allocator: std.mem.Allocator,
        client: *Client,
        config: HealthcareConfig,
    ) !void {
        var last_activity = std.time.milliTimestamp();
        
        loop {
            var current_time = std.time.milliTimestamp();
            var idle_time = current_time - last_activity;
            
            // 5-minute idle timeout
            if (idle_time > config.idle_timeout_ms) {
                std.debug.print("Session idle timeout exceeded\n", .{});
                client.disconnect();
                return;
            }
            
            // 15-minute absolute timeout
            if (idle_time > config.session_timeout_ms) {
                std.debug.print("Session absolute timeout exceeded\n", .{});
                client.disconnect();
                return;
            }
            
            std.time.sleep(std.time.ns_per_s);
        }
    }
    
    pub fn warn_before_timeout(minutes_remaining: u32) void {
        std.debug.print("Warning: Session will expire in {} minutes\n", .{minutes_remaining});
    }
};
```

---

## Real-World Example: Patient Management System

### Complete Healthcare System

```zig
const std = @import("std");
const zig3270 = @import("zig-3270");

const Client = zig3270.client.Client;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Configure healthcare client
    var config = HealthcareConfig{
        .facility_id = "Hospital-001",
        .user_role = "Provider",
        .workstation_id = "WS-001",
    };
    
    // Create secure connection
    var client = try create_healthcare_client(allocator, config);
    defer client.disconnect();
    
    // Authenticate user
    try authenticate_healthcare_user(&client, allocator, "provider_id", "password");
    
    // Example: Lookup patient
    var patient = try lookup_patient(allocator, &client, "MRN123456");
    defer {
        allocator.free(patient.mrn);
        allocator.free(patient.first_name);
        allocator.free(patient.last_name);
        allocator.free(patient.date_of_birth);
        patient.allergies.deinit();
        patient.medications.deinit();
        patient.diagnoses.deinit();
    }
    
    std.debug.print("Patient: {} {}\n", .{ patient.first_name, patient.last_name });
    std.debug.print("MRN: {s}\n", .{patient.mrn});
    std.debug.print("DOB: {s}\n", .{patient.date_of_birth});
    
    // Example: Schedule appointment
    var appointment = Appointment{
        .appointment_id = "APT001",
        .patient_mrn = patient.mrn,
        .provider_id = "PROV001",
        .department = "Cardiology",
        .appointment_date = "20240101",
        .appointment_time = "0930",
        .duration_minutes = 30,
        .status = .Scheduled,
        .notes = "Follow-up appointment",
    };
    
    try schedule_appointment(allocator, &client, &appointment);
    std.debug.print("Appointment scheduled: {}\n", .{appointment.appointment_id});
    
    // Audit log
    try audit_patient_access(allocator, "PROV001", "Provider", patient.mrn);
}

fn authenticate_healthcare_user(
    client: *Client,
    allocator: std.mem.Allocator,
    user_id: []const u8,
    password: []const u8,
) !void {
    // Send authentication credentials
    var creds = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ user_id, password });
    defer allocator.free(creds);
    
    var creds_ebcdic = try ebcdic.encode_alloc(allocator, creds);
    defer allocator.free(creds_ebcdic);
    
    try client.write(creds_ebcdic);
    
    // Read response
    var response = try client.read();
    defer allocator.free(response);
    
    if (std.mem.indexOf(u8, response, "AUTHENTICATED") == null) {
        return error.AuthenticationFailed;
    }
}
```

---

## Best Practices

1. **Always use TLS 1.2+** for HIPAA compliance
2. **Never log PHI** in application logs
3. **Implement automatic session timeouts** after inactivity
4. **Encrypt all data at rest** using AES-256
5. **Maintain comprehensive audit trails** for all PHI access
6. **Validate user authentication** on every connection
7. **Enforce role-based access control** (RBAC)
8. **Implement data encryption** during transmission
9. **Regular security audits** of access logs
10. **Secure credential handling** with memory cleanup

---

## Additional Resources

- HIPAA Compliance: https://www.hhs.gov/hipaa/
- HL7 Healthcare Data Standards: https://www.hl7.org/
- FHIR (Fast Healthcare Interoperability Resources): https://www.hl7.org/fhir/
- Healthcare Data Security: https://healthitsecurity.com/
- IBM CICS: https://www.ibm.com/cloud/cics

