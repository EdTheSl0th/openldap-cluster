# Development helpers. End-to-end tests: see tests/hetzner/README.md.
#   make lint    ansible-lint (production profile)
#   make units   unit tests of the filter plugins (pytest)
#   make sanity  ansible-test sanity + units on a copy of the tracked files
#                (same content as CI; ansible-test needs the path
#                .../ansible_collections/openldap/cluster)
#   make build   build the collection artifact

COLLECTIONS := $(CURDIR)/tests/hetzner/.collections
PYTHON      ?= python3
SANITY_PYTHON ?= 3.12

.PHONY: collection lint units sanity build

collection:
	@$(MAKE) -s -C tests/hetzner collection

lint: collection
	ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS):$$HOME/.ansible/collections ansible-lint

units: collection
	PYTHONPATH=$(COLLECTIONS) $(PYTHON) -m pytest -q tests/unit

SANITY_DIR := $(CURDIR)/tests/output/sanity/ansible_collections/openldap/cluster

sanity:
	rm -rf $(SANITY_DIR) && mkdir -p $(SANITY_DIR)
	git ls-files -co --exclude-standard | rsync -a --files-from=- ./ $(SANITY_DIR)/
	cd $(SANITY_DIR) && git init -q && git add -A && \
		ansible-test sanity --venv --python $(SANITY_PYTHON) && \
		ansible-test units --venv --python $(SANITY_PYTHON)

build:
	ansible-galaxy collection build --force
