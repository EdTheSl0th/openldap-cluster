# End-to-end tests on Hetzner Cloud

Run manually before a release (CI runs the same tests in Molecule, see
[tests/e2e](../e2e/README.md)). Real VMs for `openldap.cluster`: two providers (`ldap1`, `ldap2`, group
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
make down                # destroy everything
```

Other targets: `make deploy-node NODE=ldap2`, `make update`, `make backup`,
`make ssh VM=ldap1`, `make play PLAYBOOK=playbooks/site.yml [LIMIT=ldap1]`.
To switch the Debian version change `default_image` and run `make reset`.

`make collection` (run implicitly) links the repository root to
`tests/.collections/ansible_collections/openldap/cluster`, so the tests always
use the working copy. Domain and RBAC test data come from
`tests/e2e/vars/directory.yml`.

Generated and secret files stay local (gitignored): `terraform.tfvars`,
Terraform state, `inventory/hosts.yml`, the secret seed
(`inventory/.secrets/`) and the internal CA (`inventory/.ldap-pki/`).

## Layout

```
terraform/                       VMs, private network, firewall, generated inventory
inventory/group_vars/all.yml     adapter Terraform -> collection variables, seed, CA
inventory/group_vars/ldap_servers.yml   shared IP provider "hetzner"
playbooks/check.yml              connectivity check
playbooks/site.yml               full deployment
../e2e/                          the end-to-end tests and test data (shared with Molecule)
```

## Tests

See [tests/e2e](../e2e/README.md). Measured here: failover ≈20–30 s with the
provider `hetzner` (mostly the API action), a hard power-off is detected by
replication within about a minute.
