(* Module ascription mints fresh uids: [Asc.length] and [List.length] are
   distinct identities. The ascription also records a cross-unit
   def->decl pair in this unit's cmt — the pair the intra-unit bridge
   filter must refuse. *)

module Asc : sig
  val length : 'a list -> int
end =
  List

let use_withmli x = Withmli.f x
let use_nomli_g x = Nomli.g x
let use_nomli_f x = Nomli.f x
let use_asc xs = Asc.length xs
let use_list_direct xs = List.length xs
