(* Control fixture: byte-identical in shape to [wit_trap.ml] minus
   the quoted directive line — it must stay unclassified and keep
   linting. *)

let expected_ocamllex_header =
  {|
plain data, no directive
let token lexbuf = ...|}

let flag c = if c then true else false
