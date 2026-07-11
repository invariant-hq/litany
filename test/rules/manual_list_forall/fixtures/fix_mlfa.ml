(* Fixture for manual-list-forall: positives carry the FIRE marker;
   every other binding is a negative lookalike from the spec plus one
   adversarial extra. *)

(* The cases form, function-parameter step. *)
let rec all (* FIRE *) p = function [] -> true | x :: xs -> p x && all p xs

(* A specialized step, no function parameter. *)
let rec positive (* FIRE *) = function
  | [] -> true
  | x :: xs -> x > 0 && positive xs

(* The match form. *)
let rec every (* FIRE *) p l =
  match l with [] -> true | x :: xs -> p x && every p xs

(* negative: self-call left of && — evaluation order differs from
   List.for_all (recorded false negative, deliberate) *)
let rec left p = function [] -> true | x :: xs -> left p xs && p x

(* negative: the nil literal is false — constant-false, not for_all;
   the (true, &&) pairing is required *)
let rec never p = function [] -> false | x :: xs -> p x && never p xs

(* negative: no [rec] under the outer all — Ident.same refuses the
   self-call (adversarial shadowing) *)
let all p = function [] -> true | x :: xs -> p x && all p xs

(* negative: the recursion argument is not the bound tail *)
let rec ntl p = function [] -> true | x :: xs -> p x && ntl p (List.tl xs)

(* negative: a guard on the cons case (the deliberately partial
   lookalike needs its warning silenced; the shape is the point) *)
let rec guarded p = function
  | [] -> true
  | x :: xs when p x -> p x && guarded p xs
[@@warning "-8"]

(* negative: extra cases *)
let rec three p = function
  | [] -> true
  | [ x ] -> p x
  | x :: xs -> p x && three p xs

(* negative: a user-defined (::)/[] — predefined identity refuses *)
module UserList = struct
  type t = ( :: ) of int * t | []

  let rec uall p = function ([] : t) -> true | x :: xs -> p x && uall p xs
  let sample = 1 :: []
end

(* negative: the if spelling — redundant-if-bool owns that inner if *)
let rec ifs p = function
  | [] -> true
  | x :: xs -> if p x then ifs p xs else false

(* negative (adversarial extra): the step uses the bound tail — no
   faithful List.for_all predicate exists *)
let rec usestl p = function
  | [] -> true
  | x :: xs -> (p x || xs = []) && usestl p xs
