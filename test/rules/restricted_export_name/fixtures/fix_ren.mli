(* Interface for the mli-backed fixture: what this file names is the
   export surface — the rule fires only on names spelled here, anchored
   in the implementation. *)

val parse' : int -> int
(* negative: the forbidden suffix mid-name — a name must END with it. *)

val x'y : int
(* negative: exactly at the (max-underscores 3) limit. *)

val a_b_c_d : int
val a_b_c_d_e : int
external refl' : int -> int = "%identity"

type t'
type meta = { tag : int }

(* negative: module names are outside the claim (values and types), and
   the member is a submodule export — a recorded false negative. *)
module Sub' : sig
  val bad' : int
end
