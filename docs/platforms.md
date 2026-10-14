# Platforms

The collection needs nothing but Debian 12/13 hosts reachable over SSH. The
only platform-specific part is how the shared IP reaches the current master
(`ldap_ha_provider` of the [ha role](../roles/ha/README.md)).

## Proxmox VE, VMware, KVM/libvirt, bare metal (`vrrp`, default)

Requirements:

* Providers and shared IP in the **same layer-2 segment** (bridge/VLAN);
  clients either in that segment or routed to it.
* The hypervisor must let a VM answer for an additional IP and send
  gratuitous ARP:
  * **Proxmox:** with the VM firewall enabled, `IP filter` (ipfilter) must be
    off for the providers' NICs or the shared IP must be in the VM's IP set
    (`ipfilter-net0`). MAC filtering is not a problem (the MAC does not
    change).
  * **VMware:** "Forged transmits" and "MAC address changes" are not needed;
    the default security policy works.
* VRRP (IP protocol 112) between the providers must not be filtered by
  network firewalls. With `ldap_ha_unicast: true` (default) no multicast is
  needed.
* `ldap_ha_vrid` must be unique in the segment if other VRRP clusters exist.

Minimal inventory:

```yaml
all:
  children:
    ldap_servers:
      hosts:
        ldap1: { ansible_host: 192.168.50.11 }
        ldap2: { ansible_host: 192.168.50.12 }
    ldap_clients:
      hosts:
        app1: { ansible_host: 192.168.50.21 }
  vars:
    ldap_domain: example.org
    ldap_secret_seed: "{{ vault_ldap_secret_seed }}"
    ldap_vip: 192.168.50.10
    ldap_allowed_networks: [192.168.50.0/24]
```

### Several networks per host

If Ansible reaches the hosts on a management network and LDAP should run on
another one, set `ldap_node_address` per host:

```yaml
ldap1: { ansible_host: 10.10.0.11, ldap_node_address: 192.168.50.11 }
```

Listeners, replication, VRRP (interface detected from this address) and the
client backup URIs use it.

## Hetzner Cloud (`hetzner`)

Private networks are routed: servers cannot announce an IP by ARP. The
shared IP is an **alias IP** that the new master assigns to itself through
the Hetzner API (`hetzner-failover`), in addition to configuring it locally.

```yaml
ldap_ha_provider: hetzner
ldap_ha_hetzner_token: "{{ vault_hcloud_token }}"
ldap_ha_hetzner_network_id: 1234567
# per host:
ldap_ha_hetzner_server_id: 7654321
```

Choose a free address of the subnet as `ldap_vip` (e.g. `.10`) that is not
assigned to any server. The repository's end-to-end tests run this setup
([tests/hetzner](../tests/hetzner/README.md)).

## Other clouds and routed networks

* **Hook:** `ldap_ha_notify_master` runs commands on every master transition,
  e.g. a CLI call that moves a floating/secondary IP to this instance:

  ```yaml
  ldap_ha_notify_master:
    - "/usr/local/bin/move-floating-ip --to $(hostname)"
  ```

  Install the tool and its credentials with your own tasks; the commands run
  as root.
* **No shared IP:** leave `ldap_vip` empty. Clients then use the first
  provider as primary and all providers as backup URIs (SSSD fails over by
  itself); the `ha` role is skipped by the `server` playbook.
* A cloud load balancer in TCP mode in front of port 636 works as well – add
  its name/IP to `ldap_tls_extra_sans` and point `ldap_client_uri` to it.
