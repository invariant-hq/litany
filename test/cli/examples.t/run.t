The documentation's examples, linted as its pages show them: each project
under examples/ copied into a nested dune project of its own, so the dune
adapter builds and describes it, and what litany reports there is what the
pages say it reports. Cram commands run inside dune, so the shell unsets
INSIDE_DUNE exactly as a user's shell has it.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

Getting started: the default set over a library that tests a list's
emptiness through its length and compares strings physically.

  $ mkdir inventory && cd inventory
  $ echo '(lang dune 3.20)' > dune-project
  $ mkdir lib && cp ../../../../examples/inventory/dune ../../../../examples/inventory/inventory.ml lib/
  $ env -u INSIDE_DUNE litany check
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
  [1]

The safe fix applied, and the physical comparison left to its author.

  $ env -u INSIDE_DUNE litany check --fix
  fix lib/inventory.ml: 1 applied
  pass 1: 1 fix applied (1 file)
  pass 2 (rebuild + re-lint): findings remain
  File "lib/inventory.ml", line 5, characters 43-52:
  5 | let find t name = List.find (fun (n, _) -> n == name) t.stock
                                                 ^^^^^^^^^
  Warning 0 [suspicious-physical-equality]: physical comparison has a non-immediate operand
  
  30 rules selected · 1 unit · 1 finding · 1 fix applied · 0 skipped
  [1]
  $ grep 'let check' lib/inventory.ml
  let check t = if t.stock = [] then restock t else t
