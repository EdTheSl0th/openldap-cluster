# openldap.cluster.client

Binds a Debian 12/13 host to the cluster with SSSD: users and groups (NSS),
login (PAM), access per hostgroup, sudo rules from LDAP and home directories
on first login.

Every client gets **its own bind account** `cn=<fqdn>,ou=hosts,…`. Its
password is derived, not stored:

```
password = base64url(HMAC-SHA256(ldap_secret_seed, "host:" + lower(fqdn)))[:40]
```

It is unique per host, identical on every run and only written to the client
(`/etc/sssd/sssd.conf`, root-only). The role creates or updates the account on
a provider (delegated, via `ldapi`) and only resets the password when a bind
with the derived one fails. Host accounts use the password policy
`cn=service` (no lockout) and may read people, groups and sudo rules – nothing
else.

## Requirements

* The LDAP servers are in the inventory (`ldap_servers_group`) – their
  addresses are taken from `ldap_node_address`, else `ansible_host`.
* The CA certificate is available on the controller (`ldap_client_ca_file`).
* `ldap_secret_seed` as for the servers.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_domain`, `ldap_suffix`, `ldap_dn_*` *(shared)* | see server role | Directory layout. |
| `ldap_secret_seed` *(shared)* | – **required** | Seed for the host password. |
| `ldap_servers_group` *(shared)* | `ldap_servers` | Group of the providers. |
| `ldap_vip` *(shared)* | `""` | Shared IP; when empty, clients use the first provider as primary. |
| `ldap_client_fqdn` | `ansible_facts.fqdn` | Name of the host account and input of the password derivation. Changing it creates a new account. |
| `ldap_client_bind_dn` | `cn=<fqdn>,{{ ldap_dn_hosts }}` | Bind DN of the host. |
| `ldap_client_uri` | `ldaps://<ldap_vip>` | Primary LDAP URI. |
| `ldap_client_backup_uris` | `ldaps://<each provider>` | Fallback URIs (SSSD `ldap_backup_uri`), used while the primary is unreachable. |
| `ldap_client_provision_host` | first provider of the group | Provider on which the host account is created (must be reachable). |
| `ldap_pki_dir` *(shared)* | `{{ inventory_dir }}/.ldap-pki` | Internal CA directory on the controller. |
| `ldap_client_ca_file` | `{{ ldap_pki_dir }}/ca.crt` | CA certificate (on the controller) installed on the client. Point it to your CA when using `ldap_tls_external`. |
| `ldap_hostgroups` *(shared with directory)* | `[]` | Hostgroup definitions; used to find the groups of this host. |
| `ldap_client_hostgroups` | computed | Hostgroups this host belongs to. Members of `access-<hostgroup>` may log in. **No hostgroup = no directory user may log in** (`access_provider = deny`). |
| `ldap_client_sudo` | `true` | Sudo rules from LDAP (SSSD sudo provider, `sudoers: files sss`). |
| `ldap_client_sudo_refresh` | `300` | Seconds until changed sudo rules reach the client (smart refresh). |
| `ldap_client_mkhomedir` | `true` | Create home directories on first login (`pam_mkhomedir`). |
| `ldap_client_cache_credentials` | `true` | Allow offline logins with cached credentials when no server is reachable. |

## What it changes on the client

| Item | Change |
|------|--------|
| Packages | `sssd-ldap`, `sssd-tools`, `libnss-sss`, `libpam-sss`, `ldap-utils`, `libsss-sudo` |
| `/etc/sssd/sssd.conf` | Domain `ldap`, TLS 1.3 with certificate validation (`ldap_tls_reqcert = demand`) |
| `/usr/local/share/ca-certificates/ldap-ca.crt` | LDAP CA, also added to the system store |
| `/etc/ldap/ldap.conf` | Defaults for `ldapsearch` & co. |
| `/etc/nsswitch.conf` | `files sss` for passwd, group, shadow, sudoers |
| PAM | `pam_mkhomedir` via `pam-auth-update` |

SSSD logs "RootDSE could not be retrieved" – expected, anonymous reads are
disabled on the servers.

## Example

```yaml
- hosts: ldap_clients
  become: true
  roles:
    - openldap.cluster.client
```
