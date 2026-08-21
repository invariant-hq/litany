The litany config file: discovered at the workspace root, parsed by
litany_config, every mistake a positioned refusal (exit 2, nothing runs).
The fixture is a real nested dune project so the dune adapter builds and
describes it; cram commands run inside dune, so the shell unsets
INSIDE_DUNE exactly as a user's shell has it.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir -p proj/vendor && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name cfglib))
  > EOP
  $ cat > vendor/dune <<'EOP'
  > (library (name cfgvendor))
  > EOP
  $ cat > length.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > EOP
  $ cat > chain.ml <<'EOP'
  > let path = "a" ^ "b" ^ "c" ^ "d"
  > EOP
  $ cat > vendor/vlen.ml <<'EOP'
  > let vendored xs = List.length xs = 0
  > EOP

No config file: the default set runs, and both List.length findings —
workspace and vendored — report.

  $ env -u INSIDE_DUNE litany check 2>&1 | grep -cE "needless-list-length"
  2

Per-path ignore is selection of reports, never of analysis: the vendored
finding disappears, the workspace one stays, and the unit count does not
move — vendor/vlen.ml was analyzed, its report deselected.

  $ cat > litany <<'EOP'
  > (per-path
  >  (paths vendor/**)
  >  (ignore all)
  >  (reason "vendored code"))
  > EOP
  $ env -u INSIDE_DUNE litany check
  File "length.ml", line 1, characters 18-36:
  1 | let is_empty xs = List.length xs = 0
                        ^^^^^^^^^^^^^^^^^^
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  
  30 rules selected · 5 units · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped · 2 facts-only
  [1]
  $ env -u INSIDE_DUNE litany check --list-units | grep vendor/vlen.ml
  unit vendor/vlen.ml (direct)

The file's lint block feeds the same selection as the flags. select
replaces the default set; extend adds to it.

  $ cat > litany <<'EOP'
  > (lint (select quadratic-string-concat-chain))
  > (rule quadratic-string-concat-chain
  >  (max-segments 3))
  > EOP
  $ env -u INSIDE_DUNE litany check
  File "chain.ml", line 1, characters 11-32:
  1 | let path = "a" ^ "b" ^ "c" ^ "d"
                 ^^^^^^^^^^^^^^^^^^^^^
  Warning 0 [quadratic-string-concat-chain]: chained (^) recopies later segments; use String.concat
  
  1 rule selected · 5 units · 1 finding · 0 skipped · 2 facts-only
  [1]

The per-rule option is live: at the default threshold the four-segment
chain fires (above, via (max-segments 3)); raising it to 4 tolerates the
chain and the run is clean.

  $ cat > litany <<'EOP'
  > (lint (select quadratic-string-concat-chain))
  > (rule quadratic-string-concat-chain
  >  (max-segments 4))
  > EOP
  $ env -u INSIDE_DUNE litany check 2>&1 | head -1
  1 rule selected · 5 units · 0 findings · 0 skipped · 2 facts-only
  $ env -u INSIDE_DUNE litany check > /dev/null 2>&1; echo "exit=$?"
  exit=0

Flags override the file — a given --select replaces the file's select and
extend together (the file still validates first; the flag does not turn
errors off), and a given --ignore replaces the file's ignore.

  $ env -u INSIDE_DUNE litany check --select default 2>&1 | grep -E "rules selected|quadratic"
  litany: rule "quadratic-string-concat-chain" is configured but not selected
  30 rules selected · 5 units · 2 findings (2 fixable — run `litany check --fix`) · 0 skipped · 2 facts-only
  $ cat > litany <<'EOP'
  > (lint (ignore needless-list-length))
  > EOP
  $ env -u INSIDE_DUNE litany check 2>&1 | grep -c needless-list-length
  0
  [1]
  $ env -u INSIDE_DUNE litany check --ignore trailing-whitespace 2>&1 | grep -c needless-list-length
  2

A typo is an error with a position and a suggestion, never a silent
fallback — unknown key, unknown rule, an audit name (engine hygiene, not
selection vocabulary), and a malformed rule option all refuse with exit 2.

  $ printf '(lint (selct default))\n' > litany
  $ env -u INSIDE_DUNE litany check
  litany: litany:1:8: unknown key "selct" in (lint ...) (did you mean "select"?)
  [2]
  $ printf '(lint (ignore needless-list-lenght))\n' > litany
  $ env -u INSIDE_DUNE litany check
  litany: litany:1:15: unknown rule or group "needless-list-lenght" (did you mean "needless-list-length"?)
  [2]
  $ printf '(lint (ignore unused-allow))\n' > litany
  $ env -u INSIDE_DUNE litany check
  litany: litany:1:15: "unused-allow" is engine-owned hygiene, not a selectable rule
  [2]
  $ printf '(rule quadratic-string-concat-chain (max-segments zero))\n' > litany
  $ env -u INSIDE_DUNE litany check
  litany: litany:1:51: option "max-segments" wants an integer, not "zero"
  [2]
  $ printf '(rule needless-list-length (max 3))\n' > litany
  $ env -u INSIDE_DUNE litany check
  litany: litany:1:28: rule "needless-list-length" takes no options
  [2]

Restriction rules are house policies over legitimate code, meant to be
cherry-picked by exact name. The group token works uniformly — file and
flag alike — but a bare whole-group mention on the enabling side warns
once; exact-name selection warns nothing.

  $ printf '(lint (extend restriction))\n' > litany
  $ env -u INSIDE_DUNE litany check > /dev/null 2> warn; echo "exit=$?"; cat warn
  exit=1
  litany: restriction rules are independent house policies, and some contradict each other — adopt each by exact name; the group token enables 10 of 10 restriction rules (group tokens cover stable rules only; nursery members need "nursery" or their exact name)
  litany: rule "restricted-dependency" is selected but not configured; it reports nothing without a (rule restricted-dependency ...) form
  litany: rule "restricted-export-name" is selected but not configured; it reports nothing without a (rule restricted-export-name ...) form
  $ printf '(lint (extend unsafe-obj-magic))\n' > litany
  $ env -u INSIDE_DUNE litany check > /dev/null 2> warn; echo "exit=$?"; wc -c < warn | tr -d ' '
  exit=1
  0

all excludes the restriction tier, so the full-catalog audit spells
all,restriction,nursery. It still carries the one cherry-picking note,
plus the selected-but-unconfigured note for each configured policy the
audit runs with no (rule ...) form:

  $ rm litany
  $ env -u INSIDE_DUNE litany check --select all,restriction,nursery > page 2> warn; echo "exit=$?"
  exit=1
  $ cat warn
  litany: restriction rules are independent house policies, and some contradict each other — adopt each by exact name; the group token enables 10 of 10 restriction rules (group tokens cover stable rules only; nursery members need "nursery" or their exact name)
  litany: rule "restricted-dependency" is selected but not configured; it reports nothing without a (rule restricted-dependency ...) form
  litany: rule "restricted-export-name" is selected but not configured; it reports nothing without a (rule restricted-export-name ...) form
  $ grep -oE "[0-9]+ rules selected" page
  80 rules selected
