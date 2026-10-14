# Changelog

All notable changes to `openldap.cluster` are documented here. The project
follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Documentation: README per role with all variables, `docs/` with
  architecture, RBAC, security, operations, platforms, variables and plugins.
- `client`: `sssd.conf` stays idempotent on Debian 13 (SSSD 2.10 makes it
  group-readable on start).

## 1.0.0

Initial release.

- `server`: hardened OpenLDAP provider for Debian 12 (slapd 2.5) and Debian 13
  (slapd 2.6): one-time bootstrap, online configuration via ldapi, TLS 1.3
  only, Argon2, password policy, multi-provider replication, nftables,
  sandboxed systemd unit, daily backups.
- `ha`: shared IP via keepalived; providers `vrrp` (any layer-2 network) and
  `hetzner` (alias IP via API); `ldap_ha_notify_master` hook.
- `directory`: users, posix groups, roles, host access and sudo rules.
- `client`: SSSD with a deterministic, unique bind password per host.
- Playbooks `server`, `directory`, `client`, `update` (rolling, no data loss),
  `backup`.
