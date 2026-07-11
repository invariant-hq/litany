(* Fixture for manual-record-update: each FIRE marker sits on a record
   expression rebuilt field by field from one base; every other record
   is a negative from the spec plus the adversarial cross-type case. *)

type t = { x : int; y : int; z : int }
type t0 = { e : int; g : int }
type t1 = { e : int; g : int; h : int }
type m = { mutable a : int; b : int }

let r = { x = 1; y = 2; z = 3 }
let r2 = { x = 4; y = 5; z = 6 }

module M = struct
  let default = { x = 0; y = 0; z = 0 }
end

(* Full rebuild of an immutable record: it is the base itself. *)
let clone = { x = r.x; y = r.y; z = r.z } (* FIRE *)

(* Two copies, one override: { r with z = 18 } longhand. *)
let update = { x = r.x; y = r.y; z = 18 } (* FIRE *)

(* The cross-base field is an override, spelled out. *)
let cross = { x = r.x; y = r.y; z = r2.z } (* FIRE *)

(* The base is any identifier path, Pdot included. *)
let from_m = { x = M.default.x; y = M.default.y; z = 0 } (* FIRE *)

(* No base reaches two copies: the deliberate >= 2 narrowing. *)
let below = { x = r.x; y = 1; z = r2.z }

(* Adversarial: same-named labels of a different type. Label identity
   refuses — t0.e and t1.e are different declarations, and a cross-type
   rewrite here would not typecheck. *)
let f0 : t0 = { e = 7; g = 8 }
let widened : t1 = { e = f0.e; g = f0.g; h = 1 }

(* The base is not an identifier: re-evaluating it under [with] would
   change effects. *)
let get _ = r
let through_call = { x = (get r).x; y = (get r).y; z = 0 }

(* Full rebuild of a mutable record: the deliberate copy idiom. *)
let copy_mutable (a0 : m) = { a = a0.a; b = a0.b }

(* Punned fields elaborate to bare identifiers, not accesses. *)
let punned x y = { x; y; z = 15 }

(* Already the remedy: the [with] extension refuses at the view. *)
let remedy = { r with z = 15 }

(* Keep every declaration used. *)
let sum =
  clone.z + update.z + cross.z + from_m.z + below.z + widened.h + through_call.z
  + (copy_mutable { a = 1; b = 2 }).b + (punned 1 2).z + remedy.z + f0.g
