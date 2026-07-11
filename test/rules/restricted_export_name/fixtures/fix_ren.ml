(* Fixture for restricted-export-name, the mli-backed unit: the suite
   configures (forbid-suffix ') and (max-underscores 3); each marked
   line is the implementation anchor of an exported name a restriction
   condemns. The mli decides what is exported — same-shaped names it
   hides stay silent. *)

(* The exported prime type. *)
type t' = int (* FIRE *)

(* negative: a well-named exported record type. *)
type meta = { tag : int }

(* negative: a prime-suffixed type the mli hides. *)
type hidden' = Zero

(* negative: a prime-suffixed value the mli hides. *)
let helper' n = (match Zero with Zero -> n) * 2

(* The exported prime value. *)
let parse' n = helper' n + 1 (* FIRE *)

(* negative: the forbidden suffix occurs mid-name only. *)
let x'y = 7

(* negative: exactly at the underscore limit. *)
let a_b_c_d = 3

(* Over the underscore limit. *)
let a_b_c_d_e = 4 (* FIRE *)

(* The exported prime external: a root declaration like any other. *)
external refl' : int -> int = "%identity" (* FIRE *)

(* negative: a module name never fires, and Sub'.bad' is a submodule
   export — outside the root surface, a recorded false negative. *)
module Sub' = struct
  let bad' = 9
end
