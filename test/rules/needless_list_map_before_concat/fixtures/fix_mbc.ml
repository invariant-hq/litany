(* Fixture for needless-list-map-before-concat: positives carry the FIRE
   marker; every other case is a negative lookalike ported from the old
   rule's conservative exclusions, plus fresh shadowing/aliasing
   adversaries. *)

let xs = [ 1; 2; 3 ]
let dup x = [ x; x ]

(* Both concatenation spellings, with named and literal functions. *)
let p1 = List.concat (List.map dup xs) (* FIRE *)
let p2 = List.flatten (List.map dup xs) (* FIRE *)
let p3 = List.concat (List.map (fun x -> [ x; x + 1 ]) xs) (* FIRE *)

(* Module aliases carry the aliased declarations' identities. *)
module L = List

let p4 = L.concat (L.map dup xs) (* FIRE *)

(* The fused form is the fix target, not a positive. *)
let n1 = List.concat_map dup xs

(* The compiler collapses [|>] on a saturated map into a direct
   application — a positive under the typed view (delta from the old
   syntax-view rule, which kept pipelines clean). *)
let p5 = List.map dup xs |> List.concat (* FIRE *)

(* Piping the input leaves [List.map dup] a partial-application callee, a
   nested apply node the two-argument shape refuses. *)
let n3 = xs |> List.map dup |> List.concat

(* The concatenated argument must be exactly a two-argument map. *)
let n4 = List.concat [ List.map dup xs ]
let n5 = List.concat (List.rev (List.map dup xs))

(* map-map and filter_map are different shapes. *)
let n6 = List.map dup (List.map succ xs)
let n7 = List.filter_map (fun x -> Some [ x ]) xs

(* ListLabels.map is a different declaration. *)
let n8 = List.concat (ListLabels.map ~f:dup xs)

(* Let-bound aliases mint fresh declarations and never match. *)
let n9 =
  let concat = List.concat in
  concat (List.map dup xs)

let n10 =
  let map = List.map in
  List.concat (map dup xs)

(* Shadowed identities never match. *)
let n11 =
  let module List = struct
    let map = Stdlib.List.map
    let concat _ = ([] : int list)
  end in
  List.concat (List.map dup xs)
