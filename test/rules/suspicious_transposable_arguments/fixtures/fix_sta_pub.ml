(* The mli-backed companion: the interface decides the export surface,
   joined by root value name. *)

let shown m fn msg = failwith (m ^ fn ^ (msg : string)) (* FIRE *)
let hidden (a : string) (b : string) (c : string) = a ^ b ^ c
let use () = (shown "a" "b" "c" : unit) = ignore (hidden "d" "e" "f")
