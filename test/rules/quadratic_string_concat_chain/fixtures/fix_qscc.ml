(* Fixture for quadratic-string-concat-chain: positives carry the FIRE
   marker; the rest are the spec's negatives plus an adversarial nesting.
   Longer chains report once, at the innermost matching node
   (containment) — pinned by fix_qscc_nested.ml. *)

let a = "a"
let b = "b"
let c = "c"

(* Three segments right-associate: the right operand is itself a chain. *)
let p1 = a ^ b ^ c (* FIRE *)

(* Two segments are the operator's job. *)
let n1 = a ^ b

(* Left parenthesization keeps the right operand simple: clean in v1. *)
let n2 = (a ^ b) ^ c

(* A rebound (^) is a different identity. *)
let n3 =
  let ( ^ ) = ( +. ) in
  1.0 ^ 2.0 ^ 3.0

(* One dynamic segment is not a chain. *)
let n4 = a ^ string_of_int 7

(* Already through a formatter. *)
let n5 = Printf.sprintf "%s%s%s" a b c

(* Adversarial: String.cat nests the same shape under other identities. *)
let n6 = String.cat a (String.cat b c)
