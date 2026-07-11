(* Fixture for redundant-option-roundtrip: positives carry the FIRE marker;
   every other case is a negative lookalike ported from the prior implementation's
   conservative exclusions, plus fresh shadowing/aliasing adversaries. *)

let o = Some 1

(* The canonical roundtrip. *)
let p1 = List.nth_opt (Option.to_list o) 0 (* FIRE *)

(* Module aliases carry the aliased declarations' identities. *)
module L = List
module O = Option

let p2 = L.nth_opt (O.to_list o) 0 (* FIRE *)

(* Other indices — literal or not — are different questions. *)
let n1 = List.nth_opt (Option.to_list o) 1
let n2 = List.nth_opt (Option.to_list o) (-1)
let idx = 0
let n3 = List.nth_opt (Option.to_list o) idx

(* Partial application. *)
let n4 = List.nth_opt (Option.to_list o)

(* A different outer callee. *)
let n5 = List.nth (Option.to_list o) 0

(* Operator composition is not a direct application chain. *)
let n6 = Option.to_list o |> fun l -> List.nth_opt l 0

(* Work between the two conversions is not a roundtrip. *)
let n7 = List.nth_opt (List.rev (Option.to_list o)) 0

(* Let-bound aliases mint fresh declarations and never match. *)
let n8 =
  let to_list = Option.to_list in
  List.nth_opt (to_list o) 0

let n9 =
  let nth_opt = List.nth_opt in
  nth_opt (Option.to_list o) 0

(* Shadowed identities never match. *)
let n10 =
  let module Option = struct
    let to_list = function Some x -> [ x ] | None -> []
  end in
  List.nth_opt (Option.to_list o) 0

let n11 =
  let module List = struct
    let nth_opt l (_ : int) = match l with [] -> None | x :: _ -> Some x
  end in
  List.nth_opt (Option.to_list o) 0
