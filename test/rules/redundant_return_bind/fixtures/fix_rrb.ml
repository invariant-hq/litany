(* Fixture for redundant-return-bind: positives carry the FIRE marker; the
   rest are the spec's negatives plus adversarial lookalikes. Lwt pairs
   resolve to nothing in this workspace and are exercised nowhere. *)

let f x = Some (x + 1)
let g x = Ok (x + 1)

(* A freshly returned value bound straight into a callback. *)
let p1 = Option.bind (Option.some 1) f (* FIRE *)
let p2 : (int, string) result = Result.bind (Result.ok 2) g (* FIRE *)

(* An arbitrary scrutinee is the operator's job. *)
let o = Some 3
let n1 = Option.bind o f

(* Constructor returns: [Some]/[Ok] by
   predefined/global constructor identity. *)
let p3 = Option.bind (Some 4) f (* FIRE *)
let p4 : (int, string) result = Result.bind (Ok 7) g (* FIRE *)

(* Error is not return. *)
let n3 : (int, string) result = Result.bind (Error "boom") g

(* Partial application refuses by arity. *)
let n4 : (int -> int option) -> int option = Option.bind (Option.some 5)

(* Adversarial: an applied non-return scrutinee. *)
let n5 = Option.bind (Option.map succ o) f

(* A local pair never fires. *)
module Mon = struct
  let bind m fn = fn m
  let return x = x
end

let n6 = Mon.bind (Mon.return 6) (fun x -> x + 1)
