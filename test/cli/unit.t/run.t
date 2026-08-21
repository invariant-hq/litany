The in-build lane: litany unit lints exactly one unit — its argv is the
roster, no subprocess, no lock. The report page goes to stdout — the
same page as litany check, whose finding blocks are the grammar dune's
diagnostic parser accepts from a failing action; exit 1 is the gate. The
fixture is a real dune project built in the sandbox.

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

The gate: stdout carries the page, stderr nothing, exit 1 on findings.

  $ litany unit inv --cmt $CMT --source inv.ml > gate.stdout 2> gate.stderr; echo "exit=$?"
  exit=1
  $ cat gate.stderr
  $ cat gate.stdout
  File "inv.ml", line 1, characters 18-36:
  1 | let is_empty xs = List.length xs = 0
                        ^^^^^^^^^^^^^^^^^^
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  
  30 rules selected · 1 unit · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)

The page parses in dune's own vendored ocamlc-loc parser — what litany
emits is what the editor pipeline receives. The excerpt is skipped as
ocamlc's own; the lines after the last block fold into its message, as
the parser folds everything up to the next header.

  $ $PARSE < gate.stdout
  inv.ml:1:18-36 warning 0 [needless-list-length] "comparison through List.length is a needless emptiness test\n  fix (safe): compare with []\n\n30 rules selected \194\183 1 unit \194\183 1 finding (1 fixable \226\128\148 run `litany check --fix`) \194\183 0 skipped\nroster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)\nroster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)"

A unit that cannot be admitted is a refusal naming the skip, never a
silent clean gate.

  $ printf '(* edited after the build *)\n' >> inv.ml
  $ litany unit inv --cmt $CMT --source inv.ml
  litany: cannot lint inv.ml: stale — the source changed since the compiler read it
  [2]
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null

A suppressed finding never reaches the gate: with the allow attribute the
page is the summary alone and the exit is clean.

  $ cat > inv.ml <<'EOP'
  > let is_empty xs = (List.length xs = 0) [@litany.allow "needless-list-length: teaching example"]
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null
  $ litany unit inv --cmt $CMT --source inv.ml 2>&1; echo "exit=$?"
  30 rules selected · 1 unit · 0 findings · 0 skipped · 1 suppressed
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=0
