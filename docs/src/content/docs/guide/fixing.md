---
title: Fixing
description: "Safe and unsafe fixes, the checks on every write, and where --fix refuses."
---

A fix is **safe** when it preserves behaviour, which the rule's tests prove
with a fixed copy that must compile, or **unsafe** when it may not, and its
title says how.

| Command | Applies |
| --- | --- |
| `litany check --fix` | safe fixes |
| `litany check --fix --unsafe` | safe and unsafe fixes |

Fixing a file makes its artifact stale, so litany rebuilds and lints again,
until clean or for at most three passes. Overlapping fixes are settled
deterministically, and the loser waits for the next pass. The exit code
describes the tree left behind: 0 clean, 1 findings remain.

With `--units`, `--cmt-root` or `--no-build` litany can't rebuild, so one pass
runs and it tells you to rebuild and run again; the exit code then describes
the tree before the fixes.

## What is checked before a write

- The source's digest is checked again at the moment of writing, so a fix
  computed against bytes you have since edited is discarded.
- Writes are atomic.
- The result must parse as OCaml. If it doesn't, the file is rolled back and
  the run exits 3.
- In a preprocessed unit a safe fix counts as unsafe, since the tree litany
  matched isn't the file you edit.

## If a rebuild fails

litany stops, prints the build error and every fix it applied, and exits 2
after this line on stderr:

```text
files were modified; git diff shows the applied fixes
```

Exit 2 without that line means the tree is untouched.

## Where --fix refuses

litany never writes a source from inside dune. A `--fix` that can't fix refuses
with exit 2, rather than look like a check that passed:

- under `dune exec`: run the installed binary instead;
- in a dune rule on a dune language older than 3.23: run it from a terminal,
  or use [the corrections rule](/litany/guide/build-integration/#fixing-in-the-build)
  on 3.23;
- in a dune rule given `--units` or `--cmt-root`.
