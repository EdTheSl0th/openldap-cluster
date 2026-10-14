# Filter plugins

Defined in [`plugins/filter/ldap.py`](../plugins/filter/ldap.py), covered by
[unit tests](../tests/unit/plugins/filter/test_ldap.py).

## `openldap.cluster.derive_password`

```jinja
{{ seed | openldap.cluster.derive_password(purpose, length=40) }}
```

`base64url(HMAC-SHA256(seed, purpose))`, truncated to `length`. The same
inputs always give the same password; different purposes never collide. The
seed must have at least 32 characters.

```yaml
backup_bind_pw: "{{ ldap_secret_seed | openldap.cluster.derive_password('svc:backup') }}"
```

## `openldap.cluster.host_password`

```jinja
{{ fqdn | openldap.cluster.host_password(seed) }}
```

Bind password of a client host: `derive_password(seed, "host:" + lower(fqdn))`.
Useful to configure other software on a client with the host account.

## `openldap.cluster.suffix_from_domain`

```jinja
{{ 'example.org' | openldap.cluster.suffix_from_domain }}   →  dc=example,dc=org
```

## `openldap.cluster.rbac_expand`

```jinja
{{ users | openldap.cluster.rbac_expand(roles, groups, hostgroups) }}
```

Resolves the [role model](rbac.md) into memberships:

```yaml
groups: { developers: [alice, bob], ... }   # posix group -> uids
roles:  { app-developer: [bob], ... }       # role -> uids
access: { app: [bob], ... }                 # hostgroup -> uids allowed to log in
sudo:                                       # one entry per sudo rule
  - { name: app-developer-0, role: app-developer, users: [bob],
      hosts: [app1, app1.example.org], commands: [...], runas: [ALL],
      options: [...], order: 10 }
```

Users with `state: absent` are ignored. Unknown roles, groups or hostgroups
raise an error.

## `openldap.cluster.host_hostgroups`

```jinja
{{ hostgroups | openldap.cluster.host_hostgroups([inventory_hostname, fqdn]) }}
```

Names of the hostgroups that contain one of the given names (or `ALL`).
