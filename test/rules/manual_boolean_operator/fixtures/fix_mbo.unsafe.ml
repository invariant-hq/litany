(* Fixture for manual-boolean-operator: positives carry the FIRE marker;
   every other line is a negative lookalike from the spec plus one
   adversarial extra. Every fix cell is Unsafe, so the .fixed golden's
   bytes equal this file's — --fix without --unsafe changes nothing. *)

let retry () = true
let compute () = false

(* All four rewrite cells. *)
let p1 found = found || (retry ()) (* FIRE *)
let p2 valid = valid && (compute ()) (* FIRE *)
let p3 c t = not c || t (* FIRE *)
let p4 c t = not c && t (* FIRE *)

(* Argument position: the parenthesized if's location includes the
   parentheses, and the operator replacement is not self-delimiting —
   the fix restores the pair (pinned by the unsafe golden). *)
let p5 found = string_of_bool (found || (retry ())) (* FIRE *)

(* negative: two-literal branches are redundant-if-bool's *)
let n1 c = if c then true else false

(* negative: a literal condition is suspicious-literal-condition's *)
let n2 = if true then true else retry ()

(* negative: equal literals in both branches — degenerate *)
let n3 c = if c then true else true

(* negative: no literal branch *)
let n4 c f g = if c then f () else g ()

(* negative: integer literals are not booleans *)
let n5 c = if c then 1 else 0

(* negative: user constructors, not the predefined booleans *)
type t = True | False

let n6 c = if c then True else False

(* negative (adversarial extra): polymorphic-variant lookalikes *)
let n7 c = if c then `True else `False

(* A fix-site scope that shadows a spliced operator:
   the operator rewrites are Unsafe, so --fix leaves the line alone. *)
let cor02 c t =
  let ( || ) a _ = a in
  c || (t || false)
