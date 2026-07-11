(* Fixture for suspicious-general-float-equality: positives carry the
   FIRE marker; every other case is a spec carve-out or negative plus
   one adversarial extra. *)

let x = Sys.time ()
let y = Sys.time ()

(* Plain float equality. *)
let p1 = x = y (* FIRE *)

(* Computed operands. *)
let p2 a b c = a +. b <> c (* FIRE *)

(* A non-anchor literal is exactly the classic bug. *)
let p3 weight = weight = 0.1 (* FIRE *)

(* nan through an alias is not the nan constant — identity, not
   dataflow: invalid-nan-comparison stays silent there and this rule
   owns the float comparison. *)
let p4 =
  let m = nan in
  x = m (* FIRE *)

(* negative: zero carve-outs, every spelling the lexer allows. *)
let n1 = x = 0.0
let n2 = x <> -0.0
let n3 = x = 0.
let n4 = x = 0x0p0

(* negative: infinity carve-outs, both modules. *)
let n5 = x = infinity
let n6 = x <> Float.neg_infinity

(* negative: nan constants are invalid-nan-comparison's — the exact
   partition, pinned in both fixtures. *)
let n7 = x = nan
let n8 = x <> Float.nan

(* negative: the blessed exact-comparison spelling. *)
let n9 = Float.equal x y

(* negative (adversarial): a shadowed operator resolves elsewhere. *)
let n10 =
  let ( = ) (a : float) (b : float) = a < b in
  x = y

(* negative: an abbreviation head is conservatively clean. *)
type celsius = float

let n11 (t : celsius) (u : celsius) = t = u

(* negative: orderings are meaningful on floats. *)
let n12 = x < y

(* negative (adversarial extra): physical equality is another
   operator, suspicious-physical-equality's question. *)
let n13 = x == y
