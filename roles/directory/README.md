# openldap.cluster.directory

Manages the directory content from a role-based model: users, posix groups,
roles, host access and sudo rules. It writes to **one** provider through
`ldapi` (SASL EXTERNAL as root); replication distributes the result.

The model and its mapping to LDAP are described in [RBAC](../../docs/rbac.md).

## Requirements

* Runs on a provider set up by `openldap.cluster.server` (schemas `rfc2307bis`
  and `sudo`, containers `ou=people`, `ou=groups`, …).
* Run it once per cluster, e.g. with `run_once` – the `directory` playbook
  does this.

## Behaviour

* **Idempotent and additive for people:** user attributes listed below are
  kept in sync; passwords are only set when a user is **created** – later
  self-service changes are never overwritten. `loginShell` is only managed
  when `shell` is set.
* **Exact for memberships:** group, role and sudo memberships are set exactly
  as computed from the model – manual additions are removed on the next run.
* **Deletion is explicit:** users disappear only with `state: absent`; groups,
  roles and hostgroups removed from the variables stay in LDAP. Generated sudo
  rules that no longer exist are deleted (`ldap_prune_sudoers`).
* References are validated before anything is written: unknown roles, groups
  or hostgroups fail the run.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_domain`, `ldap_suffix` *(shared)* | `example.org`, derived | See the server role. |
| `ldap_dn_people`, `ldap_dn_groups`, `ldap_dn_roles`, `ldap_dn_sudoers`, `ldap_dn_system` *(shared)* | `ou=<name>,{{ ldap_suffix }}` | Containers (must match the server role). |
| `ldap_role_admins`, `ldap_role_user_admins`, `ldap_role_auditors` *(shared)* | `ldap-admins`, `user-admins`, `auditors` | Built-in administrative roles; always created. Define a role with the same name in `ldap_roles` to add groups, host access or sudo to it. |
| `ldap_users_group` | `ldapusers` | Primary group of all directory users. |
| `ldap_users_gid` | `10000` | gidNumber of that group and default `gidNumber` of users. |
| `ldap_home_base` | `/home` | Default home directory base (`<base>/<uid>`). |
| `ldap_groups` | `[]` | Posix groups, see below. |
| `ldap_hostgroups` *(shared with client)* | `[]` | Sets of hosts, see below. |
| `ldap_roles` | `[]` | Roles, see below. |
| `ldap_users` | `[]` | Users, see below. |
| `ldap_prune_sudoers` | `true` | Delete `sudoRole` entries in `ou=sudoers` that are not generated from the current roles. Set `false` if you maintain your own sudo rules there. |

### `ldap_groups`

| Key | Required | Description |
|-----|----------|-------------|
| `name` | yes | Group name (`cn`). |
| `gid` | yes | `gidNumber`, unique. |
| `description` | no | Free text. |

### `ldap_hostgroups`

| Key | Required | Description |
|-----|----------|-------------|
| `name` | yes | Hostgroup name; the login group is `access-<name>`. |
| `gid` | yes | `gidNumber` of `access-<name>`. |
| `hosts` | yes | FQDNs or inventory names; `ALL` = every host. Matched by the client role against `inventory_hostname` and `ldap_client_fqdn`; sudo rules get FQDN and short name. |

### `ldap_roles`

| Key | Required | Description |
|-----|----------|-------------|
| `name` | yes | Role name (`cn` in `ou=roles`). |
| `description` | no | Free text. |
| `groups` | no | Posix groups members of the role are added to. |
| `host_access` | no | Hostgroups members may log in to. |
| `sudo` | no | List of sudo rules (below). Each becomes `sudoRole cn=<role>-<n>`. |

Sudo rule keys: `hostgroups` (list; empty = all hosts), `commands`
(default `[ALL]`), `runas` (default `[ALL]`), `options` (e.g.
`["!authenticate"]`), `order` (`sudoOrder`, default `10`).

### `ldap_users`

| Key | Required | Description |
|-----|----------|-------------|
| `uid` | yes | Login name. |
| `given_name`, `sn` | yes | First and last name. |
| `uid_number` | yes | `uidNumber`, unique (enforced by the `unique` overlay). |
| `cn` | no | Display name, default `<given_name> <sn>`. |
| `gid_number` | no | Primary group, default `ldap_users_gid`. |
| `home` | no | Home directory, default `<ldap_home_base>/<uid>`. |
| `mail` | no | E-mail address. |
| `shell` | no | `loginShell`; only managed when set. |
| `roles` | no | Roles of the user. |
| `groups` | no | Additional posix groups (outside of roles). |
| `host_access` | no | Additional hostgroups (outside of roles). |
| `password` | no | Initial password, used only on creation, hashed by the server (Argon2). Must satisfy the password policy. Keep it in ansible-vault. |
| `state` | no | `present` (default) or `absent`. |

## Example

```yaml
ldap_groups:
  - { name: developers, gid: 20001 }
ldap_hostgroups:
  - { name: web, gid: 30001, hosts: [web1.example.org, web2.example.org] }
ldap_roles:
  - name: web-operator
    groups: [developers]
    host_access: [web]
    sudo:
      - { hostgroups: [web], commands: ["/usr/bin/systemctl restart nginx"], options: ["!authenticate"] }
ldap_users:
  - uid: alice
    given_name: Alice
    sn: Example
    uid_number: 10001
    roles: [web-operator, ldap-admins]
    password: "{{ vault_alice_initial_password }}"
```
