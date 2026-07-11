Selection and suppression on litany check. Over the launch fixture first:
--select by group turns the off-by-default Style rule on, an exact name
narrows the run to one rule, --ignore drops a rule from the default set,
and an unknown token is a refusal with a suggestion, before anything runs.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ cp -RL ../fixture proj && chmod -R u+w proj && cd proj

  $ litany check --cmt-root . --select style
  ws.ml:1:15 warning trailing-whitespace
    trailing whitespace
       1 | let padded = 1  
         |               ^^
    fix (safe): delete the trailing whitespace
  
  23 rules selected · 6 units · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only
  [1]

  $ litany check --cmt-root . --select needless-list-length
  length.ml:1:19 warning needless-list-length
    comparison through List.length is a needless emptiness test
       1 | let is_empty xs = List.length xs = 0
         |                   ^^^^^^^^^^^^^^^^^^
    fix (safe): compare with []
  
  1 rule selected · 6 units · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only
  [1]

  $ litany check --cmt-root . --ignore needless-list-length
  funcmp.ml:3:14 warning invalid-function-comparison
    structural comparison has a function operand
       3 | let broken = compare f g
         |              ^^^^^^^^^^^
  phys.ml:1:34 warning suspicious-physical-equality
    physical comparison has a non-immediate operand
       1 | let same_object (a : string) b = a == b
         |                                  ^^^^^^
  warnattr.ml:1:1 warning disable-all-warnings
    attribute disables all compiler warnings
       1 | [@@@warning "-a"]
         | ^^^^^^^^^^^^^^^^^
  
  29 rules selected · 6 units · 3 findings · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  [1]

  $ litany check --cmt-root . --select styel
  litany: unknown rule or group "styel" (did you mean "style"?)
  [2]

The audit rules print as rule names in output but are engine hygiene, not
selection vocabulary: pasting one into --ignore refuses honestly instead
of claiming the name is unknown.

  $ litany check --cmt-root . --ignore unused-allow
  litany: "unused-allow" is engine-owned hygiene, not a selectable rule
  [2]

  $ litany check --cmt-root . --select all --ignore perf,style
  funcmp.ml:3:14 warning invalid-function-comparison
    structural comparison has a function operand
       3 | let broken = compare f g
         |              ^^^^^^^^^^^
  phys.ml:1:34 warning suspicious-physical-equality
    physical comparison has a non-immediate operand
       1 | let same_object (a : string) b = a == b
         |                                  ^^^^^^
  warnattr.ml:1:1 warning disable-all-warnings
    attribute disables all compiler warnings
       1 | [@@@warning "-a"]
         | ^^^^^^^^^^^^^^^^^
  
  28 rules selected · 6 units · 3 findings · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-transposable-arguments withheld (kind-gated; no unit in this lane carries a stanza kind)
  [1]

Now the allow-carrying fixture: the working allow hides its finding but
counts in the summary, the stale allow is an unused-allow finding at the
attribute, and ignoring the rule gates both audits off (the rule did not
run, so absence proves nothing).

  $ cd .. && cp -RL ../fixture_allow proj2 && chmod -R u+w proj2 && cd proj2

  $ litany check --cmt-root .
  allowed.ml:2:21 warning needless-list-length
    comparison through List.length is a needless emptiness test
       2 | let also_empty xs = List.length xs = 0
         |                     ^^^^^^^^^^^^^^^^^^
    fix (safe): compare with []
  allowed.ml:3:14 warning unused-allow
    allow "needless-list-length" matched no finding
       3 | let fine = 1 [@@litany.allow "needless-list-length: stale"]
         |              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    fix (safe): delete the unused allow
  
  30 rules selected · 2 units · 2 findings (2 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only · 1 suppressed
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  [1]

  $ litany check --cmt-root . --ignore needless-list-length
  29 rules selected · 2 units · 0 findings · 0 skipped · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)

Byte-determinism: the same run twice is the same page.

  $ litany check --cmt-root . > first.out 2>&1; litany check --cmt-root . > second.out 2>&1; cmp first.out second.out && echo deterministic
  deterministic
