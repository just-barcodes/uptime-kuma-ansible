# Local-development entry points. Mirrors what CI runs.
# Run `make help` for the full list.

COLLECTIONS_PATH := $(CURDIR)/.ansible/collections
COLLECTION_LINK  := $(COLLECTIONS_PATH)/ansible_collections/just_barcodes/uptime_kuma
ANSIBLE_ENV      := ANSIBLE_COLLECTIONS_PATH=$(COLLECTIONS_PATH)

.DEFAULT_GOAL := help

.PHONY: help sync deps lint yamllint ansible-lint syntax-check \
        build install-built test clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "; printf "Targets:\n"} \
	      /^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' \
	      $(MAKEFILE_LIST)

sync: ## Install pinned dev tools (ansible-core, ansible-lint, yamllint) via uv
	uv sync --frozen

$(COLLECTION_LINK):
	uv run ansible-galaxy collection install -r requirements.yml \
		-p $(COLLECTIONS_PATH)
	mkdir -p $(COLLECTIONS_PATH)/ansible_collections/just_barcodes
	ln -sfn $(CURDIR) $(COLLECTION_LINK)

deps: $(COLLECTION_LINK) ## Install runtime collection deps + symlink this collection at FQCN

yamllint: sync ## Run yamllint
	uv run yamllint .

ansible-lint: sync deps ## Run ansible-lint
	$(ANSIBLE_ENV) uv run ansible-lint

lint: yamllint ansible-lint ## Run all linters

syntax-check: sync deps ## Syntax-check the reference playbook against the stub inventory
	$(ANSIBLE_ENV) uv run ansible-playbook --syntax-check \
		-i tests/ci/inventory.yml -e @tests/ci/vars.yml playbooks/deploy.yml

build: sync ## Build the collection tarball into dist/
	uv run ansible-galaxy collection build --force --output-path dist/

install-built: build ## Install the built tarball to /tmp/installed-collections and re-syntax-check
	rm -rf /tmp/installed-collections
	uv run ansible-galaxy collection install -r requirements.yml -p /tmp/installed-collections
	uv run ansible-galaxy collection install dist/just_barcodes-uptime_kuma-*.tar.gz \
		-p /tmp/installed-collections
	ANSIBLE_COLLECTIONS_PATH=/tmp/installed-collections uv run ansible-playbook \
		--syntax-check -i tests/ci/inventory.yml -e @tests/ci/vars.yml \
		/tmp/installed-collections/ansible_collections/just_barcodes/uptime_kuma/playbooks/deploy.yml

test: lint syntax-check install-built ## Full local CI: lint + syntax + tarball install

clean: ## Remove build artifacts and the local collections cache
	rm -rf dist/ .ansible/ /tmp/installed-collections