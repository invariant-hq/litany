(* Fixture for needless-fun-match: positives carry the FIRE marker; every
   other line is a negative lookalike from the spec plus one adversarial
   extra. *)

let seps = [ "," ]
let g () = [ 1 ]

exception E

(* The plain form, through the `let f x = …` sugar. *)
let p1 x = match x with [] -> 1 | _ -> 2 (* FIRE *)

(* A single case rebinding the name: the outer ident is unused. *)
let p2 =
 fun c -> match c with xs -> List.exists (fun c -> c = 'a') xs (* FIRE *)

(* Every case shadows the parameter; the outer binding is unused. *)
let p3 =
 fun ch (* FIRE *) ->
  match ch with ch when List.mem ch seps -> ch | "\n" -> "" | ch -> "" ^ ch

(* Multi-parameter: the match is on the last. *)
let p4 a x = match x with [] -> a | _ :: _ -> a + 1 (* FIRE *)

(* negative: the parameter is used in a case body *)
let n1 x = match x with [] -> [] | _ :: _ -> x

(* negative: the scrutinee is not the bare parameter *)
let compute x = List.rev x
let n2 x = match compute x with [] -> 1 | _ -> 2

(* negative: a different ident under the same name — the inner binding
   shadows the parameter, so the parameter is not the scrutinee *)
let n3 x =
  let x = x @ g () in
  match x with [] -> 1 | _ -> 2

(* negative: a labeled parameter — the rewrite would change call sites *)
let n4 ~lbl = match lbl with [] -> 0 | _ -> 1

(* negative: the match is not the whole body *)
let n5 x = (match x with [] -> 1 | _ -> 2) + 1

(* negative: an exception case — function cannot carry it *)
let n6 x = match x with [] -> 1 | _ -> 2 | exception E -> 3

(* negative (adversarial extra): the parameter is used in a guard *)
let n7 x = match x with n when x <> [] -> List.length n | _ -> 0

(* negative: the scrutinee carries a type constraint — the annotation is
   load-bearing and function has nowhere to put it *)
let n8 x = match (x : int list) with [] -> 1 | _ -> 2

(* the same shape without the constraint still fires *)
let p5 x = match x with [] -> 1 | _ -> 2 (* FIRE *)
