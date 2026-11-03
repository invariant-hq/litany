(* Fixture for open-of-ordinary-module: positives carry the FIRE marker. *)

(* A file-wide open of an ordinary module. *)
open Store (* FIRE *)

(* A module of binding operators alone is made to be opened. *)
open Syntax

let both a b =
  let* x = a and* y = b in
  Ok (x + y + count)

(* In a nested structure too. *)
module Inner = struct
  open List (* FIRE *)

  let first xs = nth_opt xs 0
end

(* An open local to an expression is a combinator library's place. *)
let local xs = List.(length xs)

let local_in xs =
  let open List in
  length xs

let found = find ()
