SWITCH ?= hypha-litany
OPAM = opam exec --switch=$(SWITCH) --

.DEFAULT_GOAL := help
.PHONY: help setup pin build test lint fmt

help: ## list targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

# The test tools are upstream's, unreleased: pinned from invariant-hq at
# the commits litany was written against, since their main has moved on,
# and dune at the release its tests are written for.
WINDTRAP = git+https://github.com/invariant-hq/windtrap.git\#93473fb37635b95a0de94a228caef3df8fa798ee
THUMPER = git+https://github.com/invariant-hq/thumper.git\#0d42dc6964e30525b0595b6d5be04a1eda76c90e
setup: ## create the switch and install dependencies
	@opam switch list --short | grep -qx $(SWITCH) || opam switch create $(SWITCH) --empty -y
	opam repo add hypha https://github.com/hyphatech/opam-repository.git --switch=$(SWITCH) --rank=1
	$(MAKE) pin
	opam install . --switch=$(SWITCH) --deps-only --with-test --with-doc -y
	opam install --switch=$(SWITCH) -y ocamlformat.0.29.0 ocaml-lsp-server merlin

# With SWITCH= empty, the pins go to the current switch, as CI's is.
pin: ## pin dune and the test tools
	opam pin add $(if $(SWITCH),--switch=$(SWITCH)) --no-action -y dune 3.23.0
	opam pin add $(if $(SWITCH),--switch=$(SWITCH)) --no-action -y thumper $(THUMPER)
	opam pin add $(if $(SWITCH),--switch=$(SWITCH)) --no-action -y windtrap $(WINDTRAP)
	opam pin add $(if $(SWITCH),--switch=$(SWITCH)) --no-action -y ppx_windtrap $(WINDTRAP)

build: ## build everything
	$(OPAM) dune build @all

test: ## run every test
	$(OPAM) dune runtest test

# Release is the profile opam installs with.
lint: ## check formatting and the release build
	$(OPAM) dune build @fmt @all @install
	$(OPAM) dune build --profile release @install

fmt: ## format the code
	$(OPAM) dune fmt
