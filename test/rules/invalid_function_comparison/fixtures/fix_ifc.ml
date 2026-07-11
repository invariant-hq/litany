(* Fixture for invalid-function-comparison: positives carry the FIRE
   marker; the rest are the prior implementation's conservative exclusions. *)

let f x = x + 1
let g x = x + 2

(* Every canonical comparison with a direct function operand. *)
let p1 = f = g (* FIRE *)
let p2 = f <> g (* FIRE *)
let p3 = f < g (* FIRE *)
let p4 = f > g (* FIRE *)
let p5 = f <= g (* FIRE *)
let p6 = f >= g (* FIRE *)
let p7 = compare f g (* FIRE *)
let p8 = min f g (* FIRE *)
let p9 = max f g (* FIRE *)
let p10 = Stdlib.( = ) f g (* FIRE *)
let p11 = 1 = 2 || f = g (* FIRE *)

(* Non-function operands. *)
let n1 = 1 = 2
let n2 = compare "a" "b"
let n3 = min 1 2
let n4 = (f, 1) = (g, 2)

(* Physical equality is a different rule. *)
let n5 = f == g

(* Arrow types behind an abbreviation stay clean. *)
type arrow = int -> int

let n6 (x : arrow) (y : arrow) = x = y

(* Shadowed comparisons and partial applications. *)
let n7 =
  let ( = ) _ _ = false in
  f = g

let n8 = Stdlib.compare f
let n9 = Hashtbl.hash f = Hashtbl.hash g
