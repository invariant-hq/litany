M8 workers: litany check -j N shards the roster over N forked worker
processes and replays their per-unit results through one parent assembly
pass. The law under test: worker count is unobservable — the page is
byte-identical across every -j value. A real nested dune project with
findings, so the compared pages carry excerpts, notes, and a non-trivial
summary.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name jlib))
  > EOP
  $ cat > alpha.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > EOP
  $ cat > beta.ml <<'EOP'
  > let path = "a" ^ "b" ^ "c" ^ "d"
  > EOP
  $ cat > gamma.ml <<'EOP'
  > let also_empty xs = List.length xs = 0
  > EOP
  $ cat > delta.ml <<'EOP'
  > let clean x = x + 1
  > EOP

Byte-identity, pinned twice: -j 1 (the serial lane, no fork) against -j 4
(forked workers), on a freshly built roster and again with --no-build.
cmp prints nothing and exits 0 iff the pages are identical bytes.

  $ env -u INSIDE_DUNE litany check -j 1 > page.j1
  [1]
  $ env -u INSIDE_DUNE litany check -j 4 > page.j4
  [1]
  $ cmp page.j1 page.j4

  $ env -u INSIDE_DUNE litany check --no-build -j 1 > page2.j1
  [1]
  $ env -u INSIDE_DUNE litany check --no-build -j 4 > page2.j4
  [1]
  $ cmp page2.j1 page2.j4
  $ cmp page.j1 page2.j1

The page is the ordinary report — findings in the total order, one summary
line.

  $ grep -c "needless-list-length" page.j1
  2
  $ grep "rules selected" page.j1
  30 rules selected · 5 units · 2 findings (2 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only

An invalid worker count is a refusal.

  $ env -u INSIDE_DUNE litany check -j 0
  litany: --jobs must be at least 1
  [2]

--fix stays single-process this release: an explicit -j above 1 is noted
on standard error and ignored; the run proceeds serially.

  $ env -u INSIDE_DUNE litany check --no-build -j 4 --fix 2>&1 >/dev/null | head -1
  litany: --fix runs single-process this release; ignoring -j 4

A crashed worker loses exactly its shard: its units become counted skips
with the loss named, every other shard's results land, and the exit code
follows the normal law. (LITANY_TEST_LOSE_SHARD is the deterministic
test-only crash knob; two single-module executables make the entry-to-shard
assignment exact at -j 2.)

  $ cd .. && mkdir crash && cd crash
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (executable (name one) (modules one))
  > (executable (name two) (modules two))
  > EOP
  $ cat > one.ml <<'EOP'
  > let () = print_int (if List.length [] = 0 then 0 else 1)
  > EOP
  $ cat > two.ml <<'EOP'
  > let () = print_string ("a" ^ "b" ^ "c" ^ "d")
  > EOP
  $ env -u INSIDE_DUNE litany check >/dev/null 2>&1
  [1]
  $ env -u INSIDE_DUNE LITANY_TEST_LOSE_SHARD=1 litany check --no-build -j 2
  litany: worker lost (exited 66); 1 unit of its shard skipped
  one.ml:1:24 warning needless-list-length
    comparison through List.length is a needless emptiness test
       1 | let () = print_int (if List.length [] = 0 then 0 else 1)
         |                        ^^^^^^^^^^^^^^^^^^
    fix (safe): compare with []
  
  30 rules selected · 1 unit · 1 finding (1 fixable — run `litany check --fix`) · 1 skipped (unreadable 1)
  [1]

The signal arm of the same lane names the signal: waitpid reports OCaml's
own Sys.sig* numbering, so printing the raw constant would read "signal
-7" for a real SIGKILL. (The :kill knob variant makes the child kill
itself.)

  $ env -u INSIDE_DUNE LITANY_TEST_LOSE_SHARD=1:kill litany check --no-build -j 2 2>&1 >/dev/null | head -1
  litany: worker lost (killed by SIGKILL); 1 unit of its shard skipped
