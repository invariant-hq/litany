(* The smallest lexer: its generated wit_lex.ml is the generated-classification fixture. *)

rule token = parse
  | eof { 0 }
  | _ { 1 }
