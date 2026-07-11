(* No mli in a wrapped library: the derived cmi embeds definition uids, and
   the [include] re-export preserves Withmli's interface uid — two canonical
   names, one identity. *)

include Withmli

let g x = x * 2
