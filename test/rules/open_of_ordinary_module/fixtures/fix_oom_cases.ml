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

(* A constructor in a pattern comes through the open. *)
module Takes_constructor = struct
  open Mixed.Constructor (* FIRE *)

  let f x =
    let* y = x in
    Ok (match y with A -> 1 | B -> 2)
end

(* So does a record field. *)
module Takes_field = struct
  open Mixed.Field (* FIRE *)

  let f x =
    let* y = x in
    Ok y.f
end

(* So does a member of a submodule. *)
module Takes_member = struct
  open Mixed.Member (* FIRE *)

  let f x =
    let* y = x in
    Ok (Sub.v + y)
end

(* So does a type. *)
module Takes_type = struct
  open Mixed.Type_only (* FIRE *)

  let f x =
    let* (y : t) = x in
    Ok y
end

(* A name written out in full is not taken through the open, which supplies
   only the operator. *)
module Writes_out = struct
  open Mixed.Written_out

  let f x =
    let* y = x in
    Ok (y + Mixed.Written_out.helper)
end

(* An open whose names are all written out in full supplies nothing. *)
module Takes_nothing_written_out = struct
  open Mixed.Nothing_through (* FIRE *)

  let f x = Mixed.Nothing_through.( let* ) x (fun y -> Ok y)
end

(* An open nothing uses. *)
module Takes_nothing = struct
  open Mixed.Unused (* FIRE *)

  let v = 1
end

(* An open of a structure names no module made to be opened. *)
module Anonymous = struct
  open struct let hidden = 1 end (* FIRE *)

  let v = hidden
end
