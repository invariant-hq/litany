(* Fixture for redundant-conversion-roundtrip: positives carry the FIRE
   marker; the rest are the spec's excluded directions plus adversarial
   rebindings. *)

let n = 42
let b = true
let c = 'x'
let n32 = 1l
let n64 = 1L
let nn = 1n
let s = "42"
let by = Bytes.of_string "abc"
let suffix = "0"

(* Unboxed pairs: the roundtrip returns the very value (Safe fix). *)
let p1 = n (* FIRE *)
let p2 = b (* FIRE *)
let p3 = c (* FIRE *)

(* Pipeline spellings collapse to direct applications. *)
let p4 = n (* FIRE *)

(* Boxed pairs: reported, no fix (a fresh allocation). *)
let p5 = Int32.of_string (Int32.to_string n32) (* FIRE *)
let p6 = Int64.of_string (Int64.to_string n64) (* FIRE *)
let p7 = n64 |> Int64.to_string |> Int64.of_string (* FIRE *)
let p8 = Nativeint.of_string (Nativeint.to_string nn) (* FIRE *)

(* The copying pair: an equal, fresh string. *)
let p9 = Bytes.to_string (Bytes.of_string s) (* FIRE *)

(* Alias transparency. *)
module C = Char

let p10 = c (* FIRE *)

(* The canonicalizing direction is not an identity. *)
let n1 = string_of_int (int_of_string s)

(* Rebuilding mutable bytes must stay a fresh copy. *)
let n2 = Bytes.of_string (Bytes.to_string by)

(* Work between the conversions. *)
let n3 = int_of_string (string_of_int n ^ suffix)

(* A cross-module composition is no table row. *)
let n4 = int_of_string (Int64.to_string n64)

(* The float pair is lossy and excluded. *)
let n5 = Float.of_string (Float.to_string 1.5)

(* A shadowed inner conversion resolves elsewhere (adversarial). *)
let n6 =
  let string_of_int _ = s in
  int_of_string (string_of_int n)

(* A let-bound alias is identity, not dataflow (adversarial). *)
let n7 =
  let parse = int_of_string in
  parse (string_of_int n)
