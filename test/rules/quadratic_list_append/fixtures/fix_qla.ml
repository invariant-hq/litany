(* Fixture for quadratic-list-append: positives carry the FIRE marker;
   the rest are the spec's negatives — the fold_right operator form is
   the load-bearing linear pin — plus adversarial aliases. *)

let chunks = [ [ 1 ]; [ 2 ] ]
let xs = [ 1; 2 ]
let grid = [| [ 1 ]; [ 2 ] |]
let f x = [ x; x ]

(* Operator form under fold_left, saturations one to three. *)
let p1 : int list -> int list list -> int list = List.fold_left ( @ ) (* FIRE *)
let p2 : int list list -> int list = List.fold_left ( @ ) [] (* FIRE *)
let p3 = List.fold_left ( @ ) [] chunks (* FIRE *)
let p4 = List.fold_left List.append [] chunks (* FIRE *)
let p5 = Seq.fold_left ( @ ) [] (List.to_seq chunks) (* FIRE *)

(* The eta-expanded accumulator-on-the-left lambda. *)
let p6 = List.fold_left (fun acc x -> acc @ [ x ]) [] xs (* FIRE *)
let p7 = List.fold_left (fun acc x -> acc @ f x) [] xs (* FIRE *)
let p8 = Array.fold_left (fun acc row -> acc @ row) [] grid (* FIRE *)

(* fold_right with the accumulator on the left is a quadratic reversal. *)
let p9 = List.fold_right (fun x acc -> acc @ [ x ]) xs [] (* FIRE *)

(* fold_right over the operator is List.concat itself: linear. *)
let n1 = List.fold_right ( @ ) chunks []

(* Element on the left: each piece is copied once, linear. *)
let n2 = List.fold_left (fun acc x -> f x @ acc) [] xs

(* Consing accumulates linearly. *)
let n3 = List.fold_left (fun acc x -> x :: acc) [] xs

(* A shadowed (@) resolves elsewhere (adversarial). *)
let n4 =
  let ( @ ) = Filename.concat in
  List.fold_left ( @ ) ""

(* Labeled folds refuse at the argument view (documented false
   negative). *)
let n5 = ListLabels.fold_left ~f:( @ ) ~init:[] chunks

(* The fold reached through a let alias — identity, not dataflow
   (adversarial). *)
let n6 : int list list -> int list =
  let fold = List.fold_left in
  fold ( @ ) []

(* The recursive naive-reverse spelling is the spec's rec arm, held with
   the one-meta-two-kinds gate question. *)
let rec naive_rev = function [] -> [] | x :: tl -> naive_rev tl @ [ x ]
