# AGENTS.md

litany is an OCaml library of Hypha Stack: Hypha's fork of
[invariant-hq/litany](https://github.com/invariant-hq/litany), a linter
that reads the compiler's typed tree, with Hypha's rules added and
released by Hypha. HAF runs it as a gate on the code a model writes, so
the rules of Hypha's vault are held, not only told. This file is for
anyone changing it, human or agent. Users start at
[README.md](README.md); how a rule is written is
[doc/dev/rule-authoring.md](doc/dev/rule-authoring.md).

## Commands

```sh
make setup   # once: the switch hypha-litany, litany's test tools pinned
make test    # every test
make lint    # formatting and the release build
make fmt     # format in place
```

## What is Hypha's here

- **Upstream's code is kept as upstream wrote it.** Its shapes -- its
  test tools, windtrap and thumper, pinned from invariant-hq, and the
  `(pin)` stanzas in `dune-project` -- are its, and a change of Hypha's
  does not rewrite them. Why: a fork that rewrites what it did not need
  to cannot take upstream's work again. A change of Hypha's follows
  Hypha's `OCAML.md`, and `upstream` is a remote, merged from when it
  moves.
- **A rule of Hypha's holds a rule of Hypha's vault.** Its doc names
  the file and the rule it holds -- `OCAML.md`, *No `open` of an
  ordinary module* -- and its fixture proves it as upstream's rules are
  proven. Why: HAF counts a refusal by the rule it holds, and a lint
  that names no rule cannot be weighed.
- **What a rule is configured with is the vault's, not the rule's.**
  `OCAML.md`'s refused names reach litany through
  `restricted-dependency`'s options, which HAF writes from the vault;
  no list of the vault's is copied into a rule. Why: the vault stays the
  one source, and a name it adds is refused with no release of this
  repository.

## Releases

As Hypha's `LIBRARY.md` says: the version in the git tag alone,
`CHANGES.md`'s `## Unreleased` renamed to it, and the GitHub release
publishing it to Hypha's opam repository through
`.github/workflows/release.yml`. Hypha's first release is 1.1.0, after
upstream's 1.0.0.
