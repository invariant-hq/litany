The dune lane pins dune's root to the directory litany was pointed at
(--root . with the child's cwd there): without it, dune root-walks upward
and a workspace nested under another dune project resolves to the outer
one, dying on "Don't know about directory" — litany's --root promise
silently broken. A shim dune on PATH records the argv litany
spawns; the build — the one dune subprocess — must carry --root.

  $ mkdir shim proj
  $ cat > shim/dune <<'SH'
  > #!/bin/sh
  > echo "$@" >> "$ARGLOG"
  > echo shim-refused >&2
  > exit 1
  > SH
  $ chmod +x shim/dune

The build spawn (the shim's failure classifies as an ordinary build
failure — exit 2, nothing runs after it):

  $ ARGLOG=$PWD/args.log PATH=$PWD/shim:$PATH env -u INSIDE_DUNE litany check --root proj
  shim-refused
  litany: dune build @check failed; its errors are above. Lint presupposes a building project.
  [2]

--no-build spawns nothing at all: the roster is read straight from the
build tree, so an empty project is an empty, complete run — and the shim
records no second argv:

  $ ARGLOG=$PWD/args.log PATH=$PWD/shim:$PATH env -u INSIDE_DUNE litany check --root proj --no-build
  30 rules selected · 0 units · 0 findings · 0 skipped

The one argv carried --root:

  $ cat args.log
  build --root . @check
