# openldap.cluster.server

Hardened OpenLDAP (slapd) provider for Debian 12 (slapd 2.5, GnuTLS) and
Debian 13 (slapd 2.6, OpenSSL), replicating with all other providers
(multi-provider). Every node can be deployed on its own.

What the role does, in order:

1. Installs slapd with Debian's default configuration disabled, a native
   sandboxed systemd unit and listeners on the node address, the shared IP and
   `ldapi` only.
2. Issues a TLS certificate from an internal CA on the controller (or uses
   your own files, `ldap_tls_external`).
3. Bootstraps `cn=config` **once** (only if it does not exist and no database
   is present). Every later change is applied online via `ldapi:///` + SASL
   EXTERNAL as root.
4. Loads schemas/modules (additively), sets global hardening, database
   settings, indexes, ACLs, limits and overlays (`syncprov`, `ppolicy`,
   `dynlist`, `unique`).
5. Configures syncrepl to every peer of `ldap_servers_group`.
6. Creates base entries and service accounts – or, on a fresh node next to a
   reachable peer, waits for the initial replication instead.
7. Firewall (nftables) and daily backups.

Related docs: [architecture](../../docs/architecture.md),
[security](../../docs/security.md), [operations](../../docs/operations.md).

## Requirements

* Target: Debian 12 or 13, host in the inventory group `ldap_servers_group`.
* Controller: `cryptography` in Ansible's Python (internal CA),
  `community.general`, `community.crypto`, `ansible.posix`.
* `ldap_secret_seed` (>= 32 characters, keep it in ansible-vault).

## Variables

Variables marked *shared* are read by several roles under the same name – set
them once in `group_vars/all` (see [variables](../../docs/variables.md)).

### Identity

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_domain` *(shared)* | `example.org` | DNS domain; the suffix is derived from it (`example.org` → `dc=example,dc=org`). |
| `ldap_suffix` *(shared)* | derived from `ldap_domain` | Base DN of the directory. Set before the first deployment; cannot be changed later. |
| `ldap_organization` | `{{ ldap_domain }}` | `o` attribute of the base entry and name of the internal CA. |
| `ldap_secret_seed` *(shared)* | – **required** | Master secret (>= 32 chars). Replicator, client host and VRRP passwords are derived from it with HMAC-SHA256. Changing it rotates all derived passwords on the next run. |

### Cluster and network

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_servers_group` *(shared)* | `ldap_servers` | Inventory group with all providers. Peers, replication and HA are derived from it. |
| `ldap_server_id` | position in the sorted group + 1 | Unique, stable `olcServerID` (1–4095). **Pin it per host** before adding servers whose names sort before existing ones, otherwise the IDs shift. The node with ID 1 may seed an empty cluster. |
| `ldap_node_address` *(shared)* | default IPv4 from facts | Address slapd listens on and peers replicate from. Set it per host when LDAP uses another network than the default route. Peers read it from the inventory (`hostvars`), falling back to `ansible_host`, so no facts of other hosts are needed. |
| `ldap_node_fqdn` | `ansible_facts.fqdn` | Common name and DNS SAN of the server certificate. |
| `ldap_vip` *(shared)* | `""` | Shared IP. Adds listeners and a certificate SAN for it (requires `net.ipv4.ip_nonlocal_bind`, set by the role). Empty: no shared IP. |
| `ldap_allowed_networks` | RFC 1918 ranges | Sources allowed to reach 389/636 in nftables. Narrow it to your LDAP client networks. |

### TLS and PKI

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_tls_external` | `false` | `true`: skip the internal CA; place `ca.crt`, `server.crt` and `server.key` (group `openldap`, 0640) in `ldap_tls_dir` yourself. |
| `ldap_pki_dir` *(shared)* | `{{ inventory_dir }}/.ldap-pki` | Directory **on the controller** for the internal CA (`ca.key`, `ca.crt`). Keep it private and backed up; never commit it. |
| `ldap_pki_ca_name` | `{{ ldap_organization }} LDAP CA` | Common name of the internal CA. |
| `ldap_tls_dir` | `/etc/ldap/tls` | Certificate directory on the node. |
| `ldap_tls_extra_sans` | `["DNS:ldap.{{ ldap_domain }}"]` | Additional subjectAltNames (`DNS:…`, `IP:…`). FQDN, inventory name, node address and shared IP are always included. |
| `ldap_tls_cert_days` | `825` | Lifetime of new server certificates. Certificates are re-issued when the requested names or the key change; for renewal before expiry see [operations](../../docs/operations.md#certificate-renewal). |
| `ldap_tls_protocol_min` | `"3.4"` | Minimum TLS version (`3.4` = TLS 1.3). |
| `ldap_tls_gnutls_priority` | `SECURE256:+SECURE128:-VERS-ALL:+VERS-TLS1.3` | Cipher setting when slapd uses GnuTLS (Debian 12). |
| `ldap_tls_openssl_ciphers` | TLS 1.3 AEAD suites | Cipher setting when slapd uses OpenSSL (Debian 13). |
| `ldap_tls_openssl_curves` | `X25519:P-256:P-384` | Key exchange groups with OpenSSL. |

The TLS library is detected on the node; only the matching setting is used.

### Hardening and limits

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_password_hash` | `{ARGON2}` | Hash for new passwords (`olcPasswordHash`). |
| `ldap_log_level` | `stats` | `olcLogLevel` (connections, binds, operations, results → journal). |
| `ldap_size_limit` | `500` | Default size limit for searches. Host accounts and the replicator are unlimited (`ldap_limits`). |
| `ldap_time_limit` | `60` | Default time limit for searches (seconds). |
| `ldap_db_max_size` | `1073741824` | Maximum size of the MDB database in bytes. |
| `ldap_firewall_enabled` | `true` | Manage nftables. **Replaces `/etc/nftables.conf`** (`flush ruleset` + `/etc/nftables.d/*.nft`); disable if you manage the firewall elsewhere. |
| `ldap_firewall_ssh_port` | `22` | SSH port allowed by the firewall. |
| `ldap_firewall_extra_rules` | `[]` | Additional nftables rules for the input chain, e.g. `["tcp dport 9100 ip saddr 10.0.0.5 accept"]`. |
| `ldap_systemd_hardening` | `true` | Sandboxing drop-in for the slapd unit (`ProtectSystem=strict`, minimal capabilities, …). |
| `ldap_ppolicy` | see below | Attributes of the default password policy `cn=default,ou=policies` (applies to people). |

Default `ldap_ppolicy` (always set the complete dictionary when overriding):

| Attribute | Value | Meaning |
|-----------|-------|---------|
| `pwdMinLength` | `12` | Minimum length |
| `pwdInHistory` | `5` | Last 5 passwords cannot be reused |
| `pwdCheckQuality` | `1` | Check quality where possible |
| `pwdLockout` / `pwdMaxFailure` | `TRUE` / `5` | Lock after 5 failed binds … |
| `pwdLockoutDuration` | `900` | … for 15 minutes |
| `pwdFailureCountInterval` | `900` | Failures older than 15 minutes are forgotten |
| `pwdMaxAge` | `0` | No forced expiry (NIST SP 800-63B) |
| `pwdAllowUserChange` / `pwdMustChange` | `TRUE` / `FALSE` | Self-service allowed, no forced change |

Service accounts (replicator, client hosts) use `cn=service`: min. length 32,
no lockout (a lockout would take clients offline), no self-change.

### Directory layout and access control

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_dn_people`, `ldap_dn_groups`, `ldap_dn_roles`, `ldap_dn_hosts`, `ldap_dn_sudoers`, `ldap_dn_system`, `ldap_dn_policies` *(shared)* | `ou=<name>,{{ ldap_suffix }}` | Containers of the directory tree. Set before the first deployment. |
| `ldap_dn_replicator` | `cn=replicator,{{ ldap_dn_system }}` | Replication account. |
| `ldap_role_admins`, `ldap_role_user_admins`, `ldap_role_auditors` *(shared)* | `ldap-admins`, `user-admins`, `auditors` | Names of the built-in administrative roles in `ou=roles` that the ACLs refer to. |
| `ldap_acl` | see [RBAC](../../docs/rbac.md#directory-permissions-acls) | Ordered `olcAccess` rules of the database (first match wins). Override the whole list to customise. |
| `ldap_limits` | replicator and hosts unlimited | `olcLimits` of the database. |
| `ldap_modules` | `back_mdb, syncprov, ppolicy, dynlist, unique, argon2` | Modules; missing ones are loaded, none are unloaded. |
| `ldap_schemas` | `cosine, inetorgperson, dyngroup, rfc2307bis, sudo` | Schemas loaded in this order; missing ones are added, existing ones never changed. `rfc2307bis` is derived from Debian's `nis` schema, `sudo` ships with the role. |
| `ldap_indexes` | objectClass, entryCSN/UUID, cn/uid, uid/gidNumber, member, mail, sudoUser/Host | `olcDbIndex` values (list replaced as a whole). |

### Operations

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_backup_dir` | `/var/backups/slapd` | Target of the daily `slapcat` dump (`*-config.ldif.gz`, `*-data.ldif.gz`). |
| `ldap_backup_keep_days` | `14` | Retention of backups. |
| `ldap_upgrade_packages` | `false` | `true`: upgrade slapd and its tools during the run. The update playbook sets it to `true`. |
| `ldap_initial_sync_timeout` | `120` | Seconds a fresh node waits for the initial replication from a reachable peer before failing (30 s for the node with ID 1, which may then seed an empty cluster). |

## Example

```yaml
- hosts: ldap_servers
  serial: 1
  become: true
  roles:
    - openldap.cluster.server
    - role: openldap.cluster.ha
      when: ldap_vip | length > 0
```

`openldap.cluster.server` (playbook) does exactly this; deploy one node with
`--limit ldap2`. The task file `verify.yml` (`include_role … tasks_from:
verify.yml`) checks ldapi, the TLS 1.3 listener and replication convergence.
