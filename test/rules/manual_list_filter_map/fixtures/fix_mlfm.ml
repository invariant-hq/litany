(* Fixture for manual-list-filter-map: positives carry the FIRE marker;
   every other binding is a negative lookalike from the spec plus one
   adversarial extra. *)

(* The if form keeping the head unchanged: List.filter. *)
let rec evens (* FIRE *) = function
  | [] -> []
  | x :: xs -> if x mod 2 = 0 then x :: evens xs else evens xs

(* The mirrored if form: cons in the else branch. *)
let rec odds (* FIRE *) = function
  | [] -> []
  | x :: xs -> if x mod 2 = 0 then odds xs else x :: odds xs

(* The if form keeping a transformed head: List.filter_map. *)
let rec doubled (* FIRE *) = function
  | [] -> []
  | x :: xs -> if x > 0 then (2 * x) :: doubled xs else doubled xs

(* The match form over an option-returning scrutinee. *)
let rec parse (* FIRE *) = function
  | [] -> []
  | s :: r -> (
      match int_of_string_opt s with Some n -> n :: parse r | None -> parse r)

(* The parameterized filter_map, match form, None case first. *)
let rec fm (* FIRE *) f = function
  | [] -> []
  | x :: xs -> ( match f x with None -> fm f xs | Some y -> y :: fm f xs)

(* negative: the else branch is not the bare recursion — take-while *)
let rec keep p = function
  | [] -> []
  | x :: xs -> if p x then x :: keep p xs else []

(* negative: the kept head is not the bound option payload — clean in
   v1 (recorded generalization candidate) *)
let rec fm2 g f = function
  | [] -> []
  | x :: xs -> (
      match g x with Some y -> f y :: fm2 g f xs | None -> fm2 g f xs)

(* negative: a guard on the cons case (the deliberately partial
   lookalike needs its warning silenced; the shape is the point) *)
let rec fmg p = function
  | [] -> []
  | x :: xs when p x -> if x > 0 then x :: fmg p xs else fmg p xs
[@@warning "-8"]

(* negative: no [rec] under the outer evens — identity refuses the
   self-call (adversarial shadowing) *)
let evens l =
  match l with
  | [] -> []
  | x :: xs -> if x mod 2 = 0 then x :: evens xs else evens xs

(* negative: a user option-like variant — predefined identity refuses *)
module UserOpt = struct
  type 'a opt = Some of 'a | None

  let lift x = if x > 0 then Some x else None

  let rec ufm = function
    | [] -> []
    | x :: xs -> ( match lift x with Some y -> y :: ufm xs | None -> ufm xs)
end

(* negative (adversarial extra): both branches cons — a map with a dead
   condition, not a filter *)
let rec bothc p = function
  | [] -> []
  | x :: xs -> if p x then x :: bothc p xs else x :: bothc p xs

(* negative: the condition reads the scrutinized list parameter, rebound
   at every recursive call — no filter predicate sees it (the
   filter_map form would compute different values). *)
let rec spooky_evens l =
  match l with
  | [] -> []
  | x :: xs ->
      if List.length l mod 2 = 0 then x :: spooky_evens xs else spooky_evens xs
