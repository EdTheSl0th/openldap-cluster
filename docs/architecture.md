# Architecture

## Overview

```
                    clients (SSSD)
          ldaps://<shared IP>  ── fallback ──>  ldaps://<each provider>
                         │
              ┌──────────┴──────────┐
              │  shared IP (VRRP)   │   openldap.cluster.ha
              └──────────┬──────────┘
         ┌───────────────┴───────────────┐
   ┌─────┴─────┐   syncrepl (ldaps)  ┌─────┴─────┐
   │  ldap1    │ <─────────────────> │  ldap2    │   openldap.cluster.server
   │ provider  │   both directions   │ provider  │
   └───────────┘                     └───────────┘
         ▲ ldapi (root, SASL EXTERNAL)
         └── openldap.cluster.directory (users, groups, roles, sudo)
```

* **Providers** (`openldap.cluster.server`): two or more equal OpenLDAP
  servers. Each accepts reads and writes and replicates with every other one.
* **Shared IP** (`openldap.cluster.ha`): one address for the clients, held by
  one healthy provider at a time.
* **Directory content** (`openldap.cluster.directory`): generated from a
  role model in Ansible variables, written to one provider.
* **Clients** (`openldap.cluster.client`): SSSD with a per-host bind account.

## Replication

* Multi-provider (`olcMultiProvider`): every provider runs a syncrepl
  consumer for every peer (`refreshAndPersist`).
* Transport: `ldaps` with certificate validation (`tls_reqcert=demand`,
  TLS 1.3), bind as `cn=replicator,ou=system` with a derived password.
* TCP keepalive (`30:3:10`) detects half-open connections after a peer
  crashed or was powered off within about a minute; reconnects are retried
  every 5 s, then every 60 s, forever.
* Peers come from the inventory group `ldap_servers` – addresses from
  `ldap_node_address` (else `ansible_host`) – so no facts of other hosts are
  needed and a single node can be deployed with `--limit`.
* Only the data (`olcDatabase={1}mdb`) is replicated. `cn=config` is managed
  per node by Ansible, so all nodes stay identical without config
  replication.

### Seeding a new cluster vs. joining an existing one

Two providers creating the same base entries independently would produce
the same DNs with different `entryUUID`s – a replication conflict. A fresh
node therefore checks whether a peer is reachable on port 636:

| Situation | Behaviour |
|-----------|-----------|
| No peer reachable | Creates base entries and service accounts itself (first node of a new cluster). |
| Peer reachable | Waits up to `ldap_initial_sync_timeout` for the data to arrive by replication. |
| Peer reachable, but empty (all nodes new) | The node with `ldap_server_id` 1 seeds after 30 s; others fail with a clear message. Deploy providers one after another (`serial: 1`) to avoid this. |

## Configuration lifecycle

1. **Bootstrap (once):** if `/etc/ldap/slapd.d/cn=config.ldif` does not
   exist, a minimal `cn=config` is loaded with `slapadd -n0`. The role refuses
   to bootstrap when a database already exists.
2. **Online configuration (every run):** schemas, modules, global settings,
   database settings, ACLs, overlays and replication are applied through
   `ldapi:///` (SASL EXTERNAL as root) with `state: exact` where possible.
   Schemas and modules are only ever added.
3. **Data:** base entries are created only if missing; passwords of people
   are set only on creation.

This is what makes re-runs and updates safe: nothing is re-initialised, and
data is never rewritten wholesale. See [operations](operations.md#updates).

## Shared IP

keepalived runs one VRRP instance per provider (unicast by default). A health
check demotes a node whose slapd stops answering; the next healthy node with
the highest priority becomes master and runs `notify-master`. `nopreempt`
keeps the IP where it is when the old master returns. How the IP reaches the
new master depends on the provider – see [platforms](platforms.md).

Measured failover in the tests: about 5 s with `vrrp` (Molecule, client
access through the shared IP), about 20–30 s with `hetzner` (mostly the API
action). SSSD additionally knows every provider as backup URI.

## Derived secrets

Only one secret has to be kept: `ldap_secret_seed`. Everything else is
derived with HMAC-SHA256 and never stored on the controller:

| Purpose string | Used for |
|----------------|----------|
| `replicator` | Replication account |
| `host:<fqdn>` | Bind account of each client |
| `vrrp` (8 chars) | keepalived authentication |

See [plugins](plugins.md) for the filters and [security](security.md#secrets)
for handling the seed.

## Directory tree

```
dc=example,dc=org
├── ou=people     inetOrgPerson + posixAccount
├── ou=groups     groupOfNames + posixGroup (rfc2307bis), incl. access-<hostgroup>
├── ou=roles      groupOfNames – role membership, referenced by ACLs
├── ou=hosts      one bind account per client (cn=<fqdn>)
├── ou=sudoers    sudoRole, generated from roles
├── ou=system     cn=replicator
└── ou=policies   cn=default (people), cn=service (service accounts)
```

Groups are `groupOfNames` **and** `posixGroup` at the same time (rfc2307bis,
derived from Debian's `nis` schema with `posixGroup` made auxiliary): ACLs
and SSSD use the same `member` DNs. `memberOf` is available dynamically
through the `dynlist` overlay.

## Files on a provider

| Path | Purpose |
|------|---------|
| `/etc/ldap/slapd.d/` | `cn=config` (managed online) |
| `/var/lib/ldap/` | MDB database |
| `/etc/ldap/tls/` | `ca.crt`, `server.crt`, `server.key` |
| `/etc/systemd/system/slapd.service` (+ `.d/hardening.conf`) | Native unit replacing Debian's init script |
| `/etc/default/slapd` | Informational copy of the listeners |
| `/etc/nftables.conf`, `/etc/nftables.d/50-ldap.nft` | Firewall |
| `/usr/local/sbin/slapd-backup`, `slapd-backup.timer` | Daily backup |
| `/var/backups/slapd/` | Backups |
| `/etc/keepalived/`, `/usr/local/libexec/ldap-ha/` | Shared IP (ha role) |
