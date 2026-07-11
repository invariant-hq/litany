(* Slicing fixture for Unit.parenthesized / Unit.delimited: the parser
   relocates a delimited expression over its delimiters, so each binding's
   expression slice is what the binding shows. Excluded from ocamlformat,
   which would normalize the delimiters away. *)
let paren = (1 + 2)
let block = begin 1 + 2 end
let bare = 1 + 2
let framed_both = (1) + (2)
let beginning = 7
let begin_prefix = beginning + 1
let friend = 3
let end_suffix = 2 + friend
