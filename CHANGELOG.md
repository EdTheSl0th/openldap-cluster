# Changelog

All notable changes to `openldap.cluster` are documented here. The project
follows [Semantic Versioning](https://semver.org/): bug fixes increase the
patch version, new features (roles, variables, platforms) the minor version,
incompatible changes the major version.

## Unreleased

## 1.0.1

### Bugfixes

- `server`, `client`, `ha`: refresh the apt cache when no package lists
  exist (minimal images, containers, some VM templates). Before, the roles
  trusted `cache_valid_time` and failed with "No package matching …".
- `server`: the firewall replaces only its own nftables table
  (`inet ldap_filter`). `/etc/nftables.conf` no longer runs
  `flush ruleset`, which deleted the rules of other software (Docker,
  fail2ban, …). Own rules belong in `/etc/nftables.d/`.

### Tests and CI

- Molecule scenario (Docker, Debian 12/13, two providers + client) in CI:
  converge, idempotence and the end-to-end tests, including VRRP failover
  with client access through the shared IP.
- End-to-end tests moved to `tests/e2e` and shared by Molecule and the
  Hetzner VM environment, which remains a manual pre-release test.

## 1.0.0

Initial release.

### Collection

- `server`: hardened OpenLDAP provider for Debian 12 (slapd 2.5) and Debian 13
  (slapd 2.6): one-time bootstrap, online configuration via ldapi, TLS 1.3
  only, Argon2, password policy, multi-provider replication, nftables,
  sandboxed systemd unit, daily backups.
- `ha`: shared IP via keepalived; providers `vrrp` (any layer-2 network) and
  `hetzner` (alias IP via API); `ldap_ha_notify_master` hook.
- `directory`: users, posix groups, roles, host access and sudo rules.
- `client`: SSSD with a deterministic, unique bind password per host;
  idempotent on Debian 12 and 13.
- Playbooks `server`, `directory`, `client`, `update` (rolling, no data loss),
  `backup`.
- Filter plugins `derive_password`, `host_password`, `rbac_expand`,
  `host_hostgroups`, `suffix_from_domain`.

### Documentation and repository

- README per role with all variables; `docs/` with architecture, RBAC,
  security, operations, platforms, variables and plugins.
- `SECURITY.md` (private vulnerability reporting).
- CI: ansible-lint, `ansible-test` sanity and units (ansible-core 2.19–2.21),
  build; read-only token, actions pinned to commit SHAs, Dependabot.
- End-to-end tests on Hetzner Cloud VMs (`tests/hetzner`).
