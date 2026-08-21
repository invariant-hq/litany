The --fix convergence loop (dune adapter lane): after a pass that applied
fixes, litany re-runs dune build @check, re-joins, re-lints, and applies
deferred conflict losers — capped at 3 passes. The fixture is a real
nested dune project; the loop's rebuilds are real dune builds.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name looplib))
  > EOP
  $ cat > litany <<'EOP'
  > (lint (extend redundant-not-not))
  > EOP

A fix that reveals a second finding: the outer double negation's fix wins
the overlap, the inner List.length fix is deferred as a conflict loser,
and the rebuild + re-lint pass picks it up — two fixes over two passes,
the third pass proving convergence.

  $ cat > chain.ml <<'EOP'
  > let f xs = not (not (List.length xs = 0))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null
  $ env -u INSIDE_DUNE litany check --fix
  fix chain.ml: 1 applied, 1 deferred (conflicts with an applied fix)
  pass 1: 1 fix applied (1 file)
  fix chain.ml: 1 applied
  pass 2 (rebuild + re-lint): 1 fix applied (1 file)
  pass 3 (rebuild + re-lint): clean
  31 rules selected · 2 units · 0 findings · 2 fixes applied · 0 skipped · 1 facts-only
  $ cat chain.ml
  let f xs = (xs = [])

The cap is a measured dial, not a loop: a six-deep negation still applies
one fix per pass, and at the cap the leftover is still a reported deferral
— the cap line names the remedy — never looped silently: exit 1, and a
re-run continues converging.

  $ cat > chain.ml <<'EOP'
  > let f xs = not (not (not (not (not (not (List.length xs = 0))))))
  > EOP
  $ env -u INSIDE_DUNE litany check --fix > cap.out 2>&1; echo "exit=$?"
  exit=1
  $ sed -n '1,11p' cap.out
  fix chain.ml: 1 applied, 5 deferred (conflicts with an applied fix)
  pass 1: 1 fix applied (1 file)
  fix chain.ml: 1 applied, 3 deferred (conflicts with an applied fix)
  pass 2 (rebuild + re-lint): 1 fix applied (1 file)
  fix chain.ml: 1 applied, 1 deferred (conflicts with an applied fix)
  pass 3 (rebuild + re-lint): 1 fix applied (1 file)
  pass cap (3) reached — re-run litany check --fix to continue converging
  File "chain.ml", line 1, characters 11-43:
  1 | let f xs = (not (not (List.length xs = 0)))
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 0 [redundant-not-not]: double negation is redundant

The re-run picks up where the cap stopped and converges.

  $ env -u INSIDE_DUNE litany check --fix
  fix chain.ml: 1 applied
  pass 1: 1 fix applied (1 file)
  pass 2 (rebuild + re-lint): clean
  31 rules selected · 2 units · 0 findings · 1 fix applied · 0 skipped · 1 facts-only
  $ cat chain.ml
  let f xs = (xs = [])

The stop contract: a post-fix build failure stops the run — build error
first, then the applied-fix list, then the exact stderr line scripts may
grep for; exit 2 with the tree deliberately left modified. (The trap rule
stands in for any build that a changed tree breaks.)

  $ cd .. && mkdir stop && cd stop
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name stoplib))
  > (rule (alias check) (deps length.ml) (action (run grep -q List.length length.ml)))
  > EOP
  $ cat > length.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > EOP
  $ env -u INSIDE_DUNE litany check --fix 2> stderr.log
  fix length.ml: 1 applied
  pass 1: 1 fix applied (1 file)
  [2]
  $ grep -A2 "dune build @check failed" stderr.log
  litany: dune build @check failed; its errors are above. Lint presupposes a building project.
  applied fix: length.ml [needless-list-length]: compare with []
  files were modified; git diff shows the applied fixes
  $ cat length.ml
  let is_empty xs = xs = []

The one-pass lanes (--cmt-root, --no-build) never loop — litany cannot
re-run a build it does not know; one pass, then the converge message.
(--no-build in the same tree: the artifacts still describe the pre-fix
bytes, so the fixed unit now skips stale — the message's very point.)

  $ cd ../proj
  $ cat > chain.ml <<'EOP'
  > let f xs = not (not (xs = []))
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null
  $ env -u INSIDE_DUNE litany check --no-build --fix
  fix chain.ml: 1 applied
  pass 1: 1 fix applied (1 file)
  1 fix applied — artifacts are now stale; rebuild and re-run to converge
  File "chain.ml", line 1, characters 11-30:
  1 | let f xs = not (not (xs = []))
                 ^^^^^^^^^^^^^^^^^^^
  Warning 0 [redundant-not-not]: double negation is redundant
    fix (safe): drop the double negation
  
  31 rules selected · 2 units · 1 finding (1 fixable) · 1 fix applied · 0 skipped · 1 facts-only
  [1]
  $ cat chain.ml
  let f xs = (xs = [])

--unsafe is the per-invocation consent for behavior-changing fixes: off,
the unsafe fix is excluded and rendered as a suggestion; on, it applies
and the pass line counts it.

  $ cd .. && mkdir uns && cd uns
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name unslib))
  > EOP
  $ cat > litany <<'EOP'
  > (lint (extend needless-append-empty))
  > EOP
  $ cat > app.ml <<'EOP'
  > let g xs = xs @ []
  > EOP
  $ env -u INSIDE_DUNE litany check --fix 2>&1 | sed -n '1p;$p'
  fix app.ml: 0 applied, 1 more with --unsafe
  31 rules selected · 2 units · 1 finding (1 fixable) · 0 fixes applied · 0 skipped · 1 facts-only
  $ env -u INSIDE_DUNE litany check --fix --unsafe
  fix app.ml: 1 applied
  pass 1: 1 fix applied (1 file, 1 unsafe)
  pass 2 (rebuild + re-lint): clean
  31 rules selected · 2 units · 0 findings · 1 fix applied · 0 skipped · 1 facts-only
  $ cat app.ml
  let g xs = xs
