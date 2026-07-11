(* Fixture for quadratic-string-concat-fold: positives carry the FIRE
   marker; the rest are the spec's negatives plus an adversarial alias. *)

(* Partially applied folds over (^): saturations one and two. *)
let p1 = List.fold_left ( ^ ) (* FIRE *)
let p2 = List.fold_left ( ^ ) "" (* FIRE *)
let p3 = List.fold_right ( ^ ) (* FIRE *)
let p4 = Array.fold_left ( ^ ) "" (* FIRE *)
let p5 = Array.fold_right ( ^ ) (* FIRE *)
let p6 = Seq.fold_left ( ^ ) "" (* FIRE *)

(* A module alias is the same identity. *)
module L = List

let p7 = L.fold_left ( ^ ) "" (* FIRE *)

(* The spec's flagship positive: the saturated call as one
   three-argument application (the apply3 leg). *)
let segments = [ "a"; "b" ]
let p8 = List.fold_left ( ^ ) "" segments (* FIRE *)
let p9 = List.fold_right ( ^ ) segments "" (* FIRE *)

(* A rebound operator is a different identity. *)
let n1 =
  let ( ^ ) = Filename.concat in
  List.fold_left ( ^ ) ""

(* Eta-expansion hides the operator: the recorded v1 false negative. *)
let n2 = List.fold_left (fun acc s -> acc ^ s) ""

(* A different operator is a different question. *)
let n3 = List.fold_left ( + ) 0

(* Labeled folds refuse at the argument view. *)
let n4 = ListLabels.fold_left ~f:( ^ ) ~init:""

(* Buffer accumulation is already the linear idiom. *)
let n5 buf parts =
  List.fold_left
    (fun b (s : string) ->
      Buffer.add_string b s;
      b)
    buf parts

(* Adversarial: the fold reached through a let alias — identity, not
   dataflow. *)
let n6 =
  let fold = List.fold_left in
  fold ( ^ ) ""
