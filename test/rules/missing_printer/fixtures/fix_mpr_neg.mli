(* Interface fixture for the missing-printer negatives: evidence plus
   printer, a manifest type, wrong-shape evidence, and a submodule
   signature (the recorded toplevel-only false negative). Nothing in
   this unit may fire. *)

type w

val compare : w -> w -> int
val pp : Format.formatter -> w -> unit

type v = int

val to_string : v -> string

type y

val equal : y -> y -> unit

module Sub : sig
  type s

  val equal : s -> s -> bool
end
