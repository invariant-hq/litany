# AGENTS.md

litany is an OCaml library of Hypha Stack: Hypha's fork of
[invariant-hq/litany](https://github.com/invariant-hq/litany), a linter
that reads the compiler's typed tree, with rules added and released by
Hypha. It stands on its own: it lints any OCaml project, and
knows nothing of who runs it or what they hold their code to. This file
is for anyone changing it, human or agent. Users start at
[README.md](README.md), then the documentation site, whose pages are in
[docs/](docs/); how a rule is written is
[Writing a rule](https://hyphatech.github.io/litany/guide/writing-a-rule/).

## Commands

```sh
make setup     # once: the switch hypha-litany, litany's test tools pinned
make test      # every test, and litany over itself
make lint      # formatting and the release build
make coverage  # the tests' coverage, held to its floor; CI runs it
make mutate    # the mutants no test kills, to weigh
make bench     # the timing gate, on a quiet machine
make fmt       # format in place
make docs      # the documentation site, into _build/docs; make docs-serve
```

A change that makes a sentence of the site false edits that sentence in
the same commit, as it does the README's. The rule catalog on the site is
written by `make docs` from `litany rules` and `litany explain`, never by
hand. A page imports a whole program from `examples/`, built with the
repository, and `test/cli/examples.t` lints `examples/inventory`; short
snippets and console samples are inline, and nothing checks them.

## What is Hypha's here

- **It is a library of Hypha Stack like any other.** Its CI, its
  Makefile, its releases and its tests are Hypha's, held to Hypha's
  rules, and changed where they need to be -- on Linux first. Why: Hypha
  builds on it, so it is kept as Hypha keeps its own; upstream's author
  does not answer.
  `upstream` stays a remote, its work taken where it helps.
- **A rule stands on its own.** Its doc says what it refuses and why,
  and its fixture proves it, as upstream's rules are proven. Why: litany
  lints any project, so a rule cannot lean on one project's conventions.
- **What users read names nothing of Hypha's insides.** The site, the
  README, `CHANGES.md`, an `.mli` and a rule's `~doc`, which `litany
  explain` prints, say what litany does in their own words: never a file
  or a system of Hypha's, which their readers never see. Why: they are
  published, and a reader cannot follow them there.
- **What a project refuses is its configuration, not a rule's.** A list
  of names reaches litany through a rule's options, such as
  `restricted-dependency`'s; no project's list is copied into a rule.
  Why: a project changes what it refuses with no release of this
  repository.

## What is litany's own to allow

Hypha's rules, each with its reason here, and nowhere else:

- **Tests are Windtrap, and benchmarks Thumper**, not Alcotest and QCheck.
  They are the fork's choice from upstream, and Windtrap's mutation testing is
  what `make mutate` is. They are pinned to upstream's commits until the tests
  are ported to a release: its released versions don't compile them.
- **`(lang dune 3.23)`**: `(corrections produce)` in the root `dune`, which is
  the flow litany itself documents, needs it.
- **The driver prints, reads its environment and enters a directory**:
  `lib/driver.ml`, `lib/progress.ml` and `lib/adapter.ml` are the command's own,
  in a library nothing outside this repository can install, so the printing, the
  `Sys.getenv_opt` and `Sys.chdir` are the executable's business in all but name.
- **`Unix.gettimeofday`** in `lib/progress.ml` and for the cache's stamps in
  `lib/driver.ml`, and throughout `bench/`: the stdlib has no monotonic clock,
  and no dependency is worth a meter line, a coarse eviction age or a benchmark.
- **`open Litany`** in `lib/rules/` and **`open Cmdliner`** in `bin/`: the first
  is the rule author's whole vocabulary, and the second a library of combinators
  every line of those files reads.

## Releases

As Hypha's `LIBRARY.md` says: the version in the git tag alone,
`CHANGES.md`'s `## Unreleased` renamed to it, and the GitHub release
publishing it to Hypha's opam repository through
`.github/workflows/release.yml`. Hypha's first release is 1.1.0, after
upstream's 1.0.0.
