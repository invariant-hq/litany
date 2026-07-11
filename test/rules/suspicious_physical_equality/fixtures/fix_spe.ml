(* Fixture for suspicious-physical-equality: positives carry the FIRE
   marker; the rest are the prior implementation's conservative exclusions. *)

let s = "litany"
let by = Bytes.of_string s
let fl = 1.0
let arr = [| 1 |]
let i32 = 0l
let n64 = 0n
let tup = (1, 2)
let fn x = x + 1

(* Proven-boxed operands under the canonical operators. *)
let p1 = s == "other" (* FIRE *)
let p2 = by != by (* FIRE *)
let p3 = fl == 2.0 (* FIRE *)
let p4 = arr == [| 2 |] (* FIRE *)
let p5 = i32 == 1l (* FIRE *)
let p6 = n64 != 1n (* FIRE *)
let p7 = tup == (3, 4) (* FIRE *)
let p8 = fn == fn (* FIRE *)
let p9 = 1 == 2 || s != s (* FIRE *)

(* Immediate operands: physical comparison is exact there. *)
let n1 = 1 == 2
let n2 = 'a' != 'b'
let n3 = true == false
let n4 = () == ()

(* Unknown immediacy stays clean: variables, user types, abbreviations,
   parameterized predefs. *)
let n5 a b = a == b

type t = A | B

let n6 = A == B

type alias = string

let n7 (x : alias) (y : alias) = x == y
let n8 = Some s == Some s
let n9 = [ 1 ] == [ 1 ]

(* Shadowed operators and partial applications. *)
let n10 (a : string) b =
  let ( == ) _ _ = false in
  a == b

let n11 (a : string) = Stdlib.( == ) a
