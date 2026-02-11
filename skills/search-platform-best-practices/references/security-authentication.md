---
title: Configure Authentication with Native, LDAP, SAML, or OIDC
impact: MEDIUM-HIGH
impactDescription: Prevents unauthorized access to cluster data and management APIs
tags: security, authentication, native, ldap, saml, oidc, identity
---

## Configure Authentication with Native, LDAP, SAML, or OIDC

Without authentication, anyone with network access can read, write, and delete data. Elasticsearch supports multiple authentication realms that can be chained in priority order.

**Incorrect (security disabled — open access):**

```yaml
# elasticsearch.yml
xpack.security.enabled: false
# Anyone can access any index, modify cluster settings, delete data
```

**Correct (enable security with native realm):**

```yaml
# elasticsearch.yml
xpack.security.enabled: true
xpack.security.authc.realms.native.native1:
  order: 0
```

```bash
# Set built-in user passwords
bin/elasticsearch-setup-passwords interactive
# Sets passwords for: elastic, apm_system, kibana_system, logstash_system, beats_system, remote_monitoring_user
```

For enterprise SSO integration:

```yaml
# LDAP realm
xpack.security.authc.realms.ldap.ldap1:
  order: 1
  url: "ldaps://ldap.example.com:636"
  bind_dn: "cn=admin,dc=example,dc=com"
  user_search.base_dn: "dc=example,dc=com"
  group_search.base_dn: "dc=example,dc=com"
  ssl.certificate_authorities: ["ldap-ca.crt"]

# SAML realm (for Kibana SSO)
xpack.security.authc.realms.saml.saml1:
  order: 2
  idp.metadata.path: "saml-metadata.xml"
  idp.entity_id: "https://idp.example.com"
  sp.entity_id: "https://kibana.example.com"
  sp.acs: "https://kibana.example.com/api/security/saml/callback"

# OIDC realm (OAuth 2.0 / OpenID Connect)
xpack.security.authc.realms.oidc.oidc1:
  order: 3
  rp.client_id: "elasticsearch"
  rp.response_type: code
  rp.redirect_uri: "https://kibana.example.com/api/security/oidc/callback"
  op.issuer: "https://auth.example.com"
  op.authorization_endpoint: "https://auth.example.com/authorize"
  op.token_endpoint: "https://auth.example.com/token"
  claims.principal: sub
```

Map external users to Elasticsearch roles:

```json
PUT /_security/role_mapping/ldap_admins
{
  "roles": ["superuser"],
  "enabled": true,
  "rules": {
    "field": { "groups": "cn=es-admins,ou=groups,dc=example,dc=com" }
  }
}
```

Reference: [User authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-up-authentication.html)
