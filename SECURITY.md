# Security policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.x | ✓ |
| < 1.0 | – |

Fixes are released for the latest 1.x version.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them
privately via GitHub:
[Report a vulnerability](https://github.com/EdTheSl0th/openldap-cluster/security/advisories/new).

Please include:

* affected version or commit,
* the role/playbook and relevant variables (without real secrets),
* steps to reproduce and the impact you expect.

Reports are handled on a best-effort basis. You will get feedback on whether
the issue is confirmed, and credit in the advisory if you wish.

## Scope

In scope: the roles, playbooks and plugins of this collection and the
configuration they produce (TLS, ACLs, firewall, systemd hardening, secret
handling, shared IP failover).

Out of scope: vulnerabilities in OpenLDAP, SSSD, keepalived, Debian packages or
Ansible itself – please report those upstream. The test environment in
`tests/hetzner/` is not meant for production use.

The hardening measures and known limitations are described in
[docs/security.md](docs/security.md).
