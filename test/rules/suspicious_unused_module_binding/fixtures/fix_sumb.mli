(* The interface of the suspicious-unused-module-binding fixture:
   exports every value and hides [Cache], [L], and [Used] — the export
   gate the rule reads from the compiled interface. *)

val f : int -> int
val g : unit -> int
val h : unit -> int
val use_it : int
val shadow_pair : unit -> int
val constructor_use : 'a -> 'a
