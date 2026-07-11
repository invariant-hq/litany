(* Fixture for manual-option-map: positives carry the FIRE marker; every
   other binding is a negative lookalike from the spec plus adversarial
   extras. *)

let render v = string_of_int v

(* The match form: the general lambda rewrite. *)
let p1 o = match o with Some x -> Some (x + 1) | None -> None (* FIRE *)

(* Reversed case order; the rebuild is [f x]: the tighter Option.map f. *)
let p2 o = match o with None -> None | Some v -> Some (render v) (* FIRE *)

(* The function form, parameterized: report only. *)
let p3 f = function Some x -> Some (f x) | None -> None (* FIRE *)

(* The identity rebuild: the match is the scrutinee itself. *)
let p4 o = match o with Some x -> Some x | None -> None (* FIRE *)

(* An applied scrutinee: the fix parenthesizes it. *)
let p5 m =
  match List.assoc_opt 1 m (* FIRE *) with
  | Some x -> Some (x * 2)
  | None -> None

(* Argument position: the parser's location for a parenthesized match
   includes the author's parentheses, and the application replacement is
   not self-delimiting — the fix restores the pair or the call
   re-associates as [(Option.is_some Option.map) ...]. *)
let p6 o =
  Option.is_some
    (match o (* FIRE *) with Some x -> Some (x + 1) | None -> None)

(* negative: a guard *)
let n1 p o = match o with Some x when p x -> Some x | _ -> None

(* negative: a wildcard None arm — clean in v1 (recorded extension) *)
let n2 f o = match o with Some x -> Some (f x) | _ -> None

(* negative: the Some arm does not rebuild Some — Option.bind territory *)
let n3 f o = match o with Some x -> f x | None -> None

(* negative (adversarial): user Some/None constructors *)
module UserOpt = struct
  type t = Some of int | None

  let keep v = match v with Some x -> Some x | None -> None
end

(* negative: a deep payload pattern *)
let n5 o = match o with Some (Some x) -> Some x | None -> None
[@@warning "-8"]

(* negative: an exception arm is not a value case *)
exception E

let n6 f =
  match f () with Some x -> Some x | None -> None | exception E -> None

(* negative (adversarial extra): an aliased payload is a different shape *)
let n7 o = match o with Some _x as s -> s | None -> None
