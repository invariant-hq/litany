(* Fixture for manual-list-exists: positives carry the FIRE marker;
   every other binding is a negative lookalike from the spec plus one
   adversarial extra. *)

(* The cases form, function-parameter step. *)
let rec has (* FIRE *) p = function [] -> false | x :: xs -> p x || has p xs

(* A specialized step: List.exists is still the truthful suggestion. *)
let rec mem (* FIRE *) y = function [] -> false | x :: xs -> x = y || mem y xs

(* The match form, no function parameter. *)
let rec any (* FIRE *) l = match l with [] -> false | x :: xs -> x || any xs

(* The match form with a parameter, list scrutinized by position. *)
let rec has2 (* FIRE *) p l =
  match l with [] -> false | x :: xs -> p x || has2 p xs

(* The cases form at two explicit parameters. *)
let rec both (* FIRE *) p q = function
  | [] -> false
  | x :: xs -> p x q || both p q xs

(* negative: self-call left of || — evaluation order differs from
   List.exists (recorded false negative, deliberate) *)
let rec left p = function [] -> false | x :: xs -> left p xs || p x

(* negative: the nil literal is true — constant-true, not exists; the
   (false, ||) pairing is required *)
let rec always p = function [] -> true | x :: xs -> p x || always p xs

(* negative: no [rec] under the outer has — Ident.same refuses the
   self-call (adversarial shadowing) *)
let has p = function [] -> false | x :: xs -> p x || has p xs

(* negative: the recursion argument is not the bound tail *)
let rec ntl p = function [] -> false | x :: xs -> p x || ntl p (List.tl xs)

(* negative: a guard on the cons case (the deliberately partial
   lookalike needs its warning silenced; the shape is the point) *)
let rec guarded p = function
  | [] -> false
  | x :: xs when p x -> p x || guarded p xs
[@@warning "-8"]

(* negative: extra cases *)
let rec three p = function
  | [] -> false
  | [ x ] -> p x
  | x :: xs -> p x || three p xs

(* negative: a user-defined (::)/[] — predefined identity refuses *)
module UserList = struct
  type t = ( :: ) of int * t | []

  let rec uhas p = function ([] : t) -> false | x :: xs -> p x || uhas p xs
  let sample = 1 :: []
end

(* negative: the if spelling — redundant-if-bool owns that inner if
   (stated boundary; its fix rewrites to the || form, after which this
   rule fires) *)
let rec ifs p = function
  | [] -> false
  | x :: xs -> if p x then true else ifs p xs

(* negative (adversarial extra): the step uses the bound tail — no
   faithful List.exists predicate exists *)
let rec usestl p = function
  | [] -> false
  | x :: xs -> (p x && xs = []) || usestl p xs
