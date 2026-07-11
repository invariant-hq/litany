# Compiler support

This page records what is defined about compiler versions: the support
window and its policy, the seam mechanism (see also
[design.md](design.md), Compiler-version support), and the seams present
in the tree. Litany has not cut a release — `litany --version`
prints `dev` — and no release process is defined.

## The support window

Litany supports the last three OCaml minors — today 5.3, 5.4, and 5.5; the
opam bound is `>= 5.5.0 & < 5.6.0`. The model is one package, one branch,
one release: a single release compiles against whichever supported compiler
the user's switch has, and opam installs the right build per switch.

The bound is narrower than the window deliberately (the 5.5 re-lock,
2026-08): `dune pkg lock` is one solve for every platform, and under a
`>= 5.3.0` bound the macOS legs solve to relocatable-5.4.1 while Linux gets
5.5.0 — one lock, two magics. `>= 5.5.0` is what forces every platform onto
plain `ocaml-base-compiler.5.5.0` (`doc/env-55-leg.md` in git history
records the mechanism). The 5.3/5.4 seam legs stay in the tree and still
compile; widening the bound back for a released package means giving the
older minors their own lock or CI contexts, per the policy below.

Single-source multi-version does not mean one binary reading every
version's artifacts. An installed litany links one compiler-libs and reads
that compiler's artifacts only; an artifact from another minor is refused,
naming both versions. The property is per-switch, not per-binary.

## Version seams

Compiler churn is concentrated in the modules that destructure compiler
trees: `Pat` internals, the loader, the resolver, and rules matching raw
constructors. The mechanism is a version-selected copy — two or three
hand-written legs of one small module, one selected by a dune rule with
`(enabled_if (%{ocaml_version} ...))`. The copy-module route was chosen
over `[%%if]` conditional compilation: `ppx_optcomp` is not in the lock,
and a whole file per leg diffs and reviews better than interleaved
conditional blocks.

The seams in the tree (a seam target is a module of the one `litany`
library that the facade aliases nowhere, so nothing outside can name it; the
version-selected leg is copied into `lib/` under the seam's own name, and
the legs `*_53/54/55.ml` stay excluded from the module set):

| Seam | Legs | What moved |
| --- | --- | --- |
| `lib/apply_arg` | 53, 54 | `Texp_apply`'s argument payload shape |
| `lib/pat_alias` | 53, 54 | `Tpat_alias` gained a fifth argument |
| `lib/cstr` | 53, 54 | `constructor_description` moved `Types` → `Data_types` |
| `lib/tuple` | 53, 54 | tuple payloads gained labeled components |
| `lib/head` | 53, 54 | constructor/label description records moved |
| `lib/dep_kind` | 54, 55 | `Cmt_format.dependency_kind` → `Shape.Uid.Deps.kind` |
| `lib/expr_item` | 54, 55 | `Texp_letmodule` → `Texp_struct_item` |

One more version-sensitive fact lives outside the seams:
`lib/digest0.ml` handles `cmt_source_digest`, which is MD5 before 5.5
and BLAKE128 from it with no in-record discriminator, so admission accepts
a match under either algorithm.

## Window movement

The standing policy:

- Every minor in the window gets a CI leg that builds litany with that
  compiler and compiles the fixture suites with it, so magic numbers and
  digest algorithms are exercised rather than simulated. The committed
  workflow (`.github/workflows/ci.yml`) currently runs a 5.5.0 leg only —
  the 5.4.1 leg fell to the 5.5 re-lock's `>= 5.5.0` bound and returns
  when the older minors get their own lock or CI contexts. Corpus runs
  are nightly and on release, never per-PR. The five 5.3
  seam legs compile nowhere in this workspace — no 5.3 toolchain is in the
  lock — so their only evidence is the still-pending 5.3 CI lane; at the
  next re-lock, give 5.3 the same both-ways treatment the 5.5 boundary
  got (a CI context or a lock solved for 5.3), so
  all fourteen legs have build evidence.
- Dropping the oldest minor when a new one enters the window deletes its
  legs and its CI leg. Single-branch support means no backport
  multiplication.
- A maintenance ledger records changed lines and elapsed engineer-days per
  absorbed minor. If two consecutive minors each cost more than four weeks,
  the design is re-opened to evaluate vendoring a frozen reading
  frontend. A minor that
  cannot be absorbed single-source gets a frozen branch with a
  version-suffixed release for the old window instead of contorting the
  shared tree.

`doc/env-55-leg.md` (in git history since the doc restructure) records
the macOS 5.5 toolchain recipe and its pitfalls.

## Corpus discipline

The standing corpus lanes: litany's own tree (the dogfood lane); the
`.pkg` dependency store (~180 packages — litany's own dependency closure
as dune builds it); and a large application codebase.

The practiced run shape: `litany check --root DIR --cmt-root DIR
--no-build --select all,restriction,nursery` — the full-catalog audit
spelling, not `all`, because nursery and restriction rules are the ones
needing evidence — read-only over the corpus's
existing artifacts, run twice to confirm byte-identical output. Every
finding batch is triaged; the records travel in git history, and a
nursery rule graduates only on a reviewed corpus record (see
[rule-authoring.md](rule-authoring.md), The lifecycle). Changes to the
default set re-measure the engine-overhead budget (the house performance
rule: overhead below 30% of runtime); the margin is thin — the most
recent measurement was 29.0–29.7%.
