(* Interface for the mli-backed fixture: what this file declares is the
   export surface — its exceptions fire, anchored in the implementation. *)

exception Boom of string
exception Rebound

val trigger : unit -> unit

(* negative: a non-exception extension constructor contributes no row. *)
type ext = ..
type ext += Case

(* negative: a submodule exception is a dotted row — outside the root
   surface, a recorded false negative. *)
module Sub : sig
  exception Nested
end
