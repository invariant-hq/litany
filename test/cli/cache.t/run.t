M8 cache: litany check keys each unit's result on (cmt digest, source
digest, config fingerprint, selected-rule set, binary digest) and replays
hits through the same assembly path as fresh analysis, so a warm page is
byte-identical to a cold one by construction. The cache is advisory and
silent; --cache-stats puts one diagnostic line on standard error.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS
  $ export LITANY_CACHE_DIR=$PWD/lcache

  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name clib))
  > EOP
  $ cat > alpha.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > EOP
  $ cat > beta.ml <<'EOP'
  > let beta = 41 + 1
  > EOP
  $ cat > gamma.ml <<'EOP'
  > let also_empty xs = List.length xs = 0
  > EOP

A cold run misses every admitted unit and stores its results: the three
modules plus the library's generated alias module (facts-only units cache
too — their classification is part of the result).

  $ env -u INSIDE_DUNE litany check --cache-stats > cold.page 2> cold.err
  [1]
  $ grep '^litany: cache:' cold.err
  litany: cache: 0 hits, 4 misses, 4 stored, 0 evicted

A warm run hits all four and stores nothing — and its page is the cold
page, byte for byte.

  $ env -u INSIDE_DUNE litany check --cache-stats > warm.page 2> warm.err
  [1]
  $ grep '^litany: cache:' warm.err
  litany: cache: 4 hits, 0 misses, 0 stored, 0 evicted
  $ cmp cold.page warm.page

The parallel lane shares the same cache: workers hit the entries the
serial run stored, and the page still compares equal.

  $ env -u INSIDE_DUNE litany check -j 3 --cache-stats > warm-j3.page 2> warm-j3.err
  [1]
  $ grep '^litany: cache:' warm-j3.err
  litany: cache: 4 hits, 0 misses, 0 stored, 0 evicted
  $ cmp cold.page warm-j3.page

Editing one source invalidates exactly that unit: one miss recomputes and
stores, the rest still hit.

  $ cat > beta.ml <<'EOP'
  > let beta = 40 + 2
  > EOP
  $ env -u INSIDE_DUNE litany check --cache-stats > edit.page 2> edit.err
  [1]
  $ grep '^litany: cache:' edit.err
  litany: cache: 3 hits, 1 misses, 1 stored, 0 evicted

The config fingerprint is a key component: any change to the litany file
invalidates every entry — here a per-path ignore, which also changes the
report (selection of reports, never of analysis).

  $ cat > litany <<'EOP'
  > (per-path
  >  (paths gamma.ml)
  >  (ignore all)
  >  (reason "demo"))
  > EOP
  $ env -u INSIDE_DUNE litany check --cache-stats > cfg.page 2> cfg.err
  [1]
  $ grep '^litany: cache:' cfg.err
  litany: cache: 0 hits, 4 misses, 4 stored, 0 evicted
  $ grep -c "needless-list-length" cold.page
  2
  $ grep -c "needless-list-length" cfg.page
  1

The selected-rule set is a key component too.

  $ env -u INSIDE_DUNE litany check --select correctness --cache-stats > sel.page 2> sel.err
  $ grep '^litany: cache:' sel.err
  litany: cache: 0 hits, 4 misses, 4 stored, 0 evicted

--no-cache runs uncached: nothing is read, stored, or swept, and no stats
line prints; the page is still the same bytes.

  $ env -u INSIDE_DUNE litany check --no-cache --cache-stats > nc.page 2> nc.err
  [1]
  $ grep -c '^litany: cache:' nc.err
  0
  [1]
  $ cmp cfg.page nc.page

--cache-dir overrides the environment: a fresh directory is a cold cache.

  $ env -u INSIDE_DUNE litany check --cache-dir $PWD/other --cache-stats > od.page 2> od.err
  [1]
  $ grep '^litany: cache:' od.err
  litany: cache: 0 hits, 4 misses, 4 stored, 0 evicted
  $ test -d other
