(* Fixture for needless-and-binding: each FIRE marker sits on the
   pattern of a recursive-group binding that is mutually reachable with
   no sibling; every other group is a spec negative plus one
   adversarial extra. Warning 39 is silent on every positive (it needs
   the whole group inert) and disabled here (see the fixture dune) for
   the partition negative — the whole-inert group that belongs to
   suspicious-rec-without-recursion, never to this rule. *)

(* Spec positive 1: double rides a chain it doesn't need. *)
let rec is_even n = n = 0 || is_odd (n - 1)
and is_odd n = n <> 0 && is_even (n - 1)
and double (* FIRE *) x = x + x

(* Spec positive 2: memo extracts above the group as a plain let, fib
   as its own let rec — one finding per wasted chain link. *)
let rec fib (* FIRE *) n = if n < 2 then n + !memo else fib (n - 1)
and memo (* FIRE *) = ref 0

(* Spec positive 3: each self-recursive, no cross edges — this rule's
   whole yield is beyond warning 39. *)
let rec selfa (* FIRE *) x = selfa x
and selfb (* FIRE *) y = selfb y

(* Spec positive 4: expression-level groups dispatch too. *)
let expr_level () =
  let rec go_around (* FIRE *) x = go_around (x - 1)
  and go_label (* FIRE *) = "the label the loop reports" in
  ignore go_around;
  go_label

(* Spec positive 5, the decided case: a one-directional chain passes
   the partition gate, yet neither binding sits in a cycle — both
   report, since a plain sequence needs no chain at all. *)
let rec ida (* FIRE *) x = x
and idb (* FIRE *) y = ida y

(* Adversarial: an inner rebinding of a sibling's name contributes no
   edge — a spelling-based graph would see a cycle here and stay
   silent; the identity graph reports both. *)
let rec pea (* FIRE *) x = qea x

and qea (* FIRE *) y =
  let pea z = z in
  pea y

(* Spec negative 1: one cycle, silent. *)
let rec even2 n = if n = 0 then true else odd2 (n - 1)
and odd2 n = if n = 0 then false else even2 (n - 1)

(* Spec negative 2, the exact partition: no edges at all is the sibling
   rule's finding, never this one's. *)
let rec pa = 1
and pb = 2

(* Spec negative 3: a two-cycle, silent. *)
let rec cyc_f x = cyc_g x
and cyc_g y = cyc_f y

(* Spec negative 4: a singleton group is refused by the two-binding
   gate — and the body's use is self-use through the fresh rec ident
   besides. *)
let outer_s x = x + 1

let singleton () =
  let rec outer_s y = outer_s y in
  outer_s 3
