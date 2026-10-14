# End-to-end tests on Hetzner Cloud

Real VMs for `openldap.cluster`: two providers (`ldap1`, `ldap2`, group
`ldap_servers`) and one client (`client1`, group `ldap_clients`), Debian 12 or
13. Three `cx23` servers cost a few cents per hour – run `make down` when done.

The collection itself is platform-agnostic. This environment only maps its
Terraform inventory onto the collection variables
(`inventory/group_vars/all.yml`) and uses the shared-IP provider `hetzner`
(`inventory/group_vars/ldap_servers.yml`), because Hetzner's private networks
are routed (no layer 2 between servers).

## Requirements

OpenTofu, Ansible (ansible-core >= 2.16 with `cryptography`),
`community.general`, `community.crypto`, `ansible.posix`, a Hetzner Cloud
project and API token.

## Usage

```sh
cd tests/hetzner
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # token, admin IPs, image
make init
make up                  # create VMs (+ connectivity check)
make deploy              # ldap1, then ldap2 separately, directory, client
make test                # test-client, test-failover, test-update
make test-failover ARGS="-e ldap_ha_provider=vrrp -e test_vip_routed=false"
                         # plain VRRP mode (VIP placement only, see below)
make down                # destroy everything
```

Other targets: `make deploy-node NODE=ldap2`, `make update`, `make backup`,
`make ssh VM=ldap1`, `make play PLAYBOOK=playbooks/site.yml [LIMIT=ldap1]`.
To switch the Debian version change `default_image` and run `make reset`.

`make collection` (run implicitly) links the repository root to
`.collections/ansible_collections/openldap/cluster`, so the tests always use
the working copy.

Generated and secret files stay local (gitignored): `terraform.tfvars`,
Terraform state, `inventory/hosts.yml`, the secret seed
(`inventory/.secrets/`) and the internal CA (`inventory/.ldap-pki/`).

## Layout

```
terraform/                       VMs, private network, firewall, generated inventory
inventory/group_vars/all.yml     adapter Terraform -> collection, RBAC example
inventory/group_vars/ldap_servers.yml   shared IP provider "hetzner"
playbooks/check.yml              connectivity check
playbooks/site.yml               full deployment
playbooks/test_*.yml             end-to-end tests
playbooks/vars/update_change.yml change set for the update test
```

## Tests

| Test | Checks |
|------|--------|
| `test_client.yml` | replication both ways (add/delete), Argon2 hashes, host bind with derived password, groups from roles, PAM login allowed/denied per hostgroup, mkhomedir, sudo per role, no anonymous access, no plaintext bind, StartTLS, TLS 1.2 refused, ACLs per role, self-service password, password policy |
| `test_failover.yml` | slapd stopped → IP moves; recovery without preemption; holder powered off → IP moves back; write during outage reaches the rebooted node. Provider `hetzner`: alias IP via API and client access through the VIP (≈20–30 s, mostly the API action). Provider `vrrp`: VIP placement by keepalived (≈5–7 s); client access through the VIP cannot be checked on Hetzner's routed network, clients keep working via the backup URIs |
| `test_update.yml` | rolling update with a change set (new group/role/user, stricter policy, new index): no entry lost or recreated, settings active on both nodes, self-service password kept, new user can log in, backups written |
