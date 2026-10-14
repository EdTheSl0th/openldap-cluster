# openldap.cluster

[![CI](https://github.com/EdTheSl0th/openldap-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/EdTheSl0th/openldap-cluster/actions/workflows/ci.yml)
[![License: GPL v3+](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)

Highly available, hardened OpenLDAP (slapd) for Debian 12 (slapd 2.5, GnuTLS)
and Debian 13 (slapd 2.6, OpenSSL), with a role-based access model and SSSD
clients. Platform-agnostic: plain Debian VMs on Proxmox, VMware, bare metal or
any cloud; the only platform-specific part is an optional shared-IP provider.

| Role | Purpose |
|------|---------|
| `openldap.cluster.server` | slapd provider: bootstrap, TLS, cn=config, ACLs, overlays, multi-provider replication, firewall, backups |
| `openldap.cluster.ha` | Shared IP via keepalived (VRRP), optional cloud provider (Hetzner) |
| `openldap.cluster.directory` | Users, posix groups, roles, host access, sudo rules |
| `openldap.cluster.client` | SSSD client with its own deterministic bind account |

| Playbook | |
|----------|---|
| `openldap.cluster.server` | Providers one at a time (`--limit ldap2` deploys a single node) |
| `openldap.cluster.directory` | Directory content (written to one provider, replicated) |
| `openldap.cluster.client` | Clients |
| `openldap.cluster.update` | Rolling update: backup → upgrade/reconfigure → verify, shared-IP holder last |
| `openldap.cluster.backup` | Ad-hoc `slapcat` dump of config and data |

## Installation

```sh
ansible-galaxy collection install git+https://github.com/EdTheSl0th/openldap-cluster.git
```

or in `requirements.yml`:

```yaml
collections:
  - name: https://github.com/EdTheSl0th/openldap-cluster.git
    type: git
    version: main
```

Requirements: ansible-core >= 2.16 on the controller with `cryptography`
(internal CA); `community.general`, `community.crypto` and `ansible.posix`
are installed as dependencies. Targets: Debian 12 or 13.

## Quick start

```sh
ansible-playbook openldap.cluster.server      # providers, one at a time
ansible-playbook openldap.cluster.directory   # users, groups, roles, sudo
ansible-playbook openldap.cluster.client      # SSSD clients
ansible-playbook openldap.cluster.update      # later: rolling update
```

See [Inventory](#inventory-example-proxmox-vms-on-one-vlan) for the minimal
configuration and the role defaults (`roles/*/defaults/main.yml`) for all
variables.

## Design

**Replication.** Every provider pulls from every other provider
(`syncrepl refreshAndPersist` over `ldaps`, certificate verified, dedicated
`cn=replicator` account, `olcMultiProvider`). Peers come from the inventory
group `ldap_servers`, so a node can be (re)deployed alone. A fresh node never
creates base entries while a peer is reachable – it waits for the initial
refresh, which avoids duplicate DNs with different entryUUIDs.

**Shared IP.** keepalived elects a master (unicast VRRP by default, so no
multicast is needed). The health check (`check-slapd`) demotes a node whose
slapd stops answering; `nopreempt` prevents flapping when the old master
returns. Clients also get the single nodes as `ldap_backup_uri`. How the IP
reaches the new master is chosen with `ldap_ha_provider`:

| Provider | Platforms | Mechanism |
|----------|-----------|-----------|
| `vrrp` (default) | Proxmox (bridge/VLAN), VMware, KVM/libvirt, bare metal – any layer-2 network | IP added on the master's interface, gratuitous ARP |
| `hetzner` | Hetzner Cloud private networks (routed, no ARP between servers) | additionally moves an alias IP via the Hetzner API |

Other platforms (e.g. clouds with movable IPs) can hook in with
`ldap_ha_notify_master: ["/usr/local/bin/move-my-ip"]`; the commands run as
root on every master transition.

**Roles and permissions.** Users get *roles*; roles bundle

* posix groups (`groups`),
* login permission on *hostgroups* (`host_access` → group `access-<hostgroup>`,
  enforced by SSSD `access_provider = simple`),
* sudo rules (`sudoRole` entries, scoped to hostgroups),
* directory permissions via the built-in roles `ldap-admins` (write all),
  `user-admins` (people/groups, password resets) and `auditors` (read all but
  passwords) referenced by the ACLs.

The filter `openldap.cluster.rbac_expand` resolves the model; roles are also stored
in `ou=roles` (members + `seeAlso` to the granted groups) for traceability.

```
dc=…
├── ou=people     inetOrgPerson + posixAccount
├── ou=groups     groupOfNames + posixGroup (rfc2307bis), incl. access-<hostgroup>
├── ou=roles      groupOfNames – role membership, referenced by ACLs
├── ou=hosts      one bind account per client (cn=<fqdn>)
├── ou=sudoers    sudoRole, generated from roles
├── ou=system     cn=replicator
└── ou=policies   cn=default (people), cn=service (no lockout)
```

**Client passwords.** `HMAC-SHA256(ldap_secret_seed, "host:<fqdn>")`,
base64url: unique per host, reproducible on every run, nothing to store but
the seed. The client role creates/updates `cn=<fqdn>,ou=hosts` itself and only
rewrites the password when a bind with the derived one fails. The same scheme
derives the replicator and VRRP secrets.

**Hardening.**

* TLS 1.3 only (`olcTLSProtocolMin 3.4`, AEAD suites; X25519/P-256/P-384 on
  OpenSSL), ECDSA P-256 server keys, internal CA whose key stays on the
  controller; node keys never leave the nodes.
* `olcSecurity ssf=128 simple_bind=128 update_ssf=128` – no plaintext binds,
  StartTLS or ldaps required; `olcDisallows bind_anon`, `olcRequires authc`,
  no anonymous SASL.
* No root password anywhere: administration via `ldapi:///` + SASL EXTERNAL
  as root, people via role ACLs.
* `{ARGON2}` password hashing (cleartext writes are hashed by ppolicy),
  password policy: min. length 12, history 5, lockout after 5 failures.
* Listeners bound to the private address, the shared IP and `ldapi` only;
  nftables allows 389/636 only from `ldap_allowed_networks`.
* Native systemd unit with sandboxing (`systemd-analyze security`: 2.5 "OK"),
  minimal capability set.
* Daily `slapcat` backups (`/var/backups/slapd`, 14 days).

**Updates without data loss.** cn=config is bootstrapped exactly once (only
when it does not exist, refusing to run over existing data); afterwards every
change is applied online through `ldapi` (`ldap_attrs` with `state: exact`),
schemas and modules only additively. User passwords are set only on creation,
so self-service changes survive. `openldap.cluster.update` takes a backup, updates
one node at a time (shared-IP holder last) and waits until both nodes report
the same `contextCSN` before continuing.

## Inventory (example: Proxmox VMs on one VLAN)

```yaml
# inventory/hosts.yml
all:
  children:
    ldap_servers:
      hosts:
        ldap1: { ansible_host: 192.168.50.11 }
        ldap2: { ansible_host: 192.168.50.12 }
    ldap_clients:
      hosts:
        app1: { ansible_host: 192.168.50.21 }
```

```yaml
# inventory/group_vars/all.yml
ldap_domain: example.org
ldap_secret_seed: "{{ vault_ldap_secret_seed }}"   # >= 32 chars
ldap_vip: 192.168.50.10                             # free IP in the same VLAN
ldap_allowed_networks: [192.168.50.0/24]
ldap_pki_dir: "{{ inventory_dir }}/.ldap-pki"
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `ldap_node_address` | default IPv4 (facts) | listener / replication address; set per host when LDAP runs on a separate network. Peers use `ldap_node_address`, else `ansible_host` (no facts needed, so single nodes can be deployed) |
| `ldap_node_fqdn`, `ldap_client_fqdn` | `ansible_facts.fqdn` | certificate name / host account name |
| `ldap_vip` | – | shared IP (empty = no HA role, clients use the nodes directly) |
| `ldap_ha_provider` | `vrrp` | see above; `hetzner` needs `ldap_ha_hetzner_token`, `ldap_ha_hetzner_network_id` and per host `ldap_ha_hetzner_server_id` |
| `ldap_allowed_networks` | RFC 1918 | sources allowed to reach 389/636 |

A complete RBAC example (groups, hostgroups, roles, users) is in
[`tests/hetzner/inventory/group_vars/all.yml`](tests/hetzner/inventory/group_vars/all.yml).

## Notes

* `nftables.conf` is replaced (`flush ruleset` + `/etc/nftables.d/*.nft`);
  set `ldap_firewall_enabled: false` to manage the firewall yourself.
* Provider `hetzner`: the token on the providers can change alias IPs of the
  whole project – use a dedicated project in production.
* Provider `vrrp` needs the VIP in the same layer-2 segment as the nodes and
  clients (or routed to it), and the hypervisor must not filter gratuitous
  ARP / foreign IPs (Proxmox: IP filter of the VM firewall off or VIP
  whitelisted).
* SSSD logs "RootDSE could not be retrieved": intended, anonymous reads are
  disabled. New sudo rules reach clients within `ldap_client_sudo_refresh`
  (300 s).

## Development and tests

| | |
|---|---|
| `make lint` | ansible-lint, production profile |
| `make units` | unit tests of the filter plugins (`PYTHON=` with pytest) |
| `make build` | build the collection artifact |
| CI | ansible-lint, `ansible-test sanity` and `units` for ansible-core 2.19–2.21, build |
| [`tests/hetzner/`](tests/hetzner/README.md) | end-to-end tests on real VMs (Debian 12 and 13): replication, client login, RBAC, hardening, failover, rolling update |

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
