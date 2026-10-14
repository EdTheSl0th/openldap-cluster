# Variables

The complete reference is in the role READMEs:

* [server](../roles/server/README.md#variables)
* [ha](../roles/ha/README.md#variables)
* [directory](../roles/directory/README.md#variables)
* [client](../roles/client/README.md#variables)

## Shared variables

Several roles read the same variables (each role has its own default). Set
them once for all hosts, e.g. in `group_vars/all`, so providers, directory
and clients agree:

| Variable | server | ha | directory | client | Notes |
|----------|:------:|:--:|:---------:|:------:|-------|
| `ldap_domain` | ✓ | | ✓ | ✓ | **Set it.** Defines the suffix. |
| `ldap_suffix` | ✓ | | ✓ | ✓ | Derived from `ldap_domain`. |
| `ldap_secret_seed` | ✓ | ✓ | | ✓ | **Required**, vault. |
| `ldap_servers_group` | ✓ | ✓ | | ✓ | Default `ldap_servers`. |
| `ldap_node_address` | ✓ | ✓ | | ✓ (of the servers) | Per host if not the default route. |
| `ldap_vip` | ✓ | ✓ | | ✓ | Empty = no shared IP. |
| `ldap_pki_dir` | ✓ | | | ✓ | Internal CA on the controller. |
| `ldap_dn_*` | ✓ | | ✓ | ✓ | Directory layout. |
| `ldap_role_admins`, `ldap_role_user_admins`, `ldap_role_auditors` | ✓ | | ✓ | | Built-in roles used by the ACLs. |
| `ldap_hostgroups` | | | ✓ | ✓ | Hostgroup definitions. |

## Required vs. recommended

| Variable | Why |
|----------|-----|
| `ldap_secret_seed` | Required by server, ha and client. |
| `ldap_domain` | Otherwise the directory is `dc=example,dc=org`. |
| `ldap_vip` | Required for the ha role; without it there is no shared IP. |
| `ldap_allowed_networks` | Default allows all RFC 1918 ranges. |
| `ldap_server_id` (per host) | Recommended when the cluster may grow, see [operations](operations.md#adding-a-provider). |
| `ldap_ha_hetzner_*` | Only with `ldap_ha_provider: hetzner`. |

## Playbook variables

| Variable | Playbooks | Description |
|----------|-----------|-------------|
| `ldap_target` | all | Host pattern; defaults to `ldap_servers` (`client`: `ldap_clients`). |
| `ldap_upgrade_packages` | `update` | Set to `true` by the play; disable with `-e ldap_upgrade_packages=false`. |

## Variables set by the inventory, not by the collection

`ansible_host`, `ansible_user`, … as usual. The collection does not need any
cloud- or hypervisor-specific inventory variables; the Hetzner test
environment maps its Terraform output onto the variables above in
[`tests/hetzner/inventory/group_vars`](../tests/hetzner/inventory/group_vars/).
