The interface text lane — a pinned case: a trailing-whitespace mli with
no final newline. A module's paired .mli is text-linted exactly as its .ml is
— the walk names the editable mli on the unit's entry, source rules run
over it, and findings anchor in the mli itself. The fixture's
implementation is clean; its interface carries a trailing tab and no final
newline.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ cp -RL ../fixture_mli proj && chmod -R u+w proj && cd proj

Both text rules fire on the interface file (missing-final-newline is
Nursery, so exact names select the pair). The implementation contributes
nothing — iface.ml is clean.

  $ litany check --cmt-root . --select trailing-whitespace,missing-final-newline
  File "iface.mli", line 1, characters 13-14:
  1 | val eof : int	
                   ^
  Warning 0 [trailing-whitespace]: trailing whitespace
    fix (safe): delete the trailing whitespace
    
  File "iface.mli", line 1, characters 14-14:
  1 | val eof : int	
                    ^
  Warning 0 [missing-final-newline]: file does not end with LF
    fix (safe): add a final newline
  
  2 rules selected · 2 units · 2 findings (2 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only
  [1]

--fix rewrites the mli under its own write baseline (the applying run
simulates the user's shell with env -u INSIDE_DUNE): the tab goes, the
final newline arrives, and a re-run is clean — the unit's witness is the
implementation's, so fixing the mli stales nothing.

  $ env -u INSIDE_DUNE litany check --cmt-root . --select trailing-whitespace,missing-final-newline --fix
  fix iface.mli: 2 applied
  pass 1: 2 fixes applied (1 file)
  2 fixes applied — artifacts are now stale; rebuild and re-run to converge
  File "iface.mli", line 1, characters 13-14:
  1 | val eof : int	
                   ^
  Warning 0 [trailing-whitespace]: trailing whitespace
    fix (safe): delete the trailing whitespace
    
  File "iface.mli", line 1, characters 14-14:
  1 | val eof : int	
                    ^
  Warning 0 [missing-final-newline]: file does not end with LF
    fix (safe): add a final newline
  
  2 rules selected · 2 units · 2 findings (2 fixable) · 2 fixes applied · 0 skipped · 1 facts-only
  [1]
  $ od -c iface.mli
  0000000    v   a   l       e   o   f       :       i   n   t  \n        
  0000016
  $ litany check --cmt-root . --select trailing-whitespace,missing-final-newline
  2 rules selected · 2 units · 0 findings · 0 skipped · 1 facts-only
