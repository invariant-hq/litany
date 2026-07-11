(* Fixture for redundant-guard-true: positives carry the FIRE marker;
   every other case is a negative lookalike from the spec plus one
   adversarial extra. *)

(* Leftover from editing a real guard: fires, fix withheld (not the
   final arm). *)
let p1 x = match x with n when true -> n | _ -> 0 (* FIRE *)

(* Function form: fires, fix withheld (not the final arm). *)
let p2 = function
  | Some x when true -> x (* FIRE *)
  | None -> 0
  | Some _ -> -1

(* Handler form, final arm: the fix ships. *)
let p3 f = try f () with Failure _ -> 0 (* FIRE *)

(* Final arm of a multi-handler try: the fix ships here too. *)
let p4 f = try f () with Not_found -> 1 | Failure _ -> 2 (* FIRE *)

(* An always-false guard: the dead-arm message, never a fix. *)
type v = A | B

let vs = [ A; B ]
let p5 v = match v with A -> 1 | B when false -> 2 | B -> 3 (* FIRE *)

(* A commented guard still fires; the comment refuses the fix. *)
let p6 f = try f () with Failure _ when (* why *) true -> 0 (* FIRE *)

(* negative: a real guard *)
let n1 p x = match x with y when p y -> y | _ -> 0

(* negative: not a literal guard — the true && is
   redundant-boolean-operator's node inside the guard *)
let n2 debug x = match x with y when true && debug -> y | _ -> 0

(* negative: a named flag — there is no constant propagation *)
let debug = true
let n3 x = match x with y when debug -> y | _ -> 0

(* negative (adversarial extra): a comparison of literals is not the
   literal itself *)
let n4 x = match x with y when true = true -> y | _ -> 0
