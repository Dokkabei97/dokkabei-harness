---
title: Enable TLS Encryption for Both Transport and HTTP Layers
impact: MEDIUM-HIGH
impactDescription: Prevents data interception and unauthorized cluster access in transit
tags: security, tls, ssl, encryption, transport, http
---

## Enable TLS Encryption for Both Transport and HTTP Layers

Without TLS, all data between nodes (transport layer) and between clients and nodes (HTTP layer) travels in plaintext. Anyone with network access can intercept queries, documents, and credentials.

**Incorrect (no TLS — plaintext communication):**

```yaml
# elasticsearch.yml — no TLS configured
# All inter-node communication is plaintext
# HTTP API is accessible without encryption
# Credentials sent in plaintext Authorization headers
```

**Correct (TLS on both transport and HTTP):**

```yaml
# elasticsearch.yml

# Transport layer TLS (node-to-node communication)
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: elastic-certificates.p12

# HTTP layer TLS (client-to-node communication)
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: http.p12
```

Generate certificates using `elasticsearch-certutil`:

```bash
# Generate CA
bin/elasticsearch-certutil ca --out elastic-stack-ca.p12

# Generate node certificates signed by the CA
bin/elasticsearch-certutil cert --ca elastic-stack-ca.p12 --out elastic-certificates.p12

# Generate HTTP certificate (can include SANs for load balancers)
bin/elasticsearch-certutil http
```

Verify TLS is working:

```json
// HTTPS connection required
GET https://localhost:9200/_cluster/health

// Check SSL certificate info
GET /_ssl/certificates
```

Reference: [Encrypt internode communications](https://www.elastic.co/guide/en/elasticsearch/reference/current/configuring-tls.html)
