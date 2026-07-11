(* Implementation fixture for the missing-printer negatives: no marked
   lines — nothing here may fire. *)

type w = float
type v = int
type y = string

let compare (a : w) (b : w) = Float.compare a b
let pp ppf (_ : w) = Format.pp_print_string ppf "<w>"
let to_string (n : v) = string_of_int n
let equal (_ : y) (_ : y) = ()

module Sub = struct
  type s = int

  let equal (a : s) (b : s) = Int.equal a b
end
