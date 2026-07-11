The catalog table: litany rules lists every built-in rule from the same
Rule.meta declarations the engine runs — there is nothing else to read, so
the table cannot drift from behavior.

One row per rule: name, group, stability tier, fix promise, default state,
one-line summary. Three rows prove the default-state law — on requires
stable AND a default group (correctness, suspicious, perf):

  $ litany rules | grep -E "^needless-list-length "
  needless-list-length                      perf         stable   sometimes  on   List.length compared with 0 or 1 to test emptiness

A stable rule outside the default groups is off:

  $ litany rules | grep -E "^trailing-whitespace "
  trailing-whitespace                       style        stable   always     off  trailing spaces or tabs at end of line

And a nursery rule is off even inside a default group:

  $ litany rules | grep -E "^used-underscore-binding "
  used-underscore-binding                   suspicious   nursery  never      off  underscore-prefixed binding is used

A restriction rule is house policy over legitimate code — off, outside
all, cherry-picked by exact name:

  $ litany rules | grep -E "^ignored-result "
  ignored-result                            restriction  stable   never      off  result or option value is discarded by a wildcard binding

The summary counts the whole catalog, names the default-set law, and
names the cherry-picked tier (restriction is outside all):

  $ litany rules | tail -1
  80 rules · 30 on by default (stable correctness, suspicious, perf) · 10 restriction (cherry-picked; outside all) · 12 nursery

One line per rule plus the summary — the table and the count cannot
disagree:

  $ litany rules | wc -l | tr -d ' '
  81
  $ litany rules > /dev/null 2> rules.err; echo "exit=$?"; wc -c < rules.err | tr -d ' '
  exit=0
  0
