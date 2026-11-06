(* Fixture for untyped-wildcard-binding: positives carry the FIRE marker. *)

let write (_ : string) : (unit, string) result = Ok ()

(* At the root. *)
let _ = write "a" (* FIRE *)

(* In an expression. *)
let inner () =
  let _ (* FIRE *) = write "b" in
  ()

(* The type is named: what the rule asks for. *)
let (_ : (unit, string) result) = write "c"

let typed_inner () =
  let (_ : (unit, string) result) = write "d" in
  ()

(* A named binding, and unit, discard nothing unseen. *)
let named () =
  let _written = write "e" in
  ()

let () = ignore (write "f" : (unit, string) result)

(* A wildcard nested in a pattern binds a field, it discards no value. *)
let pair () =
  let a, _ = (1, 2) in
  a

(* The spellings of a named type, and of none. *)
let (_ : (unit, string) result) = write "g"
let _ : (unit, string) result = write "h"
let _ (* FIRE *) = write "i"
let (_ : _) (* FIRE *) = write "j"
let (_ : 'a) (* FIRE *) = write "k"
