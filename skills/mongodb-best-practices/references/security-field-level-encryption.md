---
title: Use Client-Side Field Level Encryption for Sensitive Data
impact: MEDIUM-HIGH
impactDescription: Encrypts sensitive fields before they reach the server
tags: csfle, field-level-encryption, queryable-encryption, pii, security
---

## Use Client-Side Field Level Encryption for Sensitive Data

Client-Side Field Level Encryption (CSFLE) encrypts sensitive fields in the driver before sending to the server. Even database administrators cannot read encrypted data.

**Incorrect (sensitive data stored in plaintext):**

```javascript
// PII stored as plaintext — visible to DBAs, backup readers, log systems
db.patients.insertOne({
  name: "Kim Minsu",
  ssn: "900101-1234567",        // plaintext SSN!
  diagnosis: "Type 2 Diabetes",  // plaintext medical data!
  insuranceId: "INS-12345"
});
```

**Correct (CSFLE encrypts sensitive fields client-side):**

```javascript
// Configure auto-encryption in the driver
const secureClient = new MongoClient(uri, {
  autoEncryption: {
    keyVaultNamespace: "encryption.__keyVault",
    kmsProviders: {
      aws: { accessKeyId: process.env.AWS_KEY, secretAccessKey: process.env.AWS_SECRET }
    },
    schemaMap: {
      "myApp.patients": {
        bsonType: "object",
        encryptMetadata: { keyId: [dataKeyId] },
        properties: {
          ssn: {
            encrypt: {
              bsonType: "string",
              algorithm: "AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic"
              // Deterministic: allows equality queries on encrypted field
            }
          },
          diagnosis: {
            encrypt: {
              bsonType: "string",
              algorithm: "AEAD_AES_256_CBC_HMAC_SHA_512-Random"
              // Random: more secure but no querying
            }
          }
        }
      }
    }
  }
});

// Usage is transparent — driver encrypts/decrypts automatically
await secureClient.db("myApp").collection("patients").insertOne({
  name: "Kim Minsu",
  ssn: "900101-1234567",        // encrypted before reaching server
  diagnosis: "Type 2 Diabetes"  // encrypted before reaching server
});
```

For MongoDB 7.0+, use Queryable Encryption for range queries on encrypted fields.

Reference: [Client-Side Field Level Encryption](https://www.mongodb.com/docs/manual/core/csfle/)
