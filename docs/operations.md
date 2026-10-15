# Operations

All playbooks accept `-e ldap_target=<pattern>` to override the target hosts.

## Initial deployment

```sh
ansible-playbook openldap.cluster.server      # providers one at a time (serial: 1)
ansible-playbook openldap.cluster.directory   # users, groups, roles, sudo
ansible-playbook openldap.cluster.client      # clients
```

Providers can also be deployed individually:

```sh
ansible-playbook openldap.cluster.server --limit ldap1
ansible-playbook openldap.cluster.server --limit ldap2   # joins by replication
```

## Day-to-day changes

| Change | Run |
|--------|-----|
| Users, groups, roles, hostgroups, sudo | `openldap.cluster.directory` (+ `client` if hostgroups of clients changed) |
| Server settings (ACLs, indexes, policy, TLS, firewall …) | `openldap.cluster.update` (rolling) or `openldap.cluster.server` |
| New client | `openldap.cluster.client --limit <host>` |

## Updates

`openldap.cluster.update` rolls changes and package updates through the
providers without losing data:

1. finds the node currently holding the shared IP and updates it **last**;
2. per node (`serial: 1`): backup with `slapcat` → `apt` upgrade of slapd →
   the `server` and `ha` roles → checks (`ldapi`, TLS 1.3 listener) → waits
   until all providers report the same `contextCSN`;
3. only then continues with the next node.

Package upgrades are on by default in this playbook; disable them with
`-e ldap_upgrade_packages=false` (a play variable, so the inventory cannot
override it).

What makes it safe: `cn=config` is never re-initialised, configuration is
changed online, schemas/modules are only added, and user passwords are only
written on creation.

## Adding a provider

1. Add the host to `ldap_servers`. Pin `ldap_server_id` for **all**
   providers if the new name sorts before existing ones (the default ID is
   the position in the sorted group).
2. `ansible-playbook openldap.cluster.server --limit <new>` – it waits for the
   data from the existing providers.
3. `ansible-playbook openldap.cluster.server` – existing providers add the
   new peer to syncrepl, keepalived and the firewall.
4. `ansible-playbook openldap.cluster.client` – clients get the new backup URI.

Removing a provider works the same way in reverse: remove it from the group,
run steps 3 and 4, then shut it down.

## Backups and restore

Every provider writes a daily dump to `ldap_backup_dir`
(`<timestamp>-config.ldif.gz`, `<timestamp>-data.ldif.gz`, kept
`ldap_backup_keep_days`). Ad hoc: `ansible-playbook openldap.cluster.backup`.
Copy backups off the hosts.

**One provider lost or broken:** reinstall it and run
`openldap.cluster.server --limit <host>`. It is bootstrapped fresh and gets
all data by replication – no backup needed.

**Data damaged everywhere** (e.g. a wrong bulk change that replicated):

```sh
# on ALL providers
systemctl stop slapd
mv /var/lib/ldap /var/lib/ldap.broken && install -d -o openldap -g openldap -m 0750 /var/lib/ldap

# on ONE provider
zcat /var/backups/slapd/<timestamp>-data.ldif.gz | slapadd -F /etc/ldap/slapd.d -n 1 -w
chown -R openldap:openldap /var/lib/ldap
systemctl start slapd

# on the other providers (they replicate everything from the restored node)
systemctl start slapd
```

Afterwards run `openldap.cluster.server` once and check the `contextCSN`
(below). Rehearse the procedure in a test environment before you need it.
The configuration dump (`-config.ldif.gz`) is for reference; `cn=config` is
rebuilt by the role.

## Certificate renewal

Server certificates are re-issued when names or keys change. To renew one
before it expires, delete it and run the role:

```sh
ansible ldap_servers -b -m file -a "path=/etc/ldap/tls/server.crt state=absent" --limit ldap1
ansible-playbook openldap.cluster.server --limit ldap1
```

The internal CA is valid for 10 years; renewing it means redistributing
`ca.crt` to all providers and clients (run `server` and `client`).

## Health checks

```sh
# replication converged? (same values on every provider)
ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -s base -b dc=example,dc=org contextCSN

# who holds the shared IP / failover history
ip -4 addr show | grep <shared IP>
journalctl -u keepalived -t ldap-ha

# replication errors
journalctl -u slapd | grep -E 'do_syncrep|syncrepl'

# client side
systemctl status sssd
sss_cache -E && id <user>
sudo -l -U <user>
```

## Release checklist

1. CI green on `main`: lint, sanity/units (ansible-core 2.19–2.21) and
   Molecule for Debian 12 and 13 (converge, idempotence, end-to-end tests).
2. On real VMs, both Debian versions ([tests/hetzner](../tests/hetzner/README.md)):
   `make up deploy test`, then `make down`. Covers what containers cannot:
   provider `hetzner`, hard power-off of a VM, real kernels and reboots.
3. Version in `galaxy.yml`, `CHANGELOG.md`, tag `vX.Y.Z`.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| User cannot log in, `id` works | No role grants access to one of the host's hostgroups (`access_provider`), or the host is in no hostgroup at all (`access_provider = deny`). |
| Bind fails with correct password | Account locked by the password policy (5 failures). Unlock as root on a provider: `ldapmodify -Q -Y EXTERNAL -H ldapi:///` with `dn: uid=<user>,ou=people,…` / `changetype: modify` / `delete: pwdAccountLockedTime`. |
| New sudo rule missing on a client | Arrives with the next smart refresh (`ldap_client_sudo_refresh`); immediately: `systemctl restart sssd`. |
| `contextCSN` differs for long | Check `journalctl -u slapd` on both sides for `do_syncrepl` errors (TLS, replicator bind, firewall). |
| Fresh provider fails with "Peers are reachable but nothing was replicated" | The peer is reachable but has no data or rejects the replicator. Deploy the providers one after another; check TLS and the seed. |
| Shared IP does not move (provider `vrrp`) | Hypervisor filters foreign IPs or gratuitous ARP, or VRRP packets are blocked – see [platforms](platforms.md). |
| SSSD logs "RootDSE could not be retrieved" | Expected: anonymous reads are disabled. |
