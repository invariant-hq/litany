SWITCH ?= hypha-litany
OPAM = opam exec --switch=$(SWITCH) --

.DEFAULT_GOAL := help
.PHONY: help setup pin build test lint fmt docs docs-serve

DOCS_PORT ?= 4321

help: ## list targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

# The test tools are upstream's, unreleased: pinned from invariant-hq at
# the commits litany was written against, since their main has moved on,
# and dune at the release its tests are written for.
WINDTRAP = git+https://github.com/invariant-hq/windtrap.git\#93473fb37635b95a0de94a228caef3df8fa798ee
THUMPER = git+https://github.com/invariant-hq/thumper.git\#0d42dc6964e30525b0595b6d5be04a1eda76c90e
setup: ## create the switch and install dependencies
	@command -v bun >/dev/null 2>&1 || echo "The documentation site needs Bun 1.3 or later."
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

# The tests read litany's page plain -- a parser and a grep over it -- and
# dune decides from the console it runs in whether to colour what its
# actions write: so every run, here or on CI, is given one with no colour.
test: ## run every test
	env -u CI -u TERM -u GITHUB_ACTIONS -u CLICOLOR_FORCE NO_COLOR=1 $(OPAM) dune runtest test

# Release is the profile opam installs with.
lint: ## check formatting and the release build
	$(OPAM) dune build @fmt @all @install
	$(OPAM) dune build --profile release @install

fmt: ## format the code
	$(OPAM) dune fmt

docs/node_modules: docs/package.json docs/bun.lock
	cd docs && bun install --frozen-lockfile
	@touch docs/node_modules

# The site is written in three steps. odoc's reference from the .mli files is
# copied into public/, which Starlight serves as it is, since it cannot read
# an .mli: the litany library is not installed, so it is @doc-private's, in a
# folder named with a hash, renamed here to the library's name. The rule
# catalog is written from the binary just built, so it says what the rules
# do; and then the site, whose pages import each example with ?raw.
docs: docs/node_modules ## build the documentation site
	$(OPAM) dune build @install @lib/doc-private
	rm -rf docs/public/reference
	mkdir -p docs/public/reference/litany
	cp -R _build/default/_doc/_html/litany@*/Litany docs/public/reference/litany/
	cp -R _build/default/_doc/_html/odoc.support docs/public/reference/
	chmod -R u+w docs/public/reference
	find docs/public/reference/litany -name '*.html' -exec perl -pi -e 's/litany\@[0-9a-f]+/litany/g' {} +
	cd docs && bun catalog.ts ../_build/install/default/bin/litany
	cd docs && bun --bun astro build

# The built site, as Pages serves it: Pagefind's index exists only in a
# build, and a page served as it changes loads its styles after its text.
docs-serve: docs ## serve the built documentation site
	cd docs && bun --bun astro preview --open --port $(DOCS_PORT)
