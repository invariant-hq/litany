(* Fixture for suspicious-polymorphic-compare-on-opaque: positives carry
   the FIRE marker; the rest are the spec's negatives plus adversarial
   lookalikes. Cross-unit functor instances live in Spco_lib. *)

let s1 = Spco_lib.set_a
let s2 = Spco_lib.set_b
let m1 = Spco_lib.map_a
let m2 = Spco_lib.map_b

(* Cross-unit Set/Map instances: the type head walks to the functor
   body's declaration. *)
let p1 = s1 = s2 (* FIRE *)
let p2 = compare m1 m2 (* FIRE *)
let p3 = min s1 s2 (* FIRE *)
let p4 = s1 < s2 (* FIRE *)

(* Hashtbl.t compares by bucket layout. *)
let h1 : (string, int) Hashtbl.t = Hashtbl.create 3
let h2 : (string, int) Hashtbl.t = Hashtbl.create 3
let p5 = h1 = h2 (* FIRE *)
let p6 = h1 <> h2 (* FIRE *)

(* Membership hashes and compares the subject structurally. *)
let p7 = List.mem h1 [ h2 ] (* FIRE *)
let p8 = List.assoc s1 [ (s2, 0) ] (* FIRE *)

(* A container of opaque values proves through the walk. *)
let p9 = [ h1 ] = [ h2 ] (* FIRE *)

(* The module's own equal and compare are the remedy. *)
let n1 = Spco_lib.IntSet.equal s1 s2
let n2 = Spco_lib.IntSet.compare s1 s2

(* Comparing cardinals compares ints. *)
let n3 = Spco_lib.IntSet.cardinal s1 = Spco_lib.IntSet.cardinal s2

(* Physical comparison is suspicious-physical-equality's territory. *)
let n4 = s1 == s2

(* Abbreviation heads are not expanded (house conservatism, documented
   false negative). *)
type cache = (string, int) Hashtbl.t

let c1 : cache = Hashtbl.create 3
let n5 = c1 = c1

(* A functor instance declared in the linted unit itself resolves through
   the matches_type local-alias hop (landed with the next-10 merge):
   [IS.t] reaches [Stdlib.Set.Make.t]'s identity, so the comparison
   fires. *)
module IS = Set.Make (Int)

let p10 = IS.empty = IS.add 1 IS.empty (* FIRE *)

(* Tuple components await a version-stable Ttuple seam — pinned
   clean. *)
let n7 = (s1, 0) = (s2, 1)

(* A shadowed operator resolves locally (adversarial). *)
let n8 =
  let ( = ) = Spco_lib.IntSet.equal in
  s1 = s2

(* A foreign type merely spelled Hashtbl.t is its own identity
   (adversarial). *)
let n9 = Spco_lib.fake = Spco_lib.fake
