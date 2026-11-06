Every way a run can refuse says so in its own words. Each is an input a user
can reach.

  $ unset GITHUB_ACTIONS INSIDE_DUNE
  $ litany=$(command -v litany)
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name l))
  > EOP
  $ printf 'let a = 1   \n' > a.ml
  $ dune build --root . @check 2>/dev/null

No dune on PATH, and the two ways of naming a roster at once.

  $ (PATH=/nonexistent "$litany" check)
  litany: dune is not on PATH. Pass --cmt-root DIR to lint artifacts built elsewhere.
  [2]
  $ litany check --cmt-root _build/default --units a.units
  litany: --cmt-root and --units both name a roster source; pass one
  [2]

The JSON page's roster states a project rule's disposition.

  $ litany check --select unused-export --no-build --format json | tail -1 | grep -o '"roster":\[{"rule":"unused-export","state":"[a-z-]*"'
  "roster":[{"rule":"unused-export","state":"ran"
  $ litany check --select unused-export --cmt-root _build/default --format json | tail -1 | grep -o '"roster":\[{"rule":"unused-export","state":"[a-z-]*"'
  "roster":[{"rule":"unused-export","state":"unavailable"
