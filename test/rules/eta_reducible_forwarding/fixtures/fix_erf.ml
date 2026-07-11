(* Fixture for eta-reducible-forwarding: each FIRE marker sits on a
   binding that only forwards its parameters, in order, to a single
   identifier callee; every other binding is a negative from the spec
   plus the omitted-label adversarial. Warnings 6 (omitted labels in a
   total application) and 39 (unused rec) are what two negatives
   exhibit and are disabled for this library alone (see the fixture
   dune). *)

let my_id x = x
let my_add3 a b c = a + b + c
let labeled_add ~x ~y = x + y
let step x = x + 1
let g_opt ?(d = 0) x = x + d
let make_h () x = x + 1

(* A one-parameter forward. *)
let wrapper x = my_id x (* FIRE *)

(* Three parameters, in order. *)
let xx p q r = my_add3 p q r (* FIRE *)

(* An operator forward is still a forward. *)
let my_add x y = x + y (* FIRE *)

(* rec with a distinct callee: the forwarding proof stands. *)
let rec go x = step x (* FIRE *)

(* Adversarial: a partial forward is still eta-reducible — the type is
   the callee's remaining arrows. *)
let partial x = my_add3 x (* FIRE *)

(* Argument reuse: positional identity fails. *)
let good_wrapper x = my_add x x

(* Reordered: not a forward. *)
let flipper x y z = my_add3 y z x

(* Labeled application refuses. *)
let labeled_wrapper a b = labeled_add ~x:a ~y:b

(* The probe-pinned erasure case: the application commits [?d], and the
   omission in the argument list refuses the shape. *)
let opt_wrapper x = g_opt x

(* Extra argument: count mismatch. *)
let extra x y = my_add3 x y 0

(* The callee is not an identifier: forcing it once per call differs. *)
let forced x = (make_h ()) x

(* The callee is the binding: [let rec self = self] is illegal and the
   wrapper is not a wrapper. *)
let rec self x = self x

(* Adversarial: labels omitted in a total application still carry the
   callee's labels — refused, exactly like the spelled-out form. *)
let omitted a b = labeled_add a b

let all () =
  wrapper 1 + xx 2 3 4 + my_add 5 6 + go 7 + partial 8 9 10 + good_wrapper 11
  + flipper 12 13 14 + labeled_wrapper 15 16 + opt_wrapper 17 + extra 18 19
  + forced 20 + self 21 + omitted 22 23
