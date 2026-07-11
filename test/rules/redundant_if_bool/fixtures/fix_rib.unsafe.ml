(* Fixture for redundant-if-bool: positives carry the FIRE marker; every
   other line is a negative lookalike from the spec plus one adversarial
   extra. *)

let p x = x > 0
let retry () = true
let compute () = false

(* The two spec positives, one per rewrite. *)
let p1 x = (p x) (* FIRE *)
let p2 ok = not ok (* FIRE *)

(* Argument position: the parenthesized if's location includes the
   parentheses. The condition cell splices an already-delimited operand;
   the negation cell's application restores the pair (pinned by the
   unsafe golden). *)
let p3 x = string_of_bool (p x) (* FIRE *)
let p4 ok = string_of_bool (not ok) (* FIRE *)

(* negative: one-literal branches are manual-boolean-operator's — the
   family split out as its own rule *)
let n0a found = if found then true else retry ()
let n0b valid = if valid then compute () else false
let n0c c t = if c then t else true
let n0d c t = if c then false else t

(* negative: a literal condition is suspicious-literal-condition's *)
let n1 = if true then true else false

(* negative: integer literals are not booleans *)
let n2 c = if c then 1 else 0

(* negative: no literal branch *)
let n3 c f g = if c then f () else g ()

(* negative: equal literals in both branches — degenerate, left to a
   same-arms analysis *)
let n4 c = if c then true else true

(* negative: user constructors, not the predefined booleans *)
type t = True | False

let n5 c = if c then True else False

(* negative (adversarial extra): polymorphic-variant lookalikes *)
let n6 c = if c then `True else `False

(* A fix-site scope that shadows the spliced [not]:
   the negation rewrite is Unsafe, so --fix leaves the line alone. *)
let cor02 c =
  let not _ = 0 in
  ignore (not 1);
  not c (* FIRE *)
