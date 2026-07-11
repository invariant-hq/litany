(* Fixture for manual-list-map: positives carry the FIRE marker; every
   other binding is a negative lookalike from the spec plus one
   adversarial extra. *)

(* The cases form with a function parameter. *)
let rec map1 f = function [] -> [] | h :: tl -> f h :: map1 f tl (* FIRE *)

(* Specialized: no function parameter. *)
let rec map3 = function [] -> [] | h :: tl -> (h + 1) :: map3 tl (* FIRE *)

(* The match form. *)
let rec map4 (* FIRE *) f l =
  match l with [] -> [] | x :: xs -> f x :: map4 f xs

(* Nested recursion inside a plain binding. *)
let map6 input =
  let rec map (* FIRE *) = function [] -> [] | h :: tl -> (h + 1) :: map tl in
  map input

(* List-first parameter order — a deliberate generalization. *)
let rec map5 (* FIRE *) l f =
  match l with [] -> [] | x :: xs -> f x :: map5 xs f

(* negative: no [rec] — the body's map1 is the outer one, and identity
   (not spelling) refuses the self-call (adversarial shadowing) *)
let map1 f = function [] -> [] | h :: tl -> f h :: map1 f tl

(* negative: the argument is not the bound tail *)
let rec map_tl f = function
  | [] -> []
  | x :: xs -> f x :: map_tl f (List.tl (x :: xs))

(* negative: a guard on the cons case (the deliberately partial
   lookalike needs its warning silenced; the shape is the point) *)
let rec mapg p = function [] -> [] | x :: xs when p x -> x :: mapg p xs
[@@warning "-8"]

(* negative: the head expression reads the tail — not a map *)
let rec map_len = function [] -> [] | _ :: xs -> List.length xs :: map_len xs

(* negative: a user-defined (::)/[] — predefined identity refuses *)
module UserList = struct
  type t = ( :: ) of int * t | []

  let rec weird = function
    | ([] : t) -> ([] : t)
    | x :: xs -> (x + 1) :: weird xs
end

(* negative: three cases, an alias pattern, a nil case that is not [] *)
let rec map7 = function
  | [] -> []
  | [ x ] -> [ x + 1 ]
  | h :: tl -> h :: map7 tl

let rec map8 = function
  | [] -> []
  | x :: xs as l -> (x + List.length l) :: map8 xs

let rec map9 = function [] -> [ 0 ] | h :: tl -> h :: map9 tl

(* negative (adversarial extra): labeled parameters and labeled
   self-call arguments are a different shape *)
let rec mapl ~f = function [] -> [] | x :: xs -> f x :: mapl ~f xs

(* negative: the head reads the scrutinized list parameter, which is
   rebound at every recursive call — not expressible as List.map (the
   map form would compute different
   values). *)
let rec spooky f l =
  match l with [] -> [] | h :: tl -> (f h + List.length l) :: spooky f tl
