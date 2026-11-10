SWITCH ?= hypha-litany
OPAM = opam exec --switch=$(SWITCH) --

.DEFAULT_GOAL := help
.PHONY: help setup pin build test bench coverage mutate lint fmt docs docs-serve release

DOCS_PORT ?= 4321

help: ## list targets
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

# dune at the release litany's tests are written for.
# A switch is this repository's when its variable repository names this
# repository's git directory, which setup sets as it makes it: a switch of the
# same name made for anything else is refused, never used.
setup: ## create the switch and install dependencies
	@command -v bun >/dev/null 2>&1 || echo "The documentation site needs Bun 1.3 or later."
	@repository=$$(git rev-parse --path-format=absolute --git-common-dir); \
	if opam switch list --short | grep -qx '$(SWITCH)'; then \
	  made_for=$$(opam var --switch='$(SWITCH)' repository 2>/dev/null); \
	  [ -n "$$repository" ] && [ "$$made_for" = "$$repository" ] || { echo "The switch $(SWITCH) is not this repository's. Remove it, or name another with SWITCH=<name>." >&2; exit 2; }; \
	else \
	  opam switch create '$(SWITCH)' --empty --no-switch -y >/dev/null && \
	  opam var --switch='$(SWITCH)' "repository=$$repository" >/dev/null; \
	fi
	opam repo add open-opam https://github.com/open-opam/opam-repository.git --switch=$(SWITCH) --rank=1
	$(MAKE) pin
	opam install . --switch=$(SWITCH) --deps-only --with-test --with-doc -y
	opam install --switch=$(SWITCH) -y ocamlformat.0.29.0 ocaml-lsp-server merlin

# With SWITCH= empty, the pin goes to the current switch, as CI's is.
pin: ## pin dune
	opam pin add $(if $(SWITCH),--switch=$(SWITCH)) --no-action -y dune 3.23.0

build: ## build everything
	$(OPAM) dune build @all

# The tests read litany's page plain -- a parser and a grep over it -- and
# dune decides from the console it runs in whether to colour what its
# actions write: so every run, here or on CI, is given one with no colour.
TEST_ENV = env -u CI -u TERM -u GITHUB_ACTIONS -u CLICOLOR_FORCE NO_COLOR=1
test: ## run every test, and litany over itself
	$(TEST_ENV) $(OPAM) dune build @test/runtest @@runtest

bench: ## run the timing gate, on a quiet machine
	$(OPAM) dune build @bench/traversal/bench

coverage: ## measure the tests' coverage, and hold it to its floor
	$(TEST_ENV) $(OPAM) dune build @cover --instrument-with ppx_windtrap.coverage

# Survivors are work to weigh, not a failure, and some mutants are equivalent,
# so neither the suites that find them nor the merge fail this target.
mutate: ## list the mutants no test kills
	$(TEST_ENV) WINDTRAP_MUTATE=1 $(OPAM) dune build @test/runtest --force --instrument-with ppx_windtrap.mutate || true
	$(OPAM) windtrap mutants || true

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

release: ## tag VERSION and make its release
	@test "$$(git show HEAD:CHANGES.md | grep -m1 '^## ' | cut -d' ' -f2)" = "$(VERSION)" \
	  || { echo "CHANGES.md must open with ## $(VERSION)" >&2; exit 2; }
	open-opam release $(VERSION)
