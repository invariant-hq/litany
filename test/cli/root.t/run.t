The dune lane pins dune's root to the directory litany was pointed at
(--root . with the child's cwd there): without it, dune root-walks upward
and a workspace nested under another dune project resolves to the outer
one, dying on "Don't know about directory" — litany's --root promise
silently broken. A shim dune on PATH records the argv litany
spawns; both spawns must carry --root.

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

The describe spawn (--no-build skips the build):

  $ ARGLOG=$PWD/args.log PATH=$PWD/shim:$PATH env -u INSIDE_DUNE litany check --root proj --no-build
  litany: dune describe failed: shim-refused
  [2]

Both argvs carried --root:

  $ cat args.log
  build --root . @check
  describe workspace --format csexp --lang 0.1 --root .
