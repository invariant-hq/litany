(* Fixture for manual-case-guard: positives carry the FIRE marker; every
   other line is a negative lookalike from the spec plus one adversarial
   extra. *)

type cmp = GT | LE

exception E

let again () = 1
let log x = ignore (List.length x)

(* Function-form cases whose body is immediately an if-then-else. *)
let p1 cond = function [] -> if cond then 1 else 2 (* FIRE *) | _ -> 3
let p2 = function [ x ] -> if x > 0 then 1 else 2 (* FIRE *) | _ -> 3

(* The match form — in scope. *)
let p3 v = match v with a, b -> if a > b then GT else LE (* FIRE *)

(* negative: the if is not immediate *)
let n1 x =
  match x with
  | y ->
      let z = y + 1 in
      if z > 0 then 1 else 2

(* negative: the case already guards — the author knows the feature *)
let n2 c x = match x with y when y > 0 -> if c then y else 0 | _ -> 1

(* negative: try handlers are excluded — a failing guard would fall
   through to re-raise *)
let n3 retry = try again () with E -> if retry then again () else raise E

(* negative: an else-less if has no arm for the implicit unit *)
let n4 c x = match x with [] -> if c then print_newline () | _ -> ()

(* negative: the if is a subexpression of the right-hand side, not the
   right-hand side itself *)
let n5 c rest = function [] -> (if c then 1 else 2) :: rest | x :: _ -> [ x ]

(* negative (adversarial extra): a sequence before the if is not an
   immediate if-then-else *)
let n6 c x =
  match x with
  | y ->
      log y;
      if c then 1 else 2
