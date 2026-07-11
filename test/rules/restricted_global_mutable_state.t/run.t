The restricted-global-mutable-state cram: the kind gate end to end — a
nested dune project with a library and an executable, the same toplevel
ref in both, selection by exact name. The fixture is built for real
inside the sandbox; cram commands run inside dune, so the shell unsets
INSIDE_DUNE exactly as a user's shell has it.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir -p proj/lib proj/bin && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > lib/dune <<'EOP'
  > (library (name statelib))
  > EOP
  $ cat > lib/statelib.ml <<'EOP'
  > let counter = ref 0
  > let registry : (string, int) Hashtbl.t = Hashtbl.create 16
  > 
  > type state = { mutable hits : int }
  > 
  > let stats = { hits = 0 }
  > 
  > let tick () =
  >   let c = ref 0 in
  >   incr c;
  >   !c
  > 
  > let table : (string, int) Hashtbl.t lazy_t = lazy (Hashtbl.create 16)
  > EOP
  $ cat > bin/dune <<'EOP'
  > (executable (name main))
  > EOP
  $ cat > bin/main.ml <<'EOP'
  > let counter = ref 0
  > 
  > let () =
  >   incr counter;
  >   print_int !counter
  > EOP

Selected by exact name — the rule is Restriction, outside default and
all, so only the exact name runs it. The library's toplevel ref, table,
and mutable-record global fire; its local ref and lazy cache stay
clean; and the executable's byte-identical toplevel ref never fires —
executables own their process.

  $ env -u INSIDE_DUNE litany check --select restricted-global-mutable-state
  lib/statelib.ml:1:5 warning restricted-global-mutable-state
    toplevel mutable state in a library is a process-wide global; create it in the caller and pass it down
       1 | let counter = ref 0
         |     ^^^^^^^
  lib/statelib.ml:2:5 warning restricted-global-mutable-state
    toplevel mutable state in a library is a process-wide global; create it in the caller and pass it down
       2 | let registry : (string, int) Hashtbl.t = Hashtbl.create 16
         |     ^^^^^^^^
  lib/statelib.ml:6:5 warning restricted-global-mutable-state
    toplevel mutable state in a library is a process-wide global; create it in the caller and pass it down
       6 | let stats = { hits = 0 }
         |     ^^^^^
  
  1 rule selected · 2 units · 3 findings · 0 skipped
  [1]

