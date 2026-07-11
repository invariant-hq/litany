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
  funcmp.ml:3:14 warning invalid-function-comparison
    structural comparison has a function operand
       3 | let broken = compare f g
         |              ^^^^^^^^^^^
  length.ml:1:19 warning needless-list-length
    comparison through List.length is a needless emptiness test
       1 | let is_empty xs = List.length xs = 0
         |                   ^^^^^^^^^^^^^^^^^^
    fix (safe): compare with []
  phys.ml:1:34 warning suspicious-physical-equality
    physical comparison has a non-immediate operand
       1 | let same_object (a : string) b = a == b
         |                                  ^^^^^^
  warnattr.ml:1:1 warning disable-all-warnings
    attribute disables all compiler warnings
       1 | [@@@warning "-a"]
         | ^^^^^^^^^^^^^^^^^
  
  30 rules selected · 6 units · 4 findings (1 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  [1]

Byte-determinism: the same run twice is the same page.

  $ litany check --cmt-root . > first.out 2>&1; litany check --cmt-root . > second.out 2>&1; cmp first.out second.out && echo deterministic
  deterministic
