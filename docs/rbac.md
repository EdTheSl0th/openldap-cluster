# Role-based access control

Users never get permissions directly – they get **roles**. A role bundles

| Permission | Variable key | Implemented as |
|------------|--------------|----------------|
| Unix groups | `groups` | membership in `cn=<group>,ou=groups` (posix groups on the clients) |
| Login on hosts | `host_access` | membership in `cn=access-<hostgroup>,ou=groups`; SSSD on each client allows only the access groups of its hostgroups |
| sudo | `sudo` | `sudoRole` entries in `ou=sudoers`, read by SSSD |
| Rights in the directory | built-in roles | ACLs referencing `cn=<role>,ou=roles` |

All variables and keys are listed in the
[directory role](../roles/directory/README.md#variables).

## Example

```yaml
ldap_groups:
  - { name: developers, gid: 20001 }
  - { name: dbadmins, gid: 20003 }

ldap_hostgroups:
  - { name: all-servers, gid: 30001, hosts: [ALL] }
  - { name: app, gid: 30002, hosts: [app1.example.org] }
  - { name: db, gid: 30003, hosts: [db1.example.org] }

ldap_roles:
  - name: app-developer
    groups: [developers]
    host_access: [app]
    sudo:
      - hostgroups: [app]
        commands: ["/usr/bin/systemctl restart nginx", "/usr/bin/journalctl"]
        options: ["!authenticate"]
  - name: dba
    groups: [dbadmins]
    host_access: [db]
    sudo:
      - { hostgroups: [db], commands: [ALL], runas: [postgres] }

ldap_users:
  - { uid: bob, given_name: Bob, sn: Dev, uid_number: 10002, roles: [app-developer] }
  - { uid: carol, given_name: Carol, sn: DBA, uid_number: 10003, roles: [dba] }
  - { uid: dave, given_name: Dave, sn: Help, uid_number: 10004, roles: [user-admins, auditors] }
```

Result on `app1.example.org`:

| User | Groups | Login | sudo |
|------|--------|-------|------|
| bob | ldapusers, developers, access-app | allowed | `systemctl restart nginx`, `journalctl` without password |
| carol | ldapusers, dbadmins, access-db | **denied** (no role for hostgroup `app`) | – |
| dave | ldapusers | denied | – (but may manage people in the directory) |

## How it is stored

```
cn=app-developer,ou=roles      member: uid=bob,…   seeAlso: cn=developers,…, cn=access-app,…
cn=developers,ou=groups        member: uid=bob,…   gidNumber: 20001
cn=access-app,ou=groups        member: uid=bob,…   gidNumber: 30002
cn=app-developer-0,ou=sudoers  sudoUser: bob  sudoHost: app1, app1.example.org  sudoCommand: …
```

Role objects keep the membership and point to the granted groups
(`seeAlso`), so "who has which role and what does it grant" is visible in
the directory itself. Memberships are always set exactly from the model:
manual changes in LDAP are reverted by the next run.

## Directory permissions (ACLs)

Three roles are built in and referenced by `ldap_acl` of the server role:

| Subject | People (except passwords) | Passwords | Groups | Roles, hosts, system | Sudo rules |
|---------|---------------------------|-----------|--------|----------------------|------------|
| `ldap-admins` | write | set / reset (no read) | write | write | write |
| `user-admins` | write | set / reset in `ou=people` | write | – | – |
| `auditors` | read | – | read | read | read |
| any user (`users`) | read | own: change | read | – | – |
| user on own entry (`self`) | `loginShell`, `telephoneNumber`, `mobile` write | change | – | – | – |
| client host (`ou=hosts`) | read | – | read | own entry | read |
| replicator | read all, including hashes | read | read | read | read |
| anonymous | – (bind only) | authenticate | – | – | – |

Nobody can read password hashes except the replicator. There is no root
password: full access exists only locally as root through `ldapi`.

To customise, override `ldap_acl` as a whole (ordered list of `olcAccess`
rules, first match wins). Keep the replicator's `read` access on everything,
otherwise replication silently misses data.

## Typical tasks

```sh
# reset a password as user-admin (over TLS)
ldappasswd -H ldaps://ldap.example.org -D uid=dave,ou=people,dc=example,dc=org -W \
  -S uid=bob,ou=people,dc=example,dc=org

# change the own password
ldappasswd -H ldaps://ldap.example.org -D uid=bob,ou=people,dc=example,dc=org -W -S
```

Adding a user to a role or a role to a hostgroup is a change of the
variables followed by the `directory` playbook. New sudo rules reach clients
within `ldap_client_sudo_refresh` (default 300 s).
