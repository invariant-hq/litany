(* Fixture for redundant-not-not: positives carry the FIRE marker;
   every other case is a spec negative plus one adversarial extra. *)

let ready = Sys.word_size > 32
let flag = Sys.word_size > 64

(* All the pair spellings. *)
let p1 = not (not ready) (* FIRE *)
let p2 x = not (not (x = 0)) (* FIRE *)
let p3 = not @@ not flag (* FIRE *)
let p4 b = Bool.not (not b) (* FIRE *)

(* negative: a single negation. *)
let n1 = not ready

(* negative (adversarial): a rebound not refuses, either position. *)
let n2 x =
  let not b = b in
  not (not x)

(* negative: lnot is integer complement, not boolean negation. *)
let n3 x = not (lnot x = 0)

(* negative: a function that merely rhymes. *)
let not' b = b
let n4 b = not (not' b)

(* negative: one negation of a comparison — the operator-flip family
   is a separate rule candidate. *)
let n5 a b = not (a <> b)

(* negative (adversarial extra): an aliased not is a local identity,
   not the Stdlib declaration. *)
let n6 x =
  let f = not in
  f (f x)
