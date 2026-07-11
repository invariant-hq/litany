(* Fixture for unsafe-obj-magic: positives carry the FIRE marker; every
   other line is a negative lookalike ported from the prior implementation's cases. *)

(* Direct call: the finding lands at the identifier itself, once — the
   surrounding application never fires on its own. *)
let coerce (x : int) : string = Obj.magic x (* FIRE *)

(* Opened use resolves to the same declaration. *)
let opened (x : int) : string =
  let open Obj in
  magic x (* FIRE *)

(* A first-class reference fires at the reference. *)
let first_class : int -> string = Obj.magic (* FIRE *)

(* The alias initializer fires; the later use of the alias is a different
   identity and stays clean. *)
let alias : int -> string = Obj.magic (* FIRE *)
let through_alias (x : int) : string = alias x

(* A module alias resolves through to Stdlib.Obj. *)
module O = Obj

let via_module_alias (x : int) : string = O.magic x (* FIRE *)

(* Other canonical Obj members stay clean. *)
let representation (x : int) = Obj.repr x

(* Shadowing (adversarial): a same-spelling local module mints its own
   identities, so its magic is not Stdlib.Obj.magic. *)
module Shadow = struct
  module Obj = struct
    let magic x = x
  end

  let same (x : int) : int = Obj.magic x
end
