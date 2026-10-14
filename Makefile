# Development helpers. End-to-end tests: see tests/hetzner/README.md.
#   make lint    ansible-lint (production profile)
#   make units   unit tests of the filter plugins (pytest)
#   make build   build the collection artifact
# ansible-test sanity/units run in CI (.github/workflows/ci.yml); locally they
# need the checkout at .../ansible_collections/openldap/cluster.

COLLECTIONS := $(CURDIR)/tests/hetzner/.collections
PYTHON      ?= python3

.PHONY: collection lint units build

collection:
	@$(MAKE) -s -C tests/hetzner collection

lint: collection
	ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS):$$HOME/.ansible/collections ansible-lint

units: collection
	PYTHONPATH=$(COLLECTIONS) $(PYTHON) -m pytest -q tests/unit

build:
	ansible-galaxy collection build --force
