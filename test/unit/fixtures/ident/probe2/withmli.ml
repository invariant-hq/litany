(* A wrapped workspace unit with an mli: external use sites carry the
   interface uid, while [uses_f]'s own call of [f] carries the impl uid —
   the intra-unit bridge case. *)

let priv = 1
let f x = x + priv
let uses_f y = f y
