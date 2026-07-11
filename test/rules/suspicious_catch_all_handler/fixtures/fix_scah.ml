(* Fixture for suspicious-catch-all-handler: positives carry the FIRE
   marker; every other case is a negative lookalike from the spec plus
   one adversarial extra. *)

let f () = 1
let g m = String.length m
let log e = ignore (Printexc.to_string e)
let debug = false

(* The single-case swallow. *)
let p1 = try f () with _ -> 0 (* FIRE *)

(* Wildcard among specific handlers: only the wildcard case fires. *)
let p2 = try f () with Failure m -> g m | _ -> 0 (* FIRE *)

(* The exception arm of a match — in scope. *)
let p3 = match f () with x -> x | exception _ -> 0 (* FIRE *)

(* Fires inside functor bodies. *)
module FOO (_ : sig end) = struct
  let x = try f () with _ -> 2 (* FIRE *)
end

(* negative: a specific exception *)
let n1 = try f () with Not_found -> 0

(* negative: named binder, the re-raise idiom *)
let n2 =
  try f ()
  with e ->
    log e;
    raise e

(* negative: named binder even when unused — warning 27's business *)
let n3 = try f () with _e -> 2

(* negative: a guarded wildcard is conditional, not a swallow-all *)
let n4 = try f () with _ when debug -> 0

(* negative: wildcard value cases are not exception handling *)
let n5 = match f () with _ -> 0

(* negative: or-patterns of specific exceptions; and the wildcard hidden
   in an or-pattern stays clean in v1 (recorded false negative —
   or-pattern wildcards are a separate rule candidate) *)
let n6 = try f () with Not_found | Failure _ -> 0
let n7 = try f () with Not_found | _ -> 0

(* negative (adversarial extra): an aliased wildcard is a named binder —
   Tpat_alias, not Tpat_any — and names at least admit re-raising *)
let n8 =
  try f ()
  with _ as e ->
    log e;
    3

(* Effect-handler cases neither block nor surface: the wildcard
   exception case still fires (the try_ view's contract, pinned). *)
type _ Effect.t += Ask : int Effect.t

let p5 h =
  try h () with _ -> 0 (* FIRE *) | effect Ask, k -> Effect.Deep.continue k 4
