litany check --fix applies the kept findings' safe fixes after the report —
one pass, digest-verified against the admission-time witness, atomic write.
The summary drops the "run litany check --fix" remedy while --fix runs.

Cram commands run as a sandboxed dune action (INSIDE_DUNE set, cwd
inside _build/.sandbox). With an explicit roster (--cmt-root/--units)
--fix refuses at this vantage: a direct write would land in the staged
copy and be discarded with the sandbox, and an explicit roster's paths
cannot ride dune's corrections flow (that pairing is the auto roster's
context mirror — the build-integration manual's lane). Pin the refusal
first: message, exit 2, file untouched.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ cp -RL ../fixture proj && chmod -R u+w proj && cd proj

  $ litany check --cmt-root . --fix
  litany: refusing --fix: this action is sandboxed and the roster is explicit (--cmt-root/--units), so fixes cannot ride dune's corrections — litany mirrors only the context it walks itself; drop the roster flag (with (corrections produce) in the rule, dune shows fixes as diffs and dune promote applies), or run litany check --fix outside dune
  [2]
  $ cat length.ml
  let is_empty xs = List.length xs = 0

The applying runs below simulate the user's shell with env -u INSIDE_DUNE
(litany treats any value as set, so INSIDE_DUNE= would not be an unset).

  $ env -u INSIDE_DUNE litany check --cmt-root . --fix
  fix length.ml: 1 applied
  pass 1: 1 fix applied (1 file)
  1 fix applied — artifacts are now stale; rebuild and re-run to converge
  File "funcmp.ml", line 3, characters 13-24:
  3 | let broken = compare f g
                   ^^^^^^^^^^^
  Warning 0 [invalid-function-comparison]: structural comparison has a function operand
    
  File "length.ml", line 1, characters 18-36:
  1 | let is_empty xs = List.length xs = 0
                        ^^^^^^^^^^^^^^^^^^
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
    
  File "phys.ml", line 1, characters 33-39:
  1 | let same_object (a : string) b = a == b
                                       ^^^^^^
  Warning 0 [suspicious-physical-equality]: physical comparison has a non-immediate operand
    
  File "warnattr.ml", line 1, characters 0-17:
  1 | [@@@warning "-a"]
      ^^^^^^^^^^^^^^^^^
  Warning 0 [disable-all-warnings]: attribute disables all compiler warnings
  
  30 rules selected · 6 units · 4 findings (1 fixable) · 1 fix applied · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  [1]
  $ cat length.ml
  let is_empty xs = xs = []

The artifact is now stale by construction — convergence spans builds (M6);
a plain re-run skips the fixed unit rather than lint bytes the compiler
never saw.

  $ litany check --cmt-root . 2>&1 | grep "rules selected"
  30 rules selected · 5 units · 3 findings · 1 skipped (stale 1) · 1 facts-only

Byte-determinism: two fresh copies fix to identical bytes with identical
pages.

  $ cd .. && cp -RL ../fixture proj2 && chmod -R u+w proj2 && cp -RL ../fixture proj3 && chmod -R u+w proj3
  $ (cd proj2 && env -u INSIDE_DUNE litany check --cmt-root . --fix) > fix2.out 2>&1; (cd proj3 && env -u INSIDE_DUNE litany check --cmt-root . --fix) > fix3.out 2>&1; cmp fix2.out fix3.out && cmp proj2/length.ml proj3/length.ml && echo deterministic
  deterministic

Suppression and fixes: an allow'd finding is never fixed — its line keeps
its bytes — while the stale allow's own unused-allow audit carries the
deletion fix and --fix removes the attribute.

  $ cp -RL ../fixture_allow proja && chmod -R u+w proja && cd proja
  $ env -u INSIDE_DUNE litany check --cmt-root . --fix
  fix allowed.ml: 2 applied
  pass 1: 2 fixes applied (1 file)
  2 fixes applied — artifacts are now stale; rebuild and re-run to converge
  File "allowed.ml", line 2, characters 20-38:
  2 | let also_empty xs = List.length xs = 0
                          ^^^^^^^^^^^^^^^^^^
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
    
  File "allowed.ml", line 3, characters 13-59:
  3 | let fine = 1 [@@litany.allow "needless-list-length: stale"]
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 0 [unused-allow]: allow "needless-list-length" matched no finding
    fix (safe): delete the unused allow
  
  30 rules selected · 2 units · 2 findings (2 fixable) · 2 fixes applied · 0 skipped · 1 facts-only · 1 suppressed
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  [1]
  $ cat allowed.ml
  let is_empty xs = (List.length xs = 0) [@litany.allow "needless-list-length: benchmark helper"]
  let also_empty xs = xs = []
  let fine = 1

--fix never writes into a build tree: findings can anchor there when the
walk root covers _build (a generated unit's only source is its build-tree
copy), and fixing them would mutate dune's cache at best and corrupt it at
worst. The write is refused, loudly, and the file keeps its bytes.

  $ cd .. && mkdir -p projb/_build && cp -RL ../fixture projb/_build/default && chmod -R u+w projb && cd projb
  $ env -u INSIDE_DUNE litany check --cmt-root . --fix 2>&1 | grep -E "^fix |rules selected"
  fix _build/default/length.ml: refused — build-tree path (litany never writes into _build)
  30 rules selected · 6 units · 4 findings (1 fixable) · 0 fixes applied · 0 skipped · 1 facts-only
  $ cat _build/default/length.ml
  let is_empty xs = List.length xs = 0
