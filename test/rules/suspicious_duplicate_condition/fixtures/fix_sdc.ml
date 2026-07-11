(* Fixture for suspicious-duplicate-condition: positives carry the FIRE
   marker on the duplicated (second) condition's line; every other case
   is a spec negative plus one adversarial extra. *)

let a = 1
let b = 2
let c = 3

type state = Idle | Busy

let states = [ Idle; Busy ]
let f () = true
let r = ref true
let probe l r = l < r

(* The unedited else-if paste. *)
let p1 x = if x = 1 then a else if x = 1 then b (* FIRE *) else c

(* Operator-composed pure condition. *)
let p2 p q = if p && q then a else if p && q then b (* FIRE *) else c

(* Constructor comparison. *)
let p3 (s : state) =
  if s = Idle then a else if s = Idle then b (* FIRE *) else c

(* A triple chain fires per adjacent pair, from two nodes, without
   dedup machinery. *)
let p4 x =
  if x = 1 then a
  else if x = 1 then b (* FIRE *)
  else if x = 1 then c (* FIRE *)
  else 0

(* A comment outside the condition spans does not block: the slices are
   the conditions alone (pinned both ways with n5). *)
let p5 x = if x = 1 (* first *) then a else if x = 1 then b (* FIRE *) else c

(* negative: an effectful call repeated is not a repeated condition. *)
let n1 () = if f () then a else if f () then b else c

(* negative: a mutable read — another domain may write in between. *)
let n2 () = if !r then a else if !r then b else c

(* negative: different bytes. *)
let n3 x = if x = 1 then a else if x = 2 then b else c

(* negative (adversarial): a local (=) is effectful; the UID refuses,
   so the comparison never yields a false dead-arm claim. *)
let n4 x =
  let ( = ) l r = probe l r in
  if x = 1 then a else if x = 1 then b else c

(* negative: a comment inside the condition span differs the slices. *)
let n5 x =
  if
    x
    =
    (* one *)
    1
  then a
  else if x = 1 then b
  else c

(* negative: literal conditions are suspicious-literal-condition's. *)
let n6 y = if true then a else if true then b else y

(* negative (adversarial extra): an array read reaches mutable state
   through an unlisted callee. *)
let n7 (t : int array) = if t.(0) = 1 then a else if t.(0) = 1 then b else c
