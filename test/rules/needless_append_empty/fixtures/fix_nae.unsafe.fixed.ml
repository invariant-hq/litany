(* Fixture for needless-append-empty: positives carry the FIRE marker;
   every other case is a spec negative plus one adversarial extra. *)

let xs = [ 1; 2; 3 ]
let name = "n"
let line = "l"

(* The list legs — both callees, both sides. *)
let p1 acc = acc (* FIRE *)
let p2 = xs (* FIRE *)
let p3 tail = tail (* FIRE *)
let p4 t = t (* FIRE *)

(* The string legs — both callees, both sides. *)
let p5 = name (* FIRE *)
let p6 = line (* FIRE *)
let p7 = name (* FIRE *)
let p8 = line (* FIRE *)

(* A both-empty operation reports once, as the left-empty leg. *)
let p9 : int list = [] (* FIRE *)

(* negative: a singleton is not empty. *)
let n1 x l = [ x ] @ l

(* negative (adversarial): a shadowed (@) resolves elsewhere — and
   Filename.concat dir "" is not the neutral case there. *)
let n2 dir =
  let ( @ ) = Filename.concat in
  dir @ ""

(* negative: no empty operand. *)
let n3 a b = a @ b
let n4 s t = s ^ t

(* negative: different functions, different rule families. *)
let n5 a b = String.concat "" [ a; b ]
let n6 b = Bytes.cat b Bytes.empty

(* negative (adversarial extra): a partial application is not the
   saturated operation. *)
let n7 : int list -> int list = List.append []
