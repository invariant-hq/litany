(* The shared signature: [Wit_incl]'s mli includes [S], so values declared
   through it carry this unit's interface uids. *)
module type S = sig
  val v : int
end
