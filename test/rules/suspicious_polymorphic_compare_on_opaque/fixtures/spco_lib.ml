(* Support unit for the suspicious-polymorphic-compare-on-opaque fixture:
   functor instances declared in a separate compilation unit, so their
   type heads reach the linted unit as persistent-rooted paths that walk
   to the functor body's declaration. *)

module IntSet = Set.Make (Int)
module IntMap = Map.Make (Int)

(* Adversarial bait: a type merely spelled [Hashtbl.t], with this unit's
   own identity. *)
module Hashtbl = struct
  type t = Empty
end

let set_a = IntSet.empty
let set_b = IntSet.singleton 1
let map_a : string IntMap.t = IntMap.empty
let map_b = IntMap.add 1 "one" IntMap.empty
let fake : Hashtbl.t = Empty
