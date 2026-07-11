(* Fixture for the matches_type local-alias hop: unit-local functor
   instances and plain aliases resolve; an ascription resolves exactly as
   its written signature does — a named module type carries that module
   type's interface UIDs, an inline signature mints unit-local ones that
   match no canonical name. *)

module SM = Map.Make (String)
module IS = Set.Make (Int)
module H = Hashtbl
module AM : Map.S with type key = string = Map.Make (String)

module Opaque : sig
  type t

  val empty : t
end = struct
  type t = S of string

  let empty = S ""
end

let sm_probe = SM.empty
let is_probe = IS.empty
let h_probe : (string, int) H.t = H.create 8
let h_use = h_probe
let am_probe = AM.empty
let opaque_probe = Opaque.empty
