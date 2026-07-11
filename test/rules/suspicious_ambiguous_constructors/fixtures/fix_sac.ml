(* Fixture for suspicious-ambiguous-constructors: each FIRE marker sits
   on a variant constructor named after a predefined or stdlib
   constructor; every other declaration is a spec negative plus one
   adversarial extra. Warnings 41/42 — the compiler's use-site half of
   this judgment — are off in every mainstream default, which is the
   rule's whole gap. *)

(* Spec positive 1: a homegrown result, scoped so the toplevel [result]
   stays the stdlib's for the re-export negative below. *)
module Res = struct
  type 'a result =
    (* Both names shadow the stdlib result's constructors. *)
    | Error (* FIRE *) of string
    | Ok (* FIRE *) of 'a
end

(* Spec positive 2: a homegrown option under a fresh type name. *)
type str_option =
  (* Both names shadow the predef option's constructors. *)
  | Some (* FIRE *) of string
  | None (* FIRE *)

(* Spec positive 3: only the constructor reports — the type-name
   shadowing is not this rule's claim. *)
module Opt = struct
  type 'a option = Nothing | Some of 'a (* FIRE *)
end

(* Spec positives 4 and 5: nested structures dispatch, and both list
   constructors report — the declaration the predef-identity refusals
   of every list rule exist for. *)
module Nested = struct
  type t =
    (* Both list constructors report. *)
    | ( :: ) (* FIRE *) of int * t
    | [] (* FIRE *)
end

(* Spec negative 1: option re-export — manifest present, the
   constructors already exist by construction. *)
type 'a maybe = 'a option = None | Some of 'a

(* Spec negative 2: result re-export. *)
type ('c, 'd) res = ('c, 'd) result = Ok of 'c | Error of 'd

(* Spec negative 3: no listed name. *)
type 'a opt = Something of 'a | Nothing

(* Spec negative 4: near-miss spelling is not a match — exact names
   only. *)
type near = Okay of int

(* Adversarial: an extension constructor shadows Error identically but
   is not a variant declaration — the recorded false negative, pinned
   silent. *)
exception Error of string
