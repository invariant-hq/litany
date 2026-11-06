What --fix must never do to the files it writes. Each project is a real dune
project, built again after the fix: a fix that breaks the build, changes what
a file's owner may do with it, or is refused for no fault of the source is a
bug in litany.

  $ unset GITHUB_ACTIONS INSIDE_DUNE
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name l) (flags (:standard -w -a)))
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

Whitespace inside a string is the string: no finding, and no fix to change it.

  $ printf 'let t = "one   \ntwo"\nlet q = {|one   \ntwo|}\n' > literal.ml
  $ cp literal.ml literal.before
  $ dune build --root . 2>/dev/null
  $ litany check --fix > /dev/null
  $ cmp literal.ml literal.before

A fix that writes a name is safe only where the name is the standard library's.
Here it is, so plain --fix applies it:

  $ cat > litany <<'EOP'
  > (lint (select redundant-nested-if manual-option-map manual-result-map manual-option-value redundant-option-comparison))
  > EOP
  $ cat > plain.ml <<'EOF'
  > let launched = ref 0
  > let f x y = if x then if y then incr launched
  > let g o = match o with Some x -> Some (x + 1) | None -> None
  > EOF
  $ dune build --root . 2>/dev/null
  $ litany check --fix > /dev/null
  $ cat plain.ml
  let launched = ref 0
  let f x y = if x && y then incr launched
  let g o = Option.map (fun x -> (x + 1)) o

Here something else binds it, so plain --fix leaves it, and --unsafe still can:

  $ cat > shadow.ml <<'EOF'
  > let ( && ) a b = a || b
  > let launched = ref 0
  > let f x y = if x then if y then incr launched
  > EOF
  $ cat > option_shadow.ml <<'EOF'
  > module Option = struct let map _ _ = None let unused = 0 end
  > let g o = match o with Some x -> Some (x + 1) | None -> None
  > EOF
  $ dune build --root . 2>/dev/null
  $ litany check --fix --no-build | grep -c 'collapse\|rewrite with Option.map'
  2
  $ cat shadow.ml option_shadow.ml
  let ( && ) a b = a || b
  let launched = ref 0
  let f x y = if x then if y then incr launched
  module Option = struct let map _ _ = None let unused = 0 end
  let g o = match o with Some x -> Some (x + 1) | None -> None

So does an open that supplies it:

  $ cat > supplier.ml <<'EOF'
  > module Option = struct let map _ _ = None end
  > EOF
  $ cat > opened.ml <<'EOF'
  > open Supplier
  > let g o = match o with Some x -> Some (x + 1) | None -> None
  > EOF
  $ dune build --root . 2>/dev/null
  $ litany check --fix --no-build > /dev/null
  [1]
  $ cat opened.ml
  open Supplier
  let g o = match o with Some x -> Some (x + 1) | None -> None

A constructor chosen by its expected type stays where the type reaches it:

  $ cat > clash.ml <<'EOF'
  > type t = A | B
  > type u = A | C
  > let f (o : int option) : t option = match o with Some _x -> Some A | None -> None
  > let _ = (B, C)
  > EOF
  $ dune build --root . 2>/dev/null
  $ litany check --fix --no-build > /dev/null
  [1]
  $ sed -n 3p clash.ml
  let f (o : int option) : t option = match o with Some _x -> Some A | None -> None
  $ dune build --root . 2>&1 | grep -c Error
  0
  [1]

