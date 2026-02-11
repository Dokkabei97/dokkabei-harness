---
title: Enable Audit Logging for Security Events and Access Tracking
impact: MEDIUM
impactDescription: Provides forensic trail for security incidents, compliance requirements, and access auditing
tags: security, audit, logging, compliance, forensics
---

## Enable Audit Logging for Security Events and Access Tracking

Without audit logging, there's no record of who accessed which data, failed authentication attempts, or privilege escalation events. Audit logs are essential for security incident response and compliance.

**Incorrect (no audit logging — invisible access):**

```yaml
# No audit configuration
# Cannot detect brute-force login attempts
# Cannot trace who deleted an index
# Compliance audit fails
```

**Correct (enable audit logging with appropriate filters):**

```yaml
# elasticsearch.yml
xpack.security.audit.enabled: true
xpack.security.audit.logfile.events.include:
  - access_denied
  - access_granted
  - anonymous_access_denied
  - authentication_failed
  - authentication_success
  - connection_denied
  - tampered_request
  - run_as_denied
  - run_as_granted

# Exclude noisy system events
xpack.security.audit.logfile.events.exclude:
  - system_access_granted

# Filter to specific users or indices for high-volume clusters
xpack.security.audit.logfile.events.ignore_filters:
  monitoring:
    users: ["beats_system", "apm_system", "remote_monitoring_user"]
  health_checks:
    actions: ["cluster:monitor/*"]
```

Monitor audit events:

```json
// Audit logs are written to the ES audit log file
// <ES_HOME>/logs/<cluster_name>_audit.json

// Example audit log entry:
{
  "@timestamp": "2024-01-15T10:30:00Z",
  "event.action": "access_denied",
  "user.name": "search_api_user",
  "request.name": "DeleteIndexAction",
  "indices": ["products"],
  "opaque_id": "req-12345"
}
// This shows search_api_user tried to delete the products index — denied

// For indexing audit logs into Elasticsearch (searchable audits):
// Use Filebeat to ship audit logs to a dedicated audit index
```

Key audit events to monitor:

| Event | Significance |
|-------|-------------|
| `authentication_failed` | Brute-force attempt detection |
| `access_denied` | Unauthorized access attempts |
| `authentication_success` (from unusual IP) | Compromised credentials |
| `run_as_granted` | Privilege escalation |
| `tampered_request` | Request manipulation |

Reference: [Audit logging](https://www.elastic.co/guide/en/elasticsearch/reference/current/enable-audit-logging.html)
