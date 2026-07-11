M9 project rules: unused-export and dead-code are cross-module rules — a
per-unit collect over every admitted unit, one report over the whole
roster's facts, withheld whenever any roster unit skips. Both are Nursery,
so plain selection gates them; there is no dedicated flag.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

An unwrapped private library plus an executable root: alpha is used by the
executable (its spare export is conservatively shielded by that unit-level
reference), lone is referenced by nobody (its kept export carries a
[@litany.root] annotation), and island_top -> island_leaf is the dead
island no root reaches.

  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library
  >  (name plib)
  >  (wrapped false)
  >  (modules alpha lone island_top island_leaf))
  > (executable
  >  (name main)
  >  (modules main)
  >  (libraries plib))
  > EOP
  $ cat > alpha.mli <<'EOP'
  > val used : int -> int
  > val spare : int
  > EOP
  $ cat > alpha.ml <<'EOP'
  > let used x = x + 1
  > let spare = 5
  > EOP
  $ cat > lone.mli <<'EOP'
  > val alone : int
  > val kept : int [@@litany.root "external consumers"]
  > EOP
  $ cat > lone.ml <<'EOP'
  > let alone = 1
  > let kept = 2
  > EOP
  $ cat > island_top.ml <<'EOP'
  > let visit () = Island_leaf.leaf () + 1
  > EOP
  $ cat > island_leaf.ml <<'EOP'
  > let leaf () = 2
  > EOP
  $ cat > main.ml <<'EOP'
  > let () = ignore (Alpha.used 3)
  > EOP

The report: dead-code reaches through the island (leaf is used, but only
by dead visit), unused-export is non-transitive (no finding on leaf), the
rooted and shielded exports are silent, and findings anchor at the .mli
line when the unit has one.

  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code
  island_leaf.ml:1:5 warning dead-code
    leaf is never used in this workspace
       1 | let leaf () = 2
         |     ^^^^
  island_top.ml:1:5 warning dead-code
    visit is never used in this workspace
       1 | let visit () = Island_leaf.leaf () + 1
         |     ^^^^^
  island_top.ml:1:5 warning unused-export
    visit is exported but never used by another unit in this workspace
       1 | let visit () = Island_leaf.leaf () + 1
         |     ^^^^^
  lone.mli:1:1 warning dead-code
    alone is never used in this workspace
       1 | val alone : int
         | ^^^^^^^^^^^^^^^
  lone.mli:1:1 warning unused-export
    alone is exported but never used by another unit in this workspace
       1 | val alone : int
         | ^^^^^^^^^^^^^^^
  
  2 rules selected · 5 units · 5 findings · 0 skipped
  [1]

Determinism: facts ride the per-unit payloads, so the sharded lane and the
warm cache replay them and the page is byte-identical — worker count and
cache state are unobservable.

  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code -j 1 > page.j1
  [1]
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code -j 4 > page.j4
  [1]
  $ cmp page.j1 page.j4
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code -j 4 > page.warm
  [1]
  $ cmp page.j1 page.warm

The honesty gate: a project rule's claim is universally quantified, so one
fact-skip withholds every project report — no findings survive, the
summary names the blockers, and --explain-withheld spells out which skip
blocked which rule.

  $ echo "(* edited after the build *)" >> island_top.ml
  $ env -u INSIDE_DUNE litany check --no-build --select unused-export,dead-code --explain-withheld
  2 rules selected · 4 units · 0 findings · 1 skipped (stale 1)
  roster: project rules withheld (island_top.ml: stale — the source changed since the compiler read it)
  withheld dead-code: blocked by island_top.ml (stale — the source changed since the compiler read it)
  withheld unused-export: blocked by island_top.ml (stale — the source changed since the compiler read it)

A rebuild restores the universe; --explain-withheld also answers when
nothing was withheld.

  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code --explain-withheld > page.back
  [1]
  $ tail -1 page.back
  withheld: nothing — dead-code, unused-export ran over the complete universe

closed-world: the config bit makes public exports candidates. With the
library public, only the never-referenced exports of the (implicitly
rooted) surface change status — under open world a public library's
exports are all roots and only nothing remains; closed-world restores the
private-run findings.

  $ sed -i.bak 's/(name plib)/(name plib) (public_name plib)/' dune && rm dune.bak
  $ cat > plib.opam <<'EOP'
  > EOP
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code > page.pub
  $ grep -c "warning" page.pub
  0
  [1]
  $ cat > litany <<'EOP'
  > (lint
  >  (closed-world true))
  > EOP
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code > page.closed
  [1]
  $ grep -c "warning" page.closed
  5
  $ rm litany

Facts-only keeps the universe complete without withholding: a wrapped
library's generated alias module (.ml-gen) admits as facts-only — collect
runs, no findings can anchor in a file the user cannot edit, and project
rules still run.

  $ cd .. && mkdir wproj && cd wproj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name wlib) (modules walpha wbeta))
  > (executable (name wmain) (modules wmain) (libraries wlib))
  > EOP
  $ cat > walpha.ml <<'EOP'
  > let used x = x + 1
  > let spare = 5
  > EOP
  $ cat > wbeta.ml <<'EOP'
  > let lonely = 3
  > EOP
  $ cat > wmain.ml <<'EOP'
  > let () = ignore (Wlib.Walpha.used 2)
  > EOP
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code --explain-withheld
  2 rules selected · 4 units · 0 findings · 0 skipped · 1 facts-only
  note _build/default/wlib.ml-gen: generated (path ends in .ml-gen) — facts-only
  withheld: nothing — dead-code, unused-export ran over the complete universe

(Zero findings is itself the wrapped-library pin: the executable's
reference to Wlib is a unit-level row naming the wrapper, and the
conservative reading shields every unit the wrapper projects into —
wbeta.lonely included. Unwrapped layouts, as above, keep the shield
per-unit.)

Duplicate compilation unit names — two executables both named main.ml, an
ordinary layout — collapse the name-keyed cross-module identity. The engine
tabulates admitted unit names itself and blocks every project report with
the duplicates named: never a rule failure (exit 3), never findings (or
silent false negatives) over a collapsed identity.

  $ cd .. && mkdir dup && cd dup
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ mkdir bin tools
  $ cat > bin/dune <<'EOP'
  > (executable (name main))
  > EOP
  $ cat > bin/main.ml <<'EOP'
  > let () = print_string "a"
  > EOP
  $ cat > tools/dune <<'EOP'
  > (executable (name main))
  > EOP
  $ cat > tools/main.ml <<'EOP'
  > let () = print_string "b"
  > EOP
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code --explain-withheld
  2 rules selected · 2 units · 0 findings · 0 skipped
  roster: project rules withheld (duplicate compilation unit name Dune__exe__Main: tools/main.ml, bin/main.ml)
  withheld dead-code: duplicate compilation unit name Dune__exe__Main: tools/main.ml, bin/main.ml — cross-module identity is keyed by unit name
  withheld unused-export: duplicate compilation unit name Dune__exe__Main: tools/main.ml, bin/main.ml — cross-module identity is keyed by unit name

Two pinned classification hazards. A (test) stanza never
appears in dune describe, so its units used to reach the roster
metadata-less and project rules were unavailable on every tree with
tests; and every multi-module executable-family stanza generates a
Dune__exe alias unit (dune__exe.ml-gen), so any two such stanzas held
duplicate compilation unit names by construction and tripped the
duplicate-identity withhold forever. The adapter now claims
(test)/(tests) stanzas from the scanned dune files (kind test, the
stanza name as library) and excludes the generated alias units from the
roster — the described ones (executables) and the walked ones
(multi-module tests) alike: two multi-module executables plus a
multi-module test, and both rules run over the complete universe — the
module referenced only by the test stays silent (its user is a root),
and only the module referenced by nobody is reported.

  $ cd .. && mkdir grad && cd grad
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ mkdir lib bin tools test
  $ cat > lib/dune <<'EOP'
  > (library (name glib) (wrapped false) (modules gutil gtestonly glone))
  > EOP
  $ cat > lib/gutil.ml <<'EOP'
  > let double x = x + x
  > EOP
  $ cat > lib/gtestonly.ml <<'EOP'
  > let probe x = x * 3
  > EOP
  $ cat > lib/glone.ml <<'EOP'
  > let nobody = 1
  > EOP
  $ cat > bin/dune <<'EOP'
  > (executable (name gmain) (modules gmain ghelper) (libraries glib))
  > EOP
  $ cat > bin/gmain.ml <<'EOP'
  > let () = print_int (Ghelper.go 3)
  > EOP
  $ cat > bin/ghelper.ml <<'EOP'
  > let go x = Gutil.double x
  > EOP
  $ cat > tools/dune <<'EOP'
  > (executable (name gtool) (modules gtool gsupport) (libraries glib))
  > EOP
  $ cat > tools/gtool.ml <<'EOP'
  > let () = print_int (Gsupport.run 4)
  > EOP
  $ cat > tools/gsupport.ml <<'EOP'
  > let run x = Gutil.double (x + 1)
  > EOP
  $ cat > test/dune <<'EOP'
  > (test (name gtest) (modules gtest gt_helper) (libraries glib))
  > EOP
  $ cat > test/gt_helper.ml <<'EOP'
  > let mul x = Gtestonly.probe x
  > EOP
  $ cat > test/gtest.ml <<'EOP'
  > let () = assert (Gt_helper.mul 2 = 6)
  > EOP
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code --explain-withheld
  lib/glone.ml:1:5 warning dead-code
    nobody is never used in this workspace
       1 | let nobody = 1
         |     ^^^^^^
  lib/glone.ml:1:5 warning unused-export
    nobody is exported but never used by another unit in this workspace
       1 | let nobody = 1
         |     ^^^^^^
  
  2 rules selected · 9 units · 2 findings · 0 skipped
  withheld: nothing — dead-code, unused-export ran over the complete universe
  [1]

The test units carry their stanza's ownership metadata end to end — the
unit-file lane serializes what the adapter claimed; the excluded alias
units appear nowhere (9 units above: three library modules, four
executable modules, two test modules — never the three Dune__exe
aliases).

  $ env -u INSIDE_DUNE litany units --dump | grep "kind test"
  (unit (source test/gt_helper.ml) (cmt _build/default/test/.gtest.eobjs/byte/dune__exe__Gt_helper.cmt) (library gtest) (kind test))
  (unit (source test/gtest.ml) (cmt _build/default/test/.gtest.eobjs/byte/dune__exe__Gtest.cmt) (cmti _build/default/test/.gtest.eobjs/byte/dune__exe__Gtest.cmti) (library gtest) (kind test))
  $ env -u INSIDE_DUNE litany units --dump | grep -c "dune__exe.ml-gen"
  0
  [1]

A suppression directive naming a project rule is inert in this release —
project findings answer to configuration only — but never silently: the
per-unit note names the directive (ALT-PROJ-06), and its audit stays
withheld (zero findings proves no unused-allow fires either).

  $ cd ../proj
  $ cat >> alpha.ml <<'EOP'
  > [@@@litany.allow "unused-export: keep spare"]
  > EOP
  $ env -u INSIDE_DUNE litany check --select unused-export,dead-code
  2 rules selected · 5 units · 0 findings · 0 skipped
  note alpha.ml: directive names project rule "unused-export"; project findings answer to configuration only in this release
