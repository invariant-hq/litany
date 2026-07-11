(* Fixture for needless-identity-function: positives carry the FIRE
   marker — inline forwarding wrappers in argument position of a full,
   unlabeled application. Every other line is a negative: the
   named-binding exclusions plus structural lookalikes adopted from the
   prior implementation's cases, moved into argument position. *)

let inc x = x + 1
let add x y = x + y + 0
let tagged ~tag x = (tag, x)
let app1 f = f 1
let app2 f = f 1 2
let app3 f = f 1 2 3
let apphof g = g inc 1
let pair3 f g n = (f 1, g 2, n)

(* Unary and binary forwarding wrappers, and a dotted callee. *)
let p1 = app1 (fun x -> inc x) (* FIRE *)
let p2 = app2 (fun x y -> add x y) (* FIRE *)
let p3 = List.map (fun s -> String.length s) [ "a" ] (* FIRE *)

(* A partial forward of a wider callee is still an eta wrapper. *)
let p4 = app1 (fun x -> add x) 5 (* FIRE *)

(* Two forwarding arguments of one application are two findings. *)
let p5 =
  pair3
    (fun first_value -> inc first_value) (* FIRE *)
    (fun second_value -> inc second_value) (* FIRE *)
    0

(* Arity is unbounded: a three-argument forward and a partial forward of
   two of three arguments both fire. *)
let add3 x y z = x + y + z
let p6 = app3 (fun x y z -> add3 x y z) (* FIRE *)
let p7 = app2 (fun x y -> add3 x y) 3 (* FIRE *)

(* The named-binding narrowing: a named let binding is the author's seam —
   the name is the point — and stays clean however exact the forward. *)
let n1 = fun x -> inc x
let n2 = fun x y -> add x y

(* The [let g x = f x] sugar is a named binding too. *)
let n3 x = inc x

(* A wrapper outside argument position: a list element, and the callee
   of an immediate application. *)
let n4 = [ (fun x -> inc x) ]
let n5 = (fun x -> inc x) 5

(* An argument of a labeled application sits outside the unlabeled
   argument view. *)
let n6 = tagged ~tag:0 (fun x -> inc x)

(* Curried multi-stage wrappers are two functions, neither a full
   forward. *)
let n7 = app1 (fun x -> fun y -> add x y) 2

(* A staged callee is not a direct identifier. *)
let n8 = app1 (fun x -> (add 1) x)

(* Missing, extra, reordered, and duplicated arguments. *)
let n9 = app2 (fun x _y -> inc x)
let n10 = app1 (fun x -> add x 1)
let n11 = app2 (fun x y -> add y x)
let n12 = app2 (fun x _y -> add x x)

(* Labeled or optional shapes on either side of the wrapper's body. *)
let n13 = app1 (fun x -> tagged ~tag:1 x)

(* A non-variable parameter. *)
let n14 = List.map (fun (x, y) -> add x y) [ (1, 2) ]

(* A callee bound by a parameter forwards nothing external. *)
let n15 = apphof (fun f x -> f x)

(* No application body, and a cases body. *)
let n16 = app1 (fun x -> (x, x))
let n17 = app2 (fun x -> function 0 -> x | m -> m)

(* Shadowing (adversarial): the applied [x] is the second parameter's
   identity, not the first's — spelling matches, declarations do not. *)
let n18 = app2 ((fun x x -> add x x) [@warning "-27"])
