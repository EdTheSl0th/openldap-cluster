# openldap.cluster

[![CI](https://github.com/EdTheSl0th/openldap-cluster/actions/workflows/ci.yml/badge.svg)](https://github.com/EdTheSl0th/openldap-cluster/actions/workflows/ci.yml)
[![License: GPL v3+](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)

Ansible collection for a highly available, hardened OpenLDAP (slapd) cluster
on Debian 12 and 13, with role-based access control and SSSD clients.
Platform-agnostic: plain Debian VMs on Proxmox, VMware, bare metal or any
cloud.

* **Multi-provider replication** – every node reads and writes; nodes can be
  deployed one at a time.
* **Shared IP with automatic failover** – keepalived/VRRP, optional cloud
  provider (Hetzner) or own hooks.
* **Role-based access** – roles grant unix groups, login per hostgroup, sudo
  rules and rights in the directory.
* **Client binding** – SSSD with a unique, deterministic bind password per
  host; nothing to store but one seed.
* **Hardened** – TLS 1.3 only, no anonymous or plaintext access, no root
  password, Argon2, password policy, firewall, sandboxed service.
* **Updates without data loss** – one-time bootstrap, online configuration,
  rolling update playbook with replication checks.

## Contents

| Role | Purpose |
|------|---------|
| [`server`](roles/server/README.md) | OpenLDAP provider: TLS, configuration, ACLs, replication, firewall, backups |
| [`ha`](roles/ha/README.md) | Shared IP (keepalived), providers `vrrp` and `hetzner` |
| [`directory`](roles/directory/README.md) | Users, groups, roles, host access, sudo rules |
| [`client`](roles/client/README.md) | SSSD client with its own bind account |

| Playbook | Purpose |
|----------|---------|
| `openldap.cluster.server` | Providers one at a time (`--limit ldap2` deploys a single node) |
| `openldap.cluster.directory` | Directory content (written to one provider, replicated) |
| `openldap.cluster.client` | Clients |
| `openldap.cluster.update` | Rolling update: backup → upgrade/reconfigure → verify; shared-IP holder last |
| `openldap.cluster.backup` | Ad-hoc dump of configuration and data |

Filter plugins: `derive_password`, `host_password`, `rbac_expand`,
`host_hostgroups`, `suffix_from_domain` – see [plugins](docs/plugins.md).

## Requirements

* Controller: ansible-core >= 2.16 with `cryptography` in Ansible's Python
  (internal CA). `community.general`, `community.crypto` and `ansible.posix`
  are installed as dependencies.
* Targets: Debian 12 or 13, SSH and sudo. Two or more providers for HA.

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

## Quick start

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
ldap_secret_seed: "{{ vault_ldap_secret_seed }}"   # >= 32 characters, ansible-vault
ldap_vip: 192.168.50.10                             # free IP in the same network
ldap_allowed_networks: [192.168.50.0/24]

ldap_groups:
  - { name: developers, gid: 20001 }
ldap_hostgroups:
  - { name: app, gid: 30001, hosts: [app1] }
ldap_roles:
  - { name: app-developer, groups: [developers], host_access: [app] }
ldap_users:
  - uid: alice
    given_name: Alice
    sn: Example
    uid_number: 10001
    roles: [app-developer, ldap-admins]
    password: "{{ vault_alice_initial_password }}"
```

```sh
ansible-playbook -i inventory openldap.cluster.server
ansible-playbook -i inventory openldap.cluster.directory
ansible-playbook -i inventory openldap.cluster.client
```

`alice` can now log in on `app1`, is in `developers` and administers the
directory. Later changes: edit the variables and run the `directory`
playbook; server changes and package updates go through
`openldap.cluster.update`.

## Documentation

| Topic | |
|-------|---|
| [Architecture](docs/architecture.md) | Components, replication, seeding, configuration lifecycle, files |
| [Role-based access](docs/rbac.md) | Role model, storage in LDAP, ACL matrix |
| [Security](docs/security.md) | Hardening measures, secrets, own CA, limits |
| [Operations](docs/operations.md) | Updates, adding providers, backup/restore, renewal, health checks, troubleshooting |
| [Platforms](docs/platforms.md) | Proxmox/VMware/bare metal, Hetzner Cloud, other clouds |
| [Variables](docs/variables.md) | Shared variables and links to the full per-role reference |
| [Plugins](docs/plugins.md) | Filter plugins |
| [Changelog](CHANGELOG.md) | |

## Development and tests

| | |
|---|---|
| `make lint` | ansible-lint, production profile |
| `make units` | unit tests of the filter plugins (`PYTHON=` with pytest) |
| `make sanity` | `ansible-test sanity` and `units` on exactly the tracked files (as in CI) |
| `make build` | build the collection artifact |
| CI | ansible-lint, `ansible-test sanity` and `units` for ansible-core 2.19–2.21, build |
| [`tests/hetzner/`](tests/hetzner/README.md) | end-to-end tests on real VMs (Debian 12 and 13): replication, client login, RBAC, hardening, failover, rolling update |

## Security

Please report vulnerabilities privately, see [SECURITY.md](SECURITY.md).

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
