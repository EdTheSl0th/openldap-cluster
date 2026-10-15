# End-to-end tests

Shared by the Molecule scenario (`extensions/molecule/default`, Docker, runs in
CI) and the VM environment (`tests/hetzner`, manual before releases).

| Playbook | Checks |
|----------|--------|
| `test_client.yml` | replication both ways (add/delete), Argon2 hashes, host bind with derived password, groups from roles, PAM login allowed/denied per hostgroup, mkhomedir, sudo per role, no anonymous access, no plaintext bind, StartTLS, TLS 1.2 refused, ACLs per role, self-service password, password policy |
| `test_failover.yml` | slapd stopped → shared IP moves; recovery without preemption; holder powered off → IP moves back; write during the outage reaches the rebooted node |
| `test_update.yml` | rolling update with the change set `vars/update_change.yml` (new group/role/user, stricter policy, new index): no entry lost or recreated, settings active on all providers, self-service password kept, new user can log in, backups written |

Inputs:

| File / variable | Purpose |
|-----------------|---------|
| `vars/directory.yml` | Domain and RBAC test data, passed as extra vars (`-e @tests/e2e/vars/directory.yml`) |
| `vars/update_change.yml` | Change set, loaded by `test_update.yml` itself |
| `test_platform` | `docker` (Molecule) or `hetzner` (VMs): how a server is powered off/on (`tasks/power_<platform>.yml`) |
| `test_vip_routed` | Check client access through the shared IP (default: only with provider `hetzner`; Molecule sets `true`, its Docker network is layer 2) |

| Environment | Shared IP provider | What it adds |
|-------------|--------------------|--------------|
| Molecule (CI, every PR) | `vrrp` – gratuitous ARP on a layer-2 network | Idempotence, Debian 12/13, client access through the VIP with plain VRRP |
| Hetzner VMs (manual) | `hetzner` – alias IP via API | Real kernels and reboots, hard power-off of a VM, the cloud provider |
