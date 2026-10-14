# openldap.cluster.ha

Shared IP for the LDAP providers with keepalived (VRRP). Clients talk to one
address; when slapd or the whole server fails, another provider takes it over.

* Unicast VRRP between the providers by default (works without multicast).
* Health check `check-slapd`: slapd must answer on `ldapi` and listen on 636;
  otherwise the node leaves the master role.
* `nopreempt`: a recovered node does not take the IP back (no flapping).
* On every master transition `notify-master` runs the provider and your own
  hooks.

Platform specifics live in *providers* – see [platforms](../../docs/platforms.md).

| Provider | Use on | How the IP moves |
|----------|--------|------------------|
| `vrrp` (default) | any layer-2 network: Proxmox bridges/VLANs, VMware, KVM/libvirt, bare metal | keepalived adds the IP on the master and announces it with gratuitous ARP |
| `hetzner` | Hetzner Cloud private networks (routed, no ARP between servers) | additionally assigns the IP as alias IP through the Hetzner API |

## Requirements

* At least two hosts in `ldap_servers_group`, `ldap_vip` set,
  `ldap_secret_seed` (VRRP password is derived from it).
* Usually applied together with `openldap.cluster.server` (see the `server`
  playbook).

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_vip` *(shared)* | – **required** | The shared IP. Must be unused and reachable for the clients. |
| `ldap_ha_vip` | `{{ ldap_vip }}` | Internal alias of `ldap_vip`. |
| `ldap_ha_vip_prefix` | `32` | Prefix length used when adding the IP to the interface. |
| `ldap_servers_group` *(shared)* | `ldap_servers` | Group of the providers taking part. |
| `ldap_node_address` *(shared)* | default IPv4 from facts | Source address for VRRP; the interface holding it carries the shared IP. Peers are read from the inventory (`ldap_node_address`, else `ansible_host`). |
| `ldap_ha_interface` | `""` (auto) | Interface for VRRP and the shared IP; detected from `ldap_node_address` when empty. |
| `ldap_ha_vrid` | `51` | VRRP router ID (1–255). Must be unique per layer-2 segment – change it if other keepalived/VRRP clusters share the network. |
| `ldap_ha_priority` | `150`, `140`, … by group order | VRRP priority; the highest healthy node becomes the first master. |
| `ldap_ha_check_interval` | `2` | Seconds between health checks. |
| `ldap_ha_check_fall` | `2` | Failed checks before a node gives up the master role. |
| `ldap_ha_unicast` | `true` | Unicast VRRP to the peers. `false`: multicast (needs multicast on the network). |
| `ldap_ha_provider` | `vrrp` | `vrrp` or `hetzner` (see above). |
| `ldap_ha_notify_master` | `[]` | Extra shell commands run as root on every master transition, e.g. a script moving a cloud IP: `["/usr/local/bin/move-ip --to $(hostname)"]`. A failing command is logged; it does not stop the failover. |

### Provider `hetzner`

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_ha_hetzner_token` | – **required** | Hetzner Cloud API token (read/write). Stored on the providers in `/etc/ldap-ha/hetzner.json` (root, 0600). It can change alias IPs of the whole project – use a dedicated project. |
| `ldap_ha_hetzner_network_id` | – **required** | ID of the private network. |
| `ldap_ha_hetzner_server_id` | – **required, per host** | Server ID of each provider (the peers' IDs are read from the inventory). |

When the provider is `hetzner`, every deployment also re-assigns the alias IP
to the current master, so switching providers or manual changes are healed
without waiting for the next failover.

## Files on the nodes

| Path | Purpose |
|------|---------|
| `/etc/keepalived/keepalived.conf` | VRRP instance `LDAP` |
| `/usr/local/libexec/ldap-ha/check-slapd` | Health check |
| `/usr/local/libexec/ldap-ha/notify-master` | Runs provider + hooks; logs `MASTER for <ip>` with tag `ldap-ha` |
| `/usr/local/libexec/ldap-ha/hetzner-failover`, `/etc/ldap-ha/hetzner.json` | Provider `hetzner` only |

## Example

```yaml
# group_vars/all.yml
ldap_vip: 192.168.50.10

# Hetzner Cloud instead of layer 2:
ldap_ha_provider: hetzner
ldap_ha_hetzner_token: "{{ vault_hcloud_token }}"
ldap_ha_hetzner_network_id: 1234567
# host_vars/ldap1.yml
ldap_ha_hetzner_server_id: 7654321
```
