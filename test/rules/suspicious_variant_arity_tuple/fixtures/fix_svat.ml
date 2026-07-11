(* Fixture for suspicious-variant-arity-tuple: each FIRE marker sits on
   a constructor argument that is exactly one parenthesized tuple type;
   every other declaration is a spec negative plus one adversarial
   extra. The compiler accepts both spellings silently — the boxed one
   costs an allocation and an indirection per construction and match. *)

(* Spec positive 1. *)
type vt = Pair of (int * int) (* FIRE *)

(* Spec positive 2: GADT spelling — probe-pinned same shape. *)
type g = B : (int * int) -> g (* FIRE *)

(* Spec positive 3: fires on the boxed constructor only. *)
type mixed = A | Pt (* FIRE *) of (float * float) | B2 of string

(* Spec positive 4: recursive payload, still one boxed pair. *)
type 'a node = Node of ('a * 'a node) (* FIRE *)

(* Spec negative 1: the flat form. *)
type flat = Pair2 of int * int

(* Spec negative 2: a tuple among several fields — no flat spelling has
   the same field count, the parentheses are load-bearing. *)
type two = C2 of (int * int) * string

(* Spec negative 3: the named-tuple remedy, silent by construction. *)
type point = int * int
type pt = Pt2 of point

(* Spec negative 4: [@@unboxed] requires the single-argument form — the
   boxing complaint is void. *)
type ub = Ub of (int * int) [@@unboxed]

(* Spec negative 5: a parenthesized arrow is one field with no flat
   alternative. *)
type fn = F of (int -> int)

(* Adversarial: the qualified attribute spelling is the same
   exemption. *)
type ub2 = Ub2 of (int * int) [@@ocaml.unboxed]
