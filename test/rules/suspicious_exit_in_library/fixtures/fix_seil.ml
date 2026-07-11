(* Fixture for suspicious-exit-in-library: each marked line is a value
   reference resolving to Stdlib.exit; every other line is a negative
   from the spec plus one adversarial extra. The kind gate is roster
   metadata, so the suite runs this one artifact under Library (fires),
   Executable, Test, and no kind (all silent). *)

(* Direct and qualified references. *)
let bail bad = if bad then exit 1 else 0 (* FIRE *)
let stop () : unit = Stdlib.exit 2 (* FIRE *)

(* Aliasing an exit is an exit: the reference itself fires; the alias's
   own uses resolve locally and do not. *)
let die = exit (* FIRE *)
let use_die () : unit = die 3

(* raise Exit constructs the Stdlib.Exit exception — a constructor, not
   a value reference to Stdlib.exit. *)
let lookalike () = raise Exit

(* at_exit is a different declaration. *)
let register cleanup = at_exit cleanup

(* Shadowing: a local exit resolves to a local declaration. *)
let shadowed () =
  let exit code = Error code in
  exit 3

(* Adversarial extra: a same-spelled function from a local module. *)
module Proc = struct
  let exit _ = ()
end

let local_exit () = Proc.exit 1
