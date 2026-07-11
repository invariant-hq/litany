(* Fixture for manual-tuple-matching: each FIRE marker sits on a match
   with one irrefutable tuple case; every other match is a negative
   from the spec plus the constraint adversarial. Warning 8 is disabled
   for this library on purpose (see the fixture dune): the refutable
   negatives are partial matches by design. *)

exception Boom

let scru = (1, 2)
let get () = (3, 4)
let pair_or_raise () = if fst scru = 0 then raise Boom else (5, 6)

(* Wildcards are irrefutable — in scope. *)
let a = match scru with _, _ -> true (* FIRE *)

(* Effectful scrutinee: evaluation is identical in both forms. *)
let b = match get () with x, y -> x + y (* FIRE *)

(* Nested irrefutable tuple. *)
let c = match (5, (6, 7)) with u, (v, w) -> u + v + w (* FIRE *)

(* A comment in the keyword gap: the finding fires, the fix refuses. *)
let d = match (* why *) scru with x, y -> x * y (* FIRE *)

(* Two cases branch. *)
let n1 = match scru with 0, 1 -> true | _, _ -> false

(* Refutable component: warning 8 owns the partiality. *)
let n2 = match scru with 0, x -> x

(* Guard present. *)
let n3 = match scru with x, y when x > y -> x

(* Exception arm: two computation cases, one not a value pattern. *)
let n4 = match pair_or_raise () with a, b -> a + b | exception Boom -> 0

(* function spelling is needless-fun-match's territory. *)
let n5 = function a, b -> a + b

(* Adversarial: a constraint component refuses conservatively. *)
let n6 = match scru with (x : int), y -> x + y

(* Alias of an irrefutable component: a recorded false negative until
   the vocabulary can see through an alias's sub-pattern. *)
let n7 = match scru with (x, _) as whole -> fst whole + x

let sum =
  ignore (a, d, n1, n5 scru, n6, n7);
  b + c + n2 + n3 + n4
