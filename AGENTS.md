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

- **It is a library of Hypha Stack like any other.** Its CI, its
  Makefile, its releases and its tests are Hypha's, held to Hypha's
  rules, and changed where they need to be -- on Linux, where HAF's
  gates run it, first. Why: HAF builds every application on it, so it is
  kept as Hypha keeps its own; upstream's author does not answer.
  `upstream` stays a remote, its work taken where it helps.
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
