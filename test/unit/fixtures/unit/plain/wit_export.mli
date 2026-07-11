(* The export surface: [scale] is deliberately absent. *)
type t

val make : int -> t

module Sub : sig
  val x : int
end
