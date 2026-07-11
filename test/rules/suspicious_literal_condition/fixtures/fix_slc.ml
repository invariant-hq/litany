(* Fixture for suspicious-literal-condition: positives carry the FIRE
   marker; every other line is a negative lookalike from the spec plus
   one adversarial extra. *)

let step () = ()
let f x = x + 1
let g x = x - 1

(* Literal conditions, all three spec positives. *)
let p1 = if true then 1 else 2 (* FIRE *)
let p2 () = if false then step () (* FIRE *)
let p3 = 3 |> if true then f else g (* FIRE *)

(* negative: a named constant is not a literal — no constant propagation *)
let debug = true
let n1 = if debug then 1 else 2

(* negative: while true is the idiomatic infinite loop *)
let n2 () =
  while true do
    step ()
  done

(* negative: a two-case match on a boolean is redundant-match-bool's *)
let n3 b = match b with true -> 1 | false -> 2

(* negative: a real runtime condition *)
let n4 = if Sys.unix then 1 else 2

(* negative (adversarial extra): an applied operator is not a literal,
   even one that folds to a constant — there is no evaluation *)
let n5 = if true && true then 1 else 2
