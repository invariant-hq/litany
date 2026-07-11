(* Intra-unit recursive islands: self- and mutual recursion reachable from
   no root — the provisional-dead cycles, reported whole. *)
let rec loop x = loop (x - 1) (* FIRE *)

let rec odd n = if n = 0 then false else even (n - 1) (* FIRE *)
and even n = if n = 0 then true else odd (n - 1)
(* FIRE *)
