(* Fixture for suspicious-if-same-branches: positives carry the FIRE
   marker; every other case is a spec negative plus one adversarial
   extra. *)

let is_admin u = u > 0
let grant u = u + 1
let log (_ : string) = ()
let f x = x * 2

(* The unedited paste. *)
let p1 u = if is_admin u then grant u else grant u (* FIRE *)

(* Computed operands. *)
let p2 x = if x > 0 then f (x - 1) else f (x - 1) (* FIRE *)

(* Effectful but identical: identical slices imply identical effects. *)
let p3 c =
  if c (* FIRE *) then (
    log "hit";
    1)
  else (
    log "hit";
    1)

(* The equal-literal pair redundant-if-bool deliberately refuses. *)
let p4 c = if c then true else true (* FIRE *)

(* negative: different bytes. *)
let n1 c x y = if c then f x else f y

(* negative: comment-only difference marks the arm meant to change. *)
let n2 c x = if c then f x (* retry path *) else f x

(* negative: same resolution, different spelling — the technique's
   deliberate false negative. *)
module L = List

let n3 c g xs = if c then L.map g xs else List.map g xs

(* negative: a literal condition is suspicious-literal-condition's. *)
let n4 x = if true then x else x

(* negative: an else-less if has nothing to compare. *)
let n5 c = if c then log "only"

(* negative (adversarial extra): literal spelling differs — no literal
   canonicalization, different bytes. *)
let n6 c = if c then f 0x10 else f 16
