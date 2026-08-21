The restricted-export-name cram: the configured naming policy end to
end — a nested dune project, a litany config with the two closed
options, selection by exact name, and the schema's refusals. The
fixture is built for real inside the sandbox; cram commands run inside
dune, so the shell unsets INSIDE_DUNE exactly as a user's shell has it.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir -p proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name ren_cram))
  > EOP

An mli-backed module — the interface is the export surface — and an
ml-only module, where the derived signature exports every root name.

  $ cat > naming.mli <<'EOP'
  > val parse' : int -> int
  > val a_b_c_d_e : int
  > type t'
  > EOP
  $ cat > naming.ml <<'EOP'
  > type t' = int
  > let helper' n = n + 1
  > let parse' n = helper' n
  > let a_b_c_d_e = 4
  > EOP
  $ cat > bare.ml <<'EOP'
  > type u' = string
  > let go' x = x
  > let total_count_of_all_things = 0
  > let fine_name = 2
  > EOP

The workspace policy: no prime suffixes, at most three underscores, in
exported names.

  $ cat > litany <<'EOP'
  > (rule restricted-export-name
  >  (forbid-suffix ')
  >  (max-underscores 3))
  > EOP

Configured but not selected: the rule is Restriction — outside default
and all — so a plain check runs none of it and says so.

  $ env -u INSIDE_DUNE litany check 2>&1 | grep -E "restricted-export-name|rules selected"
  litany: rule "restricted-export-name" is configured but not selected
  30 rules selected · 3 units · 0 findings · 0 skipped · 1 facts-only

Selected by exact name: each offending exported name fires once, the
message naming the condemning option; helper', hidden by naming.mli,
stays silent, and every root name of bare.ml is export surface.

  $ env -u INSIDE_DUNE litany check --select restricted-export-name
  File "bare.ml", line 1, characters 5-7:
  1 | type u' = string
           ^^
  Warning 0 [restricted-export-name]: u' ends with "'", forbidden in exported names by (forbid-suffix ')
    
  File "bare.ml", line 2, characters 4-7:
  2 | let go' x = x
          ^^^
  Warning 0 [restricted-export-name]: go' ends with "'", forbidden in exported names by (forbid-suffix ')
    
  File "bare.ml", line 3, characters 4-29:
  3 | let total_count_of_all_things = 0
          ^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 0 [restricted-export-name]: total_count_of_all_things carries 4 underscores, over the (max-underscores 3) limit for exported names
    
  File "naming.ml", line 1, characters 5-7:
  1 | type t' = int
           ^^
  Warning 0 [restricted-export-name]: t' ends with "'", forbidden in exported names by (forbid-suffix ')
    
  File "naming.ml", line 3, characters 4-10:
  3 | let parse' n = helper' n
          ^^^^^^
  Warning 0 [restricted-export-name]: parse' ends with "'", forbidden in exported names by (forbid-suffix ')
    
  File "naming.ml", line 4, characters 4-13:
  4 | let a_b_c_d_e = 4
          ^^^^^^^^^
  Warning 0 [restricted-export-name]: a_b_c_d_e carries 4 underscores, over the (max-underscores 3) limit for exported names
  
  1 rule selected · 3 units · 6 findings · 0 skipped · 1 facts-only
  [1]


Unconfigured selection is inert by contract: with no (rule ...) form
nothing is restricted, and the run is clean — and says so:
selected-but-unconfigured is the mirror of the configured-but-unselected
trap, warned on the same channel.

  $ rm litany
  $ env -u INSIDE_DUNE litany check --select restricted-export-name 2>&1 | head -2
  litany: rule "restricted-export-name" is selected but not configured; it reports nothing without a (rule restricted-export-name ...) form
  1 rule selected · 3 units · 0 findings · 0 skipped · 1 facts-only

A malformed count is a positioned refusal — the closed schema — and
nothing runs.

  $ cat > litany <<'EOP'
  > (rule restricted-export-name
  >  (max-underscores many))
  > EOP
  $ env -u INSIDE_DUNE litany check --select restricted-export-name
  litany: litany:2:19: max-underscores wants a non-negative count, not "many"
  [2]

So is a user-supplied pattern language: the options are enumerated,
never a regex.

  $ cat > litany <<'EOP'
  > (rule restricted-export-name
  >  (forbid-regex ".*'$"))
  > EOP
  $ env -u INSIDE_DUNE litany check --select restricted-export-name
  litany: litany:2:2: unknown option "forbid-regex" (options: forbid-suffix, max-underscores)
  [2]

The policy fires on executables and tests too: an ml-only unit exports
every root declaration — executables included, their root names surface
to their own readers — and the tier keeps the rule opt-in.

  $ cat > litany <<'EOP'
  > (rule restricted-export-name
  >  (forbid-suffix '))
  > EOP
  $ mkdir tool
  $ cat > tool/dune <<'EOP'
  > (executable (name main))
  > EOP
  $ cat > tool/main.ml <<'EOP'
  > let helper' = 41
  > let () = print_int helper'
  > EOP
  $ env -u INSIDE_DUNE litany check --select restricted-export-name 2>&1 | grep -A 1 "tool/main"
  File "tool/main.ml", line 1, characters 4-11:
  1 | let helper' = 41
