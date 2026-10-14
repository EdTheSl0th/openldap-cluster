# Security

## Hardening measures

| Area | Measure |
|------|---------|
| Transport | TLS 1.3 only (`olcTLSProtocolMin 3.4`), AEAD cipher suites, X25519/P-256/P-384 (OpenSSL). Debian 12 (GnuTLS) and 13 (OpenSSL) are detected automatically. |
| Confidentiality | `olcSecurity ssf=128 simple_bind=128 update_ssf=128`: no bind or write without encryption. Plain `ldap://` works only after StartTLS. |
| Anonymous access | `olcDisallows bind_anon`, `olcRequires authc`, SASL `noanonymous,noplain`. Anonymous clients can only authenticate. |
| Administration | No root password (`olcRootPW`) anywhere. Full access only locally as root via `ldapi:///` + SASL EXTERNAL; people get rights through roles ([RBAC](rbac.md)). |
| Passwords | `{ARGON2}` hashes; cleartext writes are hashed by the ppolicy overlay. Nobody but the replicator can read hashes. |
| Password policy | Min. length 12, history 5, lockout after 5 failures for 15 min (people). Service accounts: min. length 32, no lockout. |
| Certificates | Internal CA (ECDSA P-384) on the controller; server keys (ECDSA P-256) are generated on the nodes and never leave them; clients and replication validate certificates (`demand`). |
| Network | Listeners only on the node address, the shared IP and `ldapi` (no wildcard). nftables: 389/636 only from `ldap_allowed_networks`, VRRP only from the peers, everything else dropped except SSH. |
| Service | Native systemd unit with sandboxing (`ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`, `PrivateDevices`, `MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`, minimal capability set, …). `systemd-analyze security slapd`: 2.5 "OK". slapd runs as `openldap`. |
| Files | TLS key `root:openldap 0640`, `cn=config` and database `openldap 0750`, backups `root 0700`, secrets on the nodes `root 0600`. |
| Logging | `olcLogLevel stats` (connections, binds, operations) to the journal. |
| Availability | Unique `uid`/`uidNumber` (overlay `unique`), size and time limits, daily backups. |

## Secrets

| Secret | Where | Handling |
|--------|-------|----------|
| `ldap_secret_seed` | inventory | **The** secret of the cluster. Store it with ansible-vault; whoever knows it can compute the replicator and every host password. |
| Internal CA key | controller, `ldap_pki_dir` | Keep private and backed up; never commit it. Losing it means re-issuing all certificates and redistributing the CA. |
| Initial user passwords | inventory (`ldap_users[].password`) | ansible-vault; only used when a user is created. |
| Hetzner API token | inventory, providers (`/etc/ldap-ha/hetzner.json`) | Provider `hetzner` only. Use a dedicated project – the token can change any alias IP in it. |
| Host bind passwords | clients, `/etc/sssd/sssd.conf` (root only) | Derived, not stored elsewhere. |

Example with vault:

```sh
ansible-vault encrypt_string "$(openssl rand -base64 48)" --name ldap_secret_seed \
  >> group_vars/all/vault.yml
```

### Rotating the seed

Changing `ldap_secret_seed` changes every derived password. Run the `server`
playbook on **all** providers, then the `client` playbook on all clients.
Between the two provider runs replication between an updated and a
not-yet-updated node fails (and recovers automatically afterwards); clients
lose access until they are updated. Plan a maintenance window.

## Using your own CA

Set `ldap_tls_external: true`, place `ca.crt`, `server.crt` and `server.key`
(`root:openldap 0640`) in `ldap_tls_dir` on every provider before the run,
and point `ldap_client_ca_file` to the CA certificate on the controller. The
server certificate needs the node's FQDN, its address and – if used – the
shared IP as subjectAltNames, because replication and clients connect by IP.

## Not covered

* Client certificate (mutual TLS) or multi-factor authentication.
* Rate limiting beyond the account lockout, protection against DoS.
* Central log shipping and monitoring – integrate the journal and e.g.
  `contextCSN` checks ([operations](operations.md#health-checks)) into your
  monitoring.
* Encryption of the database and backups at rest – use encrypted disks.
