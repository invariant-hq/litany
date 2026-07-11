(* Fixture for needless-mutually-recursive-types: each FIRE marker sits
   on the name of an and-chained declaration that is mutually reachable
   with no sibling; every other declaration is a spec negative plus one
   adversarial extra. Nothing in the compiler diagnoses any of this. *)

(* Spec positive 1: a chain with no cycle — every member reports,
   including the head nothing points back at. *)
type t1 = A (* FIRE *) of { a : t2; b : t3 }
and t2 = B of t3 (* FIRE *)
and t3 = C of int (* FIRE *)

(* Spec positive 2: the cycle is clean, the rider reports. *)
type q1 = Q1 of q2
and q2 = Q2 of q1
and q3 = Q3 of q1 (* FIRE *)

(* Spec positive 3: the nine-member group — the g5/g6 cycle is clean,
   every chained member reports, the manifest-only tail included. *)
type g1 = G1 of g2 (* FIRE *)
and g2 = G2 of g3 (* FIRE *)
and g3 = G3 of g4 (* FIRE *)
and g4 = G4 of g5 (* FIRE *)
and g5 = G5 of g6
and g6 = G6 of g5 * g7
and g7 = G7 of int (* FIRE *)
and g8 = G8 of g5 (* FIRE *)
and g9 = int (* FIRE *)

(* Spec positive 4: under nonrec no sibling edge can exist — every
   member of a multi-declaration nonrec group reports, derived rather
   than special-cased. *)
type nonrec na = NA (* FIRE *)
and nb = NB (* FIRE *)

(* Spec negative 1: one cycle, silent. *)
type c1 = D of c2
and c2 = E of c1

(* Spec negative 2: a singleton group has no 'and' to indict —
   self-recursion is what plain [type] already expresses. *)
type tree = Leaf | Node of tree * tree

(* Spec negative 3, adversarial shadowing: the outer sc never confuses
   the graph — edges are by identity, and the group's own sc is a fresh
   ident. The rider still reports; the cycle stays clean. *)
type sc = int

module Shadowing = struct
  type sa = SA of sb
  and sb = SB of sa
  and sc = SC of sa (* FIRE *)
end

(* Adversarial extra: a cycle closed through a constraint — the
   whole-declaration walk covers the churned constraints field, so both
   members are mutual and silent. *)
type y1 = Y1 of y1 y2
and 'a y2 = Y2 constraint 'a = y1
