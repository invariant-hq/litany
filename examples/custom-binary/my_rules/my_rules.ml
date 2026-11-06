open Litany

let meta =
  Rule.meta ~name:"house-print-endline" ~group:Rule.Restriction
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"use of print_endline"
    ~doc:
      {|The house writes through a formatter its caller hands in.

    (* bad *)  print_endline "done"
    (* good *) Format.fprintf ppf "done@."

Fires at every identifier whose resolved identity is
`Stdlib.print_endline`; a shadowing definition deliberately does not
fire.|}
    ()

let print_endline = Pat.ident "Stdlib.print_endline"

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run print_endline u e () with
  | Some () -> [ Finding.v ~loc:e.exp_loc "print through a formatter" ]
  | None -> []

let all = [ rule ]
