# Shared helper for the test environments (Molecule, Hetzner) and linting.
#   make -C tests collection
# exposes the repository root as tests/.collections/ansible_collections/openldap/cluster,
# so tests always use the working copy of the collection.

COLL_DIR := $(CURDIR)/.collections/ansible_collections/openldap

.PHONY: collection

collection:
	@mkdir -p $(COLL_DIR)
	@ln -sfn ../../../.. $(COLL_DIR)/cluster
