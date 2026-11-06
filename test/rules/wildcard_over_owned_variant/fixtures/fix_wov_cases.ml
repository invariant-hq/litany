(* Fixture for wildcard-over-owned-variant: positives carry the FIRE
   marker; every other line is a negative. *)

type local = A | B | C

(* A variant of this unit. *)
let local x = match x with A -> 1 | _ -> 0 (* FIRE *)

(* A variant of another module of this wrapped library. *)
let same_library (s : State.t) =
  match s with Open -> "open" | _ -> "closed" (* FIRE *)

(* Every case named: what the rule asks for. *)
let named (s : State.t) =
  match s with Open -> "open" | Done | Dropped -> "closed"

(* An or-pattern names the variant too. *)
let or_arm x = match x with A | B -> 1 | _ -> 0 (* FIRE *)

(* A guarded wildcard is a decision, not a catch-all. *)
let guarded x n = match x with A -> 1 | _ when n > 0 -> 2 | B | C -> 0

(* A predefined variant grows with the compiler, not with this code. *)
let predefined (o : int option) = match o with Some _ -> 1 | _ -> 0

(* A variant of another library ends in a catch-all, unless the option
   says the code owns it; this suite runs without it. *)
let other_library (c : Fix_wov_other.Color.t) = match c with Red -> 1 | _ -> 0

(* A wildcard nested in a pattern binds a field, it names no case. *)
let nested x = match x with Some A -> 1 | Some _ -> 2 | None -> 0

(* An exception arm is not a value arm. *)
let exn_arm f = match f () with A -> 1 | B | C -> 0 | exception _ -> -1

(* A submodule's variant is this unit's too. *)
module Inner = struct
  type t = Open | Shut
end

let inner (s : Inner.t) = match s with Inner.Open -> 1 | _ -> 0 (* FIRE *)

(* An alias names the module it aliases: another library's variant stays
   another library's, and this unit's stays this unit's. *)
module Aliased_other = Fix_wov_other.Color

let aliased_other (c : Aliased_other.t) =
  match c with Aliased_other.Red -> 1 | _ -> 0

module Aliased_stdlib = Either

let aliased_stdlib x = match x with Aliased_stdlib.Left _ -> 1 | _ -> 0

module Aliased_inner = Inner

let aliased_inner (s : Aliased_inner.t) =
  match s with Aliased_inner.Open -> 1 | _ -> 0 (* FIRE *)

(* An extensible variant has no last case to name: its wildcard is required. *)
type open_ended = ..
type open_ended += First | Second

let extensible x = match x with First -> 1 | _ -> 0
let (_ : open_ended) = Second

(* A match whose arms name no constructor names no variant. *)
let no_constructor n = match n with 0 -> 1 | _ -> 0
