(* Fixture for redundant-bind-return: positives carry the FIRE marker; the
   rest are the spec's negatives plus adversarial lookalikes. Lwt pairs
   resolve to nothing in this workspace and are exercised nowhere. *)

let o = Some 1

(* The bare return callback of each known-lawful Stdlib pair. *)
let p1 = Option.bind o Option.some (* FIRE *)
let r : (int, string) result = Ok 1
let p2 = Result.bind r Result.ok (* FIRE *)

(* An alias is the same identity. *)
module O = Option

let p3 = O.bind o O.some (* FIRE *)

(* A user identity monad never fires: pairs are audited claims, and local
   identities match nothing. *)
let n1 =
  let ( >>= ) x f = f x and return x = x in
  1 >>= return

(* The lambda legs: fun and
   function forms, constructor and function returns. *)
let p4 = Option.bind o (fun x -> Some x) (* FIRE *)
let p5 = Result.bind r (fun v -> Ok v) (* FIRE *)
let p6 = Option.bind o (fun x -> Option.some x) (* FIRE *)
let p7 = Option.bind o (function x -> Some x) (* FIRE *)

(* Not the bound value: Option.map territory. *)
let n3 f = Option.bind o (fun x -> Some (f x))

(* Adversarial: Result.error type-checks as the callback but is no
   return. *)
let r2 : (int, int) result = Ok 1
let n4 : (unit, int) result = Result.bind r2 Result.error

(* A third-party bind lookalike. *)
module Mon = struct
  let bind m f = f m
  let return x = x
end

let n5 = Mon.bind 1 Mon.return

(* Returning a different value than the bound one. *)
let n6 = Option.bind o (fun _x -> Option.some 7)

(* A guarded or multi-case function callback is a different shape. *)
let n7 = Option.bind o (function x when x > 0 -> Some x | x -> Some x)
