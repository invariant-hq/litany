The in-build lane: litany ships no generated files — in-dune integration
is one rule the user writes, whose (alias_rec check) deps build every
artifact before the action runs. Litany detects the action vantage from
where cwd actually is (inside the build context), walks the enclosing
context, pairs artifacts with the real source tree the context mirrors,
and defaults to the compiler report format so a failing rule's findings
land as dune diagnostics. Litany never writes a source from inside
dune: the one in-dune fix transport is dune's corrections/promotion
flow at (lang dune 3.23). The fixtures are real nested consumer
projects — one at dune lang 3.21 (reporting works; --fix refuses
toward 3.23 corrections or the terminal) and one at 3.23 (the
sandboxed norm, fixes as dune corrections) — exercised with real dune
builds; each dune-workspace file marks its project as its own root.

Dune's shared cache would replay a green child build silently on a warm
second run (a cached action's stdout is not shown again), so the nested
builds run cache-cold — this transcript must be byte-stable across
consecutive runs.

  $ export DUNE_CACHE=disabled

  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.21)
  > EOP
  $ cat > dune-workspace <<'EOP'
  > (lang dune 3.21)
  > EOP
  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (deps (sandbox none) (alias_rec check))
  >  (action (run litany check)))
  > EOP
  $ mkdir lib bin
  $ cat > lib/dune <<'EOP'
  > (library (name store))
  > EOP
  $ cat > lib/depot.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > let ids xs = List.map fst xs
  > EOP
  $ cat > lib/depot.mli <<'EOP'
  > val is_empty : 'a list -> bool
  > val ids : ('a * 'b) list -> 'a list
  > EOP
  $ cat > bin/dune <<'EOP'
  > (executable (name main) (libraries store))
  > EOP
  $ cat > bin/main.ml <<'EOP'
  > let drained xs = List.length xs = 0
  > let () = assert (drained [] && Store.Depot.is_empty [])
  > EOP

The report rule: dune build @lint fails with compiler-format diagnostics
naming the real source paths — parsed by dune, served to editors over
RPC. No dune subprocess is spawned by litany; the deps line already
built the tree.

  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  File "bin/main.ml", line 1, characters 17-35:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  File "lib/depot.ml", line 1, characters 18-36:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  exit=1

Report scope equals deps scope: a rule in a subdirectory's dune lints
that subtree only — its (alias_rec check) line keeps only that subtree
fresh, so a wider report would depend on unrelated build history. The
same tree through a lib/-scoped rule reports the lib finding and stays
silent on bin/'s, and the root rule above keeps reporting both.

  $ rm dune
  $ cat > lib/dune <<'EOP'
  > (library (name store))
  > (rule
  >  (alias lint)
  >  (deps (sandbox none) (alias_rec check))
  >  (action (run litany check)))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  File "lib/depot.ml", line 1, characters 18-36:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  exit=1
  $ cat > lib/dune <<'EOP'
  > (library (name store))
  > EOP

Sandboxing is no bar to reading: dune stages a sandboxed action in a
mirror under _build/.sandbox, but stages zero artifact files for alias
deps and never walls off reads. Litany detects the sandboxed vantage and
walks the real enclosing context against the real sources — the same
report, the same real paths, the (alias_rec check) edge still the
currency. (At dune lang 3.23 every user rule is sandboxed, so this is
the norm there — the 3.23 project below; --fix at this vantage proposes
dune corrections and never writes a source.)

  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (deps (alias_rec check) (sandbox always))
  >  (action (run litany check)))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  File "bin/main.ml", line 1, characters 17-35:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  File "lib/depot.ml", line 1, characters 18-36:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  exit=1

In-dune fixing is version-gated: litany never writes a source from
inside dune, at any dune version — the one in-dune fix transport is
dune's corrections/promotion flow, which exists at (lang dune 3.23)
(the project below). At this project's 3.21 the --fix rule refuses
toward that stanza or the terminal; read-only reporting is untouched.

  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (deps (sandbox none) (alias_rec check))
  >  (action (run litany check --fix)))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  File "dune", lines 1-4, characters 0-96:
  1 | (rule
  2 |  (alias lint)
  3 |  (deps (sandbox none) (alias_rec check))
  4 |  (action (run litany check --fix)))
  litany: refusing --fix: in-dune fixing requires (lang dune 3.23) and (corrections produce) on the rule — dune then shows fixes as diffs and dune promote applies them; on older dune, run litany check --fix from the terminal instead
  exit=1

The sources are untouched — the refusal fired before any analysis.

  $ cat bin/main.ml
  let drained xs = List.length xs = 0
  let () = assert (drained [] && Store.Depot.is_empty [])

A clean project's report rule is green — the gate passes and prints
nothing. (The findings are fixed by hand here; from a shell, litany
check --fix is the lane — pinned in fixloop.t.)

  $ cat > bin/main.ml <<'EOP'
  > let drained xs = xs = []
  > let () = assert (drained [] && Store.Depot.is_empty [])
  > EOP
  $ cat > lib/depot.ml <<'EOP'
  > let is_empty xs = xs = []
  > let ids xs = List.map fst xs
  > EOP
  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (deps (sandbox none) (alias_rec check))
  >  (action (run litany check)))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  exit=0

The dune lang 3.23 project: every user rule is sandboxed there —
(sandbox none) is refused — and rules gain (corrections produce): an
action that writes <path>.corrected files under its sandbox proposes
changes to the files they shadow; dune diffs each against its source,
fails the build, and registers promotion. That is litany's fix
transport inside dune at 3.23: --fix never writes a source at the
sandboxed vantage — the same Law-8 pipeline runs in memory and the
fixed bytes become corrections; dune promote is the single writer of
the tree.

  $ cd .. && mkdir proj323 && cd proj323
  $ cat > dune-project <<'EOP'
  > (lang dune 3.23)
  > EOP
  $ cat > dune-workspace <<'EOP'
  > (lang dune 3.23)
  > EOP
  $ mkdir lib bin
  $ cat > lib/dune <<'EOP'
  > (library (name store))
  > EOP
  $ cat > lib/depot.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > let ids xs = List.map fst xs
  > EOP
  $ cat > lib/depot.mli <<'EOP'
  > val is_empty : 'a list -> bool
  > val ids : ('a * 'b) list -> 'a list
  > EOP
  $ cat > bin/dune <<'EOP'
  > (executable (name main) (libraries store))
  > EOP
  $ cat > bin/main.ml <<'EOP'
  > let drained xs = List.length xs = 0
  > let () = assert (drained [] && Store.Depot.is_empty [])
  > EOP

A rule without the deps line builds nothing before litany runs: the
real context holds no artifacts, and an empty in-action roster is a
refusal naming the remedy, never a silent green.

  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (action (run litany check)))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  File "dune", lines 1-3, characters 0-49:
  1 | (rule
  2 |  (alias lint)
  3 |  (action (run litany check)))
  litany: the build context _build/default holds no compiled artifacts; give the rule (deps (alias_rec check)) so the tree is built before litany runs
  exit=1

The report-only rule, sandboxed by default: the run reads the real tree
and fails with diagnostics at the real source paths — exactly the
unsandboxed lane's report.

  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (deps (alias_rec check))
  >  (action (run litany check)))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  File "bin/main.ml", line 1, characters 17-35:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  File "lib/depot.ml", line 1, characters 18-36:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  exit=1

The canonical corrections stanza: --fix in the action, (corrections
produce) on the rule. Litany proposes each file's fixed bytes as a
correction and exits 0 — dune drops corrections from failing actions;
the diffs themselves fail the build — and dune shows each diff anchored
at the source and registers promotion. (This nested build keeps
INSIDE_DUNE, so dune prints its builtin label diff — machine-portable
bytes for this transcript; at a real terminal dune picks patdiff or git
and shows the same change.)

  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (deps (alias_rec check))
  >  (corrections produce)
  >  (action (run litany check --fix)))
  > EOP
  $ dune build --root . @lint 2>&1; echo "exit=$?"
  fix bin/main.ml: 1 proposed
  fix lib/depot.ml: 1 proposed
  pass 1: 2 fixes proposed (2 files)
  2 corrections proposed — dune shows each as a diff and fails the build; dune promote applies and the next build re-lints (without (corrections produce) in the rule, dune discards corrections silently)
  bin/main.ml:1:18 warning needless-list-length
    comparison through List.length is a needless emptiness test
       1 | let drained xs = List.length xs = 0
         |                  ^^^^^^^^^^^^^^^^^^
    fix (safe): compare with []
  lib/depot.ml:1:19 warning needless-list-length
    comparison through List.length is a needless emptiness test
       1 | let is_empty xs = List.length xs = 0
         |                   ^^^^^^^^^^^^^^^^^^
    fix (safe): compare with []
  
  30 rules selected · 3 units · 2 findings (2 fixable) · 2 fixes proposed · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  File "bin/main.ml", line 1, characters 0-0:
  --- bin/main.ml
  +++ _build/default/bin/main.ml.corrected
  @@ -1,2 +1,2 @@
  -let drained xs = List.length xs = 0
  +let drained xs = xs = []
   let () = assert (drained [] && Store.Depot.is_empty [])
  File "lib/depot.ml", line 1, characters 0-0:
  --- lib/depot.ml
  +++ _build/default/lib/depot.ml.corrected
  @@ -1,2 +1,2 @@
  -let is_empty xs = List.length xs = 0
  +let is_empty xs = xs = []
   let ids xs = List.map fst xs
  exit=1


The sources are untouched — the corrections live in dune's promotion
staging, and dune promote is the writer.

  $ cat bin/main.ml
  let drained xs = List.length xs = 0
  let () = assert (drained [] && Store.Depot.is_empty [])
  $ env -u INSIDE_DUNE dune promote --root . 2>&1
  Promoting _build/default/bin/main.ml.corrected to bin/main.ml.
  Promoting _build/default/lib/depot.ml.corrected to lib/depot.ml.
  $ cat bin/main.ml
  let drained xs = xs = []
  let () = assert (drained [] && Store.Depot.is_empty [])
  $ cat lib/depot.ml
  let is_empty xs = xs = []
  let ids xs = List.map fst xs

Convergence spans promotions: the promoted sources stale the artifacts,
the next build rebuilds and re-runs the rule, and the lane is green.

  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  30 rules selected · 3 units · 0 findings · 0 fixes proposed · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=0

--fix without (corrections produce) is the silent-drop hazard: dune
discards the corrected files at teardown, so the build goes green with
the fixes dropped and the sources untouched. Litany cannot see the
invoking stanza, so the proposal note always names the missing field —
that line is the only signal.

  $ cat > bin/main.ml <<'EOP'
  > let drained xs = List.length xs = 0
  > let () = assert (drained [] && Store.Depot.is_empty [])
  > EOP
  $ cat > dune <<'EOP'
  > (rule
  >  (alias lint)
  >  (deps (alias_rec check))
  >  (action (run litany check --fix)))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @lint 2>&1; echo "exit=$?"
  fix bin/main.ml: 1 proposed
  pass 1: 1 fix proposed (1 file)
  1 correction proposed — dune shows each as a diff and fails the build; dune promote applies and the next build re-lints (without (corrections produce) in the rule, dune discards corrections silently)
  bin/main.ml:1:18 warning needless-list-length
    comparison through List.length is a needless emptiness test
       1 | let drained xs = List.length xs = 0
         |                  ^^^^^^^^^^^^^^^^^^
    fix (safe): compare with []
  
  30 rules selected · 3 units · 1 finding (1 fixable) · 1 fix proposed · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=0

  $ cat bin/main.ml
  let drained xs = List.length xs = 0
  let () = assert (drained [] && Store.Depot.is_empty [])
