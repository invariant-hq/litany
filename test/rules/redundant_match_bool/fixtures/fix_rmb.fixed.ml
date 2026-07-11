(* Fixture for redundant-match-bool: positives carry the FIRE marker —
   each one a boolean match in a cascade position (an else continuation,
   or arms that continue into if/else). The negatives are the deliberate
   standalone house styles the narrowing exempts, plus the spec
   negatives dressed in the cascade position so the case-structure gates
   stay load-bearing. *)

let debug = false

exception E

(* The core shape (the canonical field sighting, stdlib weak.ml:165): the boolean match
   as an else continuation. *)
let p1 b i = if i >= 10 then 0 else if b then 1 else 2 (* FIRE *)

(* Reversed, effectful arms in else position. *)
let p2 a d =
  if d then 0
  else
    if a then 2 else (Format.printf "m %d" 42;
        1)

(* Arms continuing the cascade: a standalone match whose false arm is
   itself an if/else. *)
let p3 a d = if a then 1 else (if d then 2 else 3) (* FIRE *)

(* The function form fires on the arm shape alone. *)
let p4 d = function true -> if d then 1 else 2 | false -> 3 (* FIRE *)

(* The cascading-arms shape in argument position: the parenthesized
   match's location includes the parentheses, and the if replacement is
   not self-delimiting — the fix restores the pair or the call
   re-associates as [succ if ...]. *)
let p5 a d = succ (if a then 1 else (if d then 2 else 3)) (* FIRE *)

(* The else-continuation shape, parenthesized: the pair is the author's
   and stays. *)
let p6 b i = if i >= 10 then 0 else (if b then 1 else 2) (* FIRE *)

(* negative (house style, cmdliner): a standalone boolean match on a
   comparison. *)
let n1 i len = match i = len with true -> 1 | false -> 2

(* negative (house style, cmdliner_arg): standalone, result-returning
   arms. *)
let n2 s =
  match String.length s = 1 with true -> Ok s.[0] | false -> Error "width"

(* negative (house style, ppxlib pp_ast): standalone config dispatch. *)
let show = false
let n3 f g = match show with true -> f () | false -> g ()

(* negative (house style, sexplib0): standalone mid-parser bounds
   check. *)
let n4 seen i len = match seen <= i && i < len with true -> 1 | false -> 2

(* negative: the plain function form no longer fires standalone. *)
let n5 x = function true -> 1 | false -> 2 + x

(* negative: a then branch is not an else continuation. *)
let n6 b i = if i > 0 then (match b with true -> 1 | false -> 2) else 0

(* negative: guards and three cases, even in else position *)
let n7 d b =
  if d then 0
  else match b with true when debug -> 1 | true -> 2 | false -> 3

(* negative: a wildcard second case — clean in v1 (recorded extension) *)
let n8 d b = if d then 0 else match b with true -> 1 | _ -> 2

(* negative: an exception case — the if rewrite would change semantics *)
let n9 d f =
  if d then 0 else match f () with true -> 1 | false -> 2 | exception E -> 3

(* negative: a user two-constructor variant is not the predefined bool *)
type t = On | Off

let both = [ On; Off ]
let n10 d s = if d then 1 else match s with On -> 1 | Off -> 2

(* negative (adversarial extra): an aliased literal pattern is a
   different shape — Tpat_alias never matches through *)
let n11 d b = if d then true else match b with true as t -> t | false -> false

(* negative: a match carrying effect-handler cases — refused by the
   match_ view's contract (pinned) *)
type _ Effect.t += Ask : int Effect.t

let n12 d h =
  if d then 0
  else
    match h () with
    | true -> 1
    | false -> 2
    | effect Ask, k -> Effect.Deep.continue k 3
