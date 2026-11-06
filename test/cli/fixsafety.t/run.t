What --fix must never do to the files it writes. Each project is a real dune
project, built again after the fix: a fix that breaks the build, changes what
a file's owner may do with it, or is refused for no fault of the source is a
bug in litany.

  $ unset GITHUB_ACTIONS INSIDE_DUNE
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name l) (flags (:standard -w -14)))
  > EOP
  $ cat > litany <<'EOP'
  > (lint (select trailing-whitespace redundant-if-bool))
  > EOP

A file's permission bits survive, whatever the umask would clear.

  $ printf 'let a = 1   \n' > perms.ml
  $ chmod 664 perms.ml
  $ umask 022
  $ litany check --fix > /dev/null
  $ ls -l perms.ml | cut -c1-10
  -rw-rw-r--

An interface is read as an interface: a module or class declaration is no
implementation, and must not be refused as unparsable.

  $ printf 'let b = 1\nmodule M = struct end\n' > intf.ml
  $ printf 'val b : int\nmodule M : sig end   \n' > intf.mli
  $ litany check --fix | grep -c 'does not parse'
  0
  [1]
  $ grep -c ' $' intf.mli
  0
  [1]

Reparsing a source prints nothing of the compiler's: a warning in the file
being fixed is the build's to report.

  $ printf 'let s = "\\q"   \n' > warned.ml
  $ dune build --root . 2>/dev/null
  $ litany check --fix 2>&1 | grep -c '_none_'
  0
  [1]

A bracket inside a character literal or a comment is no bracket: the operand
stays wrapped, and the project still builds.

  $ cat > brackets.ml <<'EOF'
  > let g b = not b
  > let a = g (if [ '(' ] = [ ')' ] then true else false)
  > let c = g (if (1 (* ( *)) = (2 (* ) *)) then true else false)
  > EOF
  $ litany check --fix > /dev/null
  $ cat brackets.ml
  let g b = not b
  let a = g (([ '(' ] = [ ')' ]))
  let c = g (((1 (* ( *)) = (2 (* ) *))))
  $ dune build --root . 2>&1 | grep -v 'Entering directory\|Leaving directory'
  [1]
