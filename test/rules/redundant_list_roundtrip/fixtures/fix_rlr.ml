(* Fixture for redundant-list-roundtrip: positives carry the FIRE marker;
   every other case is a negative lookalike ported from the prior implementation's
   conservative exclusions, plus fresh shadowing/aliasing adversaries. *)

let xs = [ 1; 2; 3 ]

(* The canonical roundtrip. *)
let p1 = List.of_seq (List.to_seq xs) (* FIRE *)

(* Module aliases carry the aliased declarations' identities. *)
module L = List

let p2 = L.of_seq (L.to_seq xs) (* FIRE *)

(* Sequence work between the conversions is not a roundtrip. *)
let n1 = List.of_seq (Seq.map succ (List.to_seq xs))

(* The reverse direction is a different composition. *)
let s = List.to_seq xs
let n2 = List.to_seq (List.of_seq s)

(* A different outer target. *)
let n3 = Array.of_seq (List.to_seq xs)

(* The compiler collapses [|>] into direct applications, so the piped
   spelling is the same typedtree shape — a positive under the typed view
   (delta from the old syntax-view rule, which kept pipelines clean). *)
let p3 = xs |> List.to_seq |> List.of_seq (* FIRE *)

(* Let-bound aliases mint fresh declarations and never match. *)
let n5 =
  let to_seq = List.to_seq in
  List.of_seq (to_seq xs)

let n6 =
  let of_seq = List.of_seq in
  of_seq (List.to_seq xs)

(* Shadowed identities never match. *)
let n7 =
  let module List = struct
    let to_seq = Stdlib.List.to_seq
    let of_seq = Stdlib.List.of_seq
  end in
  List.of_seq (List.to_seq xs)
