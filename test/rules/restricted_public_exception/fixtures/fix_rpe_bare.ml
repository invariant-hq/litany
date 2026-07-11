(* Fixture for restricted-public-exception, the ml-only unit: without an
   mli the inferred signature is the export surface, so every root
   [exception] declaration is exported and fires directly. *)

(* The exported exception — exported by the derived signature. *)
exception Overflow (* FIRE *)

(* The exported carrying exception. *)
exception Parse_error of string (* FIRE *)

(* negative: a local exception never reaches the export surface. *)
let checked f x =
  let exception Bail in
  match f x with
  | v -> v
  | exception Not_found -> raise (if x = 0 then Bail else Overflow)

(* negative: a nested module's exception is a dotted row — outside the
   root surface, a recorded false negative. *)
module Inner = struct
  exception Deep
end
