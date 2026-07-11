(* Fixture for invalid-nan-comparison: positives carry the FIRE marker;
   the rest are the spec's negatives plus an adversarial shadow. *)

let x = 0.0

(* Every listed operator, both nan spellings, either operand side. *)
let p1 = x = nan (* FIRE *)
let p2 = x <> nan (* FIRE *)
let p3 = x < nan (* FIRE *)
let p4 = x > nan (* FIRE *)
let p5 = x <= Float.nan (* FIRE *)
let p6 = x >= Float.nan (* FIRE *)
let p7 = nan = x (* FIRE *)
let p8 = Float.nan < x (* FIRE *)

(* The intended test. *)
let n1 = Float.is_nan x

(* A shadowed nan is a different identity. *)
let n2 =
  let nan = 0.0 in
  x = nan

(* Identity, not dataflow: nan through an alias stays clean — the
   documented limit. *)
let n3 =
  let m = Float.nan in
  x = m

(* compare imposes a defined total order. *)
let n4 = compare x nan = 0

(* Other float constants are honest comparisons. *)
let n5 = x = Float.infinity

(* Physical equality is not constant — suspicious-physical-equality's
   territory. *)
let n6 = x == nan

(* Adversarial: a shadowing Float module mints local identities. *)
module Float = struct
  let nan = 1.0
end

let n7 = x = Float.nan
