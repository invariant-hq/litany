(* Interface fixture for missing-printer: two comparable abstract types
   with no printer of their own — the implementation carries the FIRE
   markers on its matching toplevel declarations. The [pp] here prints
   the handle [h] alone: a printer for another type must not count. *)

type t

val equal : t -> t -> bool

type u

val to_string : u -> string

type h

val make : unit -> h
val pp : Format.formatter -> h -> unit
