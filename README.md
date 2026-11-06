# litany

[![ci](https://img.shields.io/github/actions/workflow/status/hyphatech/litany/ci.yml?branch=main&label=ci)](https://github.com/hyphatech/litany/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/hyphatech/litany?label=release)](https://github.com/hyphatech/litany/releases)
[![license](https://img.shields.io/github/license/hyphatech/litany)](LICENSE)
![OCaml 5.5](https://img.shields.io/badge/OCaml-5.5-EC6813?logo=ocaml&logoColor=white)
[![Hypha Stack](https://img.shields.io/badge/Hypha-Stack-d4a820?labelColor=15120e)](https://hyphatech.io/stack/)

A linter for OCaml that reads what the compiler wrote.
Deterministic and fixable. Hypha's fork of [invariant-hq/litany](https://github.com/invariant-hq/litany).

**Documentation**: [hyphatech.github.io/litany](https://hyphatech.github.io/litany/)

## Features

- **The compiler's own view**: rules read the typed tree, and a stale artifact is a skip, never a stale finding.
- **Identity, not spelling**: an alias or an `open` fires, and a local name that shadows one never does.
- **Fixes that compile**: a safe fix is proven by its rule's tests, and every write must reparse.
- **In your editor**: one dune rule brings findings in as compiler warnings.
- **Suppressions audited**: an allow needs a reason, and one that hides nothing is a finding.

## Install

```sh
opam repo add hypha https://github.com/hyphatech/opam-repository.git
opam install litany
```

Install it in the switch of the project it lints, on OCaml 5.5.

## Example

```ocaml
(* lib/inventory.ml *)
type t = { stock : (string * int) list }

let restock t = t
let check t = if List.length t.stock = 0 then restock t else t
let find t name = List.find (fun (n, _) -> n == name) t.stock
```

```console
$ litany check
File "lib/inventory.ml", line 4, characters 17-40:
4 | let check t = if List.length t.stock = 0 then restock t else t
                     ^^^^^^^^^^^^^^^^^^^^^^^
Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
  fix (safe): compare with []

File "lib/inventory.ml", line 5, characters 43-52:
5 | let find t name = List.find (fun (n, _) -> n == name) t.stock
                                               ^^^^^^^^^
Warning 0 [suspicious-physical-equality]: physical comparison has a non-immediate operand

30 rules selected · 1 unit · 2 findings (1 fixable — run `litany check --fix`) · 0 skipped
```

`litany check --fix` rewrites the first to `t.stock = []`; the second has no fix,
since that judgement is yours. Next: [Getting started](https://hyphatech.github.io/litany/)
and [all 84 rules](https://hyphatech.github.io/litany/reference/rules/).

## Contributing

See [AGENTS.md](AGENTS.md).

## Licence

ISC: upstream's, copyright Invariant Systems, and Hypha's additions,
copyright Hypha Technologies Ltd. See [LICENSE](LICENSE).
