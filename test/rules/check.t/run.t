litany check with the default rule set over a workspace holding one positive
per rule. Group is policy: trailing-whitespace (Style) is off by default, so
ws.ml stays quiet here — the rule is exercised engine-side by its own suite
and becomes CLI-reachable with selection (M4). The fixture is copied out
(dereferencing the sandbox's links) so nothing writes through dep copies.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ cp -RL ../fixture proj && chmod -R u+w proj && cd proj

The report: findings in the total order (path, offset, rule), each with its
caret excerpt, then the summary line. Exit 1 — findings, no failures.

  $ litany check --cmt-root .
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
  
  30 rules selected · 6 units · 4 findings (1 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  [1]

Byte-determinism: the same run twice is the same page.

  $ litany check --cmt-root . > first.out 2>&1; litany check --cmt-root . > second.out 2>&1; cmp first.out second.out && echo deterministic
  deterministic
