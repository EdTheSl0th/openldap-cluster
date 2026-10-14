# End-to-end test environment for openldap.cluster on Hetzner Cloud.
# VMs are defined in terraform/terraform.tfvars (copy terraform.tfvars.example).
#   make init | up | check | ssh VM=ldap1 | reset [VM=ldap1] | down
#   make deploy               ldap1, then ldap2 (separately), directory, clients
#   make deploy-node NODE=ldap2
#   make test                 client/RBAC/hardening + failover + update tests
#   make play PLAYBOOK=playbooks/site.yml [LIMIT=ldap1]

TF       := tofu -chdir=terraform
# The repository root is the collection; expose it to Ansible via a symlink.
COLL_DIR := $(CURDIR)/.collections/ansible_collections/openldap
ANSIBLE  := ANSIBLE_CONFIG=$(CURDIR)/ansible.cfg ansible-playbook $(ARGS)
VM       ?=
NODE     ?=
LIMIT    ?=
PLAYBOOK ?=
ARGS     ?=

.PHONY: init up check play ssh reset output down collection deploy deploy-node update backup \
	test test-client test-failover test-update

init:
	$(TF) init

up:
	$(TF) apply
	$(MAKE) check

collection:
	@mkdir -p $(COLL_DIR)
	@ln -sfn ../../../../.. $(COLL_DIR)/cluster

check: collection
	$(ANSIBLE) playbooks/check.yml

play: collection
	@test -n "$(PLAYBOOK)" || { echo "usage: make play PLAYBOOK=playbooks/site.yml [LIMIT=group]"; exit 1; }
	$(ANSIBLE) $(if $(LIMIT),--limit $(LIMIT)) $(PLAYBOOK)

ssh:
	@test -n "$(VM)" || { echo "usage: make ssh VM=<name>"; exit 1; }
	@eval "$$($(TF) output -json ssh_commands | python3 -c 'import json,sys; print(json.load(sys.stdin)["$(VM)"])')"

# Rebuild all VMs (or only VM=<name>) to a fresh image; IPs, network and volumes stay.
reset:
	$(TF) apply $(if $(VM),-replace='hcloud_server.vm["$(VM)"]',$(foreach s,$(shell $(TF) state list | grep '^hcloud_server\.vm\['),-replace='$(s)'))
	$(MAKE) check

output:
	$(TF) output

down:
	$(TF) destroy

deploy: collection
	@for n in $$(ANSIBLE_CONFIG=$(CURDIR)/ansible.cfg ansible ldap_servers --list-hosts | tail -n +2 | sort); do \
		$(ANSIBLE) openldap.cluster.server --limit $$n || exit 1; done
	$(ANSIBLE) openldap.cluster.directory
	$(ANSIBLE) openldap.cluster.client

deploy-node: collection
	@test -n "$(NODE)" || { echo "usage: make deploy-node NODE=<ldap-server>"; exit 1; }
	$(ANSIBLE) openldap.cluster.server --limit $(NODE)

update: collection
	$(ANSIBLE) openldap.cluster.update

backup: collection
	$(ANSIBLE) openldap.cluster.backup

test: test-client test-failover test-update

test-client: collection
	$(ANSIBLE) playbooks/test_client.yml

test-failover: collection
	$(ANSIBLE) playbooks/test_failover.yml

test-update: collection
	$(ANSIBLE) playbooks/test_update.yml -e @playbooks/vars/update_change.yml
