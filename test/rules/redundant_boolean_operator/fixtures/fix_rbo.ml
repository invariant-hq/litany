(* Fixture for redundant-boolean-operator: positives carry the FIRE
   marker; every other line is a negative lookalike ported from the old
   rule's cases. *)

let effect_bool () =
  print_string "";
  Sys.word_size > 32

(* A left constant always preserves evaluation: short-circuiting already
   decided whether the right operand runs. *)
let p1 x = true && x (* FIRE *)
let p2 x = false && x (* FIRE *)
let p3 x = true || x (* FIRE *)
let p4 x = false || x (* FIRE *)
let p5 () = true && effect_bool () (* FIRE *)
let p6 () = false || effect_bool () (* FIRE *)

(* A neutral right constant drops without touching what runs, whatever the
   left operand does. *)
let p7 x = x && true (* FIRE *)
let p8 x = x || false (* FIRE *)
let p9 () = effect_bool () && true (* FIRE *)

(* An absorbing right constant discards the left operand's evaluation:
   fires only when that operand is provably pure — a bare identifier. *)
let p10 x = x && false (* FIRE *)
let p11 x = x || true (* FIRE *)

(* The same absorbing shapes over a possibly effectful operand stay
   clean: no purity evidence, no finding. *)
let n1 () = effect_bool () && false
let n2 () = effect_bool () || true

(* No constant operand. *)
let n3 x y = x && y

(* Two constants are a constant expression, not a redundant operand. *)
let n4 = true && false

(* Shadowed operator (adversarial): a local ( && ) is not Stdlib.(&&). *)
let n5 x =
  let ( && ) a b = a || b in
  x && true
