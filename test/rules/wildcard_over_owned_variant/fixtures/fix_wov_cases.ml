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
