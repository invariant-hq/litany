(* Fixture for manual-option-bind: positives carry the FIRE marker on
   the match's first line; every other case is a spec negative plus one
   adversarial extra. *)

let validate n = if n > 0 then Some n else None
let find k m = List.assoc_opt k m
let advance st = if st > 9 then None else Some (st + 1)

(* The match form. *)
let p1 s =
  match (* FIRE *) int_of_string_opt s with
  | Some n -> validate n
  | None -> None

(* A further lookup on Some — the chained-binds motivation. *)
let p2 k m =
  match (* FIRE *) find k m with Some v -> validate v | None -> None

(* Reversed case order. *)
let p3 o = match (* FIRE *) o with None -> None | Some n -> validate n

(* The function form. *)
let step = function Some st -> advance st | None -> None (* FIRE *)

(* negative: the manual-option-map shape — the pinned partition. *)
let n1 o = match o with Some y -> Some (y + 1) | None -> None

(* negative: the identity roundtrip is neither rule's. *)
let n2 o = match o with Some y -> Some y | None -> None

(* negative: a defaulting None arm is Option.fold territory. *)
let n3 o = match o with Some y -> validate y | None -> Some 0

(* negative: guards refuse (the partial-match lookalike needs its
   warning silenced; the shape is the point). *)
let n4 o p = match o with Some y when p y -> validate y | None -> None
[@@warning "-8"]

(* negative: an exception arm refuses. *)
let n5 g =
  match g () with
  | Some y -> validate y
  | None -> None
  | exception Not_found -> None

(* negative (adversarial): user option lookalikes — predefined-option
   identity refuses. *)
type opt = None | Some of int

let vopt v : opt = if v > 0 then Some v else None
let n6 (x : opt) = match x with Some y -> vopt y | None -> None

(* negative: a non-variable payload pattern — v1 conservatism. *)
let n7 (po : (int * int) option) =
  match po with Some (a, b) -> validate (a + b) | None -> None

(* negative (adversarial extra): a wildcard arm is not the None
   pattern. *)
let n8 (o : int option) = match o with Some y -> validate y | _ -> None
