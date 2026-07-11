(* Only [shown] crosses the boundary: the offending [hidden] is not
   exported and must stay silent. *)

val shown : string -> string -> string -> 'a
val use : unit -> bool
