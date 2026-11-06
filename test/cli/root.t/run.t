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
build tree, so a never-built project is an honest refusal — silence must
not read as cleanliness — and the shim records no second argv:

  $ ARGLOG=$PWD/args.log PATH=$PWD/shim:$PATH env -u INSIDE_DUNE litany check --root proj --no-build
  litany: no build tree at _build/default: litany reads the default context's artifacts. Build first (or drop --no-build); a workspace that renames its default context is not supported.
  [2]

The one argv carried --root:

  $ cat args.log
  build --root . @check

A dune on PATH that cannot be started is a refusal that says so, not an
internal error:

  $ mkdir unusable
  $ printf '#!/bin/sh\n' > unusable/dune
  $ chmod 644 unusable/dune
  $ litany=$(command -v litany)
  $ (unset INSIDE_DUNE; PATH=$PWD/unusable "$litany" check --root proj 2>&1) | sed 's/Permission denied/DENIED/'
  litany: dune could not be started: DENIED. Fix the dune on PATH, or pass --cmt-root DIR to lint artifacts built elsewhere.

--root enters the workspace: from anywhere, paths print and globs match as
they do at its root, and what was named on the command line still means what
it meant where it was typed.

  $ mkdir -p work/lib
  $ cat > work/dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > work/lib/dune <<'EOP'
  > (library (name l))
  > EOP
  $ cat > work/lib/a.ml <<'EOP'
  > let x = print_endline "a"
  > EOP
  $ cat > work/litany <<'EOP'
  > (rule restricted-dependency
  >  (forbid Stdlib.print_endline (use "a logger") (only "lib/**")))
  > EOP
  $ env -u INSIDE_DUNE dune build --root work @check 2>/dev/null
  $ env -u INSIDE_DUNE litany check --root work --no-build --select restricted-dependency | grep -c '^File "lib/a.ml"'
  1
  $ env -u INSIDE_DUNE litany check --root $PWD/work --cmt-root work/_build/default/lib --select restricted-dependency | grep -c '^File "lib/a.ml"'
  1
