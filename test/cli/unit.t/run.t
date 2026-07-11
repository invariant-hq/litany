The in-build lane: litany unit lints exactly one unit — its argv is the
roster, no subprocess, no lock. Findings go to stderr in the compiler
format with stdout completely silent; exit 1 is the gate. The fixture is
a real dune project built in the sandbox.

  $ PARSE=$PWD/../../vendor_ocamlc_loc/parse.exe
  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.21)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name unitlib))
  > EOP
  $ cat > inv.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > let rest xs = List.tl xs
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null
  $ CMT=_build/default/.unitlib.objs/byte/unitlib__Inv.cmt

The gate: stderr carries the report, stdout nothing, exit 1 on findings.

  $ litany unit inv --cmt $CMT --source inv.ml > gate.stdout 2> gate.stderr; echo "exit=$?"
  exit=1
  $ cat gate.stdout
  $ cat gate.stderr
  File "inv.ml", line 1, characters 18-36:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []

The stream parses in dune's own vendored ocamlc-loc parser — what litany
emits is what the editor pipeline receives.

  $ $PARSE < gate.stderr
  inv.ml:1:18-36 warning 0 [needless-list-length] "comparison through List.length is a needless emptiness test\nfix (safe): compare with []"

A unit that cannot be admitted is a refusal naming the skip, never a
silent clean gate.

  $ printf '(* edited after the build *)\n' >> inv.ml
  $ litany unit inv --cmt $CMT --source inv.ml
  litany: cannot lint inv.ml: stale — the source changed since the compiler read it
  [2]
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null

A suppressed finding never reaches the gate: with the allow attribute the
report is empty and the exit is clean.

  $ cat > inv.ml <<'EOP'
  > let is_empty xs = (List.length xs = 0) [@litany.allow "needless-list-length: teaching example"]
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null
  $ litany unit inv --cmt $CMT --source inv.ml 2>&1; echo "exit=$?"
  exit=0
