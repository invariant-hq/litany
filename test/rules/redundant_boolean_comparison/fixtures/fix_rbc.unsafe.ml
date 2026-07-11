(* Fixture for redundant-boolean-comparison: positives carry the FIRE
   marker; every other line is a negative lookalike ported from the old
   rule's cases. *)

let flag = Sys.word_size > 32
let n = Sys.word_size

(* Both operators, both constants, both operand orders. *)
let p1 = flag (* FIRE *)
let p2 = not flag (* FIRE *)
let p3 = not flag (* FIRE *)
let p4 = flag (* FIRE *)
let p5 = flag (* FIRE *)
let p6 = flag (* FIRE *)

(* A computed operand fires too: the constant is the redundancy. *)
let p7 = (n > 2) (* FIRE *)

(* Argument position: the parenthesized comparison's location includes
   the parentheses. The safe cell's bare operand needs none and drops
   them; the negate cell's application restores them (pinned by the
   unsafe golden). *)
let p8 = string_of_bool flag (* FIRE *)
let p9 = string_of_bool (not flag) (* FIRE *)

(* No boolean constant. *)
let n1 other = flag = other
let n2 = flag = (n > 2)

(* Two boolean constants are a constant expression, not a redundant
   comparison of an operand. *)
let n3 = true = false

(* Non-boolean constants. *)
let n4 = n = 1

(* Other operators over bool stay clean: physical equality, ordering,
   and Bool.equal are different questions for this rule. *)
let n5 = flag == true
let n6 = flag < true
let n7 = Bool.equal flag true

(* Shadowed operator (adversarial): a local ( = ) is not Stdlib.(=). *)
let n8 =
  let ( = ) _ _ = false in
  flag = true

(* Redefined constructors (adversarial): [true]/[false] of another type
   are not the predefined bool literals. *)
type fake = true | false

let n9 (x : fake) = x = true
let n10 : fake = false

(* A fix-site scope that shadows [not]: the negate
   rewrite is Unsafe, so --fix leaves the line alone. *)
let cor02 =
  let not _ = false in
  not (not flag)
