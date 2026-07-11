check --format selects the report surface: compiler (the exact grammar
dune's diagnostic parser accepts, on stderr), json (JSON Lines plus one
summary trailer), github (workflow annotations, auto-selected under
GITHUB_ACTIONS). The compiler stream is proved through dune's own vendored
ocamlc-loc parser. The fixture is a real nested dune project.

  $ unset GITHUB_ACTIONS
  $ PARSE=$PWD/../../vendor_ocamlc_loc/parse.exe
  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name fmtlib))
  > EOP
  $ cat > length.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > EOP
  $ cat > clean.ml <<'EOP'
  > let double x = x + x
  > EOP
  $ env -u INSIDE_DUNE dune build --root . @check 2>/dev/null

compiler: the report rides stderr with stdout completely silent (dune
gates on the combined stream starting with "File "), exit 1 on findings.
--no-build keeps stderr pure — nothing but the report.

  $ env -u INSIDE_DUNE litany check --no-build --format compiler > page.out 2> page.err; echo "exit=$?"
  exit=1
  $ wc -c < page.out | tr -d ' '
  0
  $ cat page.err
  File "length.ml", line 1, characters 18-36:
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []

The stream parses in dune's vendored lexer — what litany emits is what
the editor pipeline receives.

  $ $PARSE < page.err
  length.ml:1:18-36 warning 0 [needless-list-length] "comparison through List.length is a needless emptiness test\nfix (safe): compare with []"

json: one finding object per line on stdout in report order, then the
summary trailer. CI reads the trailer; bots read the fix edits.

  $ env -u INSIDE_DUNE litany check --no-build --format json; echo "exit=$?"
  {"rule":"needless-list-length","severity":"warning","file":"length.ml","line":1,"col":18,"end_line":1,"end_col":36,"message":"comparison through List.length is a needless emptiness test","fix":{"title":"compare with []","applicability":"safe","edits":[{"start":18,"stop":36,"text":"xs = []"}]}}
  {"summary":{"schema":1,"rules_selected":30,"findings":1,"fixable":1,"units":3,"linted":2,"facts_only":1,"suppressed":0,"skipped":[],"failures":[],"degraded":[],"notes":[{"path":"_build/default/fmtlib.ml-gen","note":"generated (path ends in .ml-gen) — facts-only"}],"dropped":0,"roster":[],"exit":1}}
  exit=1

github: workflow annotations — 1-based columns, the fix appended to the
message.

  $ env -u INSIDE_DUNE litany check --no-build --format github; echo "exit=$?"
  ::warning file=length.ml,line=1,col=19,endColumn=37,title=needless-list-length::comparison through List.length is a needless emptiness test fix (safe): compare with []
  exit=1

GITHUB_ACTIONS auto-selects github when no --format is given; an explicit
--format still wins (the auto-selection is a default, not a mandate).

  $ GITHUB_ACTIONS=true env -u INSIDE_DUNE litany check --no-build; echo "exit=$?"
  ::warning file=length.ml,line=1,col=19,endColumn=37,title=needless-list-length::comparison through List.length is a needless emptiness test fix (safe): compare with []
  exit=1
  $ GITHUB_ACTIONS=true env -u INSIDE_DUNE litany check --no-build --format text | grep "rules selected"
  30 rules selected · 3 units · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only

The machine formats render the report page only; the fix narration and
the admission listing speak the text surface.

  $ env -u INSIDE_DUNE litany check --no-build --format json --fix
  litany: --format json renders the report page only; --fix speaks the text surface
  [2]
  $ env -u INSIDE_DUNE litany check --no-build --format compiler --list-units
  litany: --format compiler renders the report page only; --list-units speaks the text surface
  [2]

A clean report: compiler renders zero bytes on both streams, github zero
annotations, json the trailer alone — exit 0.

  $ env -u INSIDE_DUNE litany check --no-build --format compiler --ignore needless-list-length 2>&1; echo "exit=$?"
  exit=0
  $ env -u INSIDE_DUNE litany check --no-build --format github --ignore needless-list-length; echo "exit=$?"
  exit=0
  $ env -u INSIDE_DUNE litany check --no-build --format json --ignore needless-list-length; echo "exit=$?"
  {"summary":{"schema":1,"rules_selected":29,"findings":0,"fixable":0,"units":3,"linted":2,"facts_only":1,"suppressed":0,"skipped":[],"failures":[],"degraded":[],"notes":[{"path":"_build/default/fmtlib.ml-gen","note":"generated (path ends in .ml-gen) — facts-only"}],"dropped":0,"roster":[],"exit":0}}
  exit=0
