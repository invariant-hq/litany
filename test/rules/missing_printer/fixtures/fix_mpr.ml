(* Implementation fixture for missing-printer: markers sit on the
   toplevel declarations whose interface rows are comparable abstract
   types without printers. *)

type t = int (* FIRE *)
type u = { name : string } (* FIRE *)
type h = unit

let equal (a : t) (b : t) = Int.equal a b
let to_string (x : u) = x.name
let make () : h = ()
let pp ppf (_ : h) = Format.pp_print_string ppf "<h>"
