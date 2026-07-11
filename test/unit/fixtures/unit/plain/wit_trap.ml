(* Trap fixture: a hand-written module whose only [.mll] mention is
   data — a directive line quoted inside a string literal. The lexical
   marker scan classifies it generated (a documented false positive), so
   the classification must be named, never an anonymous facts-only count.
   [flag] is a genuine redundant-if-bool positive the reclassification
   swallows. *)

let expected_ocamllex_header = {|
# 1 "lexer.mll"
let token lexbuf = ...|}

let flag c = if c then true else false
