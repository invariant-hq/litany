(* Module ascription mints fresh uids and records a def->decl pair whose
   definition side is Stdlib__List's interface item — the trap the bridge
   filter must refuse through the shipped loader. *)
module Asc : sig
  val length : 'a list -> int
end =
  List

let use_asc xs = Asc.length xs
let use_list xs = List.length xs
