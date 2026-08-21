check --format selects the report surface: text (the default — the report
page: finding blocks in the grammar dune's diagnostic parser accepts,
excerpts and carets between header and severity line as ocamlc prints
them, then one summary line), json (JSON Lines plus one summary trailer),
github (workflow annotations, auto-selected under GITHUB_ACTIONS). The
text page is proved through dune's own vendored ocamlc-loc parser. The
fixture is a real nested dune project.

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

text: the whole page rides stdout with stderr silent — dune gates on the
combined stream starting with "File " — exit 1 on findings. --no-build
keeps stderr pure.

  $ env -u INSIDE_DUNE litany check --no-build > page.out 2> page.err; echo "exit=$?"
  exit=1
  $ wc -c < page.err | tr -d ' '
  0
  $ cat page.out
  File "length.ml", line 1, characters 18-36:
  1 | let is_empty xs = List.length xs = 0
                        ^^^^^^^^^^^^^^^^^^
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  
  30 rules selected · 3 units · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only

The page parses in dune's vendored lexer — what litany emits is what the
editor pipeline receives: the excerpt is skipped as ocamlc's own, the
fix line folds into the message, and the summary (everything up to the
next header, which there is none of) folds into the last finding's
message rather than ending the stream. No ANSI into a pipe, so the
bytes are the parser's.

  $ $PARSE < page.out
  length.ml:1:18-36 warning 0 [needless-list-length] "comparison through List.length is a needless emptiness test\n  fix (safe): compare with []\n\n30 rules selected \194\183 3 units \194\183 1 finding (1 fixable \226\128\148 run `litany check --fix`) \194\183 0 skipped \194\183 1 facts-only"

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
  $ env -u INSIDE_DUNE litany check --no-build --format github --list-units
  litany: --format github renders the report page only; --list-units speaks the text surface
  [2]

There is no separate compiler format: the text page is the one dune
parses.

  $ env -u INSIDE_DUNE litany check --no-build --format compiler 2>&1 | grep -c "expected one of"
  1
  $ env -u INSIDE_DUNE litany check --no-build --format compiler 2>/dev/null; echo "exit=$?"
  exit=2

A clean report: text is the summary line alone, github zero annotations,
json the trailer alone — exit 0.

  $ env -u INSIDE_DUNE litany check --no-build --ignore needless-list-length; echo "exit=$?"
  29 rules selected · 3 units · 0 findings · 0 skipped · 1 facts-only
  exit=0
  $ env -u INSIDE_DUNE litany check --no-build --format github --ignore needless-list-length; echo "exit=$?"
  exit=0
  $ env -u INSIDE_DUNE litany check --no-build --format json --ignore needless-list-length; echo "exit=$?"
  {"summary":{"schema":1,"rules_selected":29,"findings":0,"fixable":0,"units":3,"linted":2,"facts_only":1,"suppressed":0,"skipped":[],"failures":[],"degraded":[],"notes":[{"path":"_build/default/fmtlib.ml-gen","note":"generated (path ends in .ml-gen) — facts-only"}],"dropped":0,"roster":[],"exit":0}}
  exit=0
