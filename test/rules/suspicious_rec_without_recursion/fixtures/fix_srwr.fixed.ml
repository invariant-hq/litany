(* Fixture for suspicious-rec-without-recursion: each FIRE marker sits
   on the first pattern of a [let rec] group — structure-level or
   expression-level — none of
   whose bindings references the group; every other binding is a
   negative from the spec plus one adversarial extra. Warning 39 is
   disabled for this library on purpose (see the fixture dune): the
   fixture's whole subject is the code that warning rejects under
   dune's dev profile. *)

let lex _s = 1
let input = "x"

(* Calls a helper, never itself; the use in the body does not
   suppress. *)
let parsed =
  let parse (* FIRE *) s = lex s in
  parse input

(* A whole group of inert bindings, both used after the group. *)
let both =
  let a (* FIRE *) x = x + 1 and b y = y * 2 in
  a 1 + b 2

(* A comment in the keyword gap: the finding fires, the fix refuses. *)
let kept =
  let rec (* keep *) g (* FIRE *) x = x + 2 in
  g 1

(* An inner same-spelled rebinding is a different identity: this group
   never references itself. *)
let shadow_fire =
  let h (* FIRE *) x =
    let h y = y + x in
    h 7
  in
  h 5

(* Self-recursion. *)
let fact n0 =
  let rec go n = if n = 0 then 1 else n * go (n - 1) in
  go n0

(* Mutual recursion. *)
let parity n0 =
  let rec even n = if n = 0 then true else odd (n - 1)
  and odd n = if n = 0 then false else even (n - 1) in
  even n0

(* One-directional cross-use is still a group reference: partial groups
   are not this rule's finding, splitting them is a different remedy. *)
let crossed =
  let rec f x = x and g y = f y in
  g (f 1)

(* Adversarial: the body's f is the rec binding itself, not the outer
   f — identity, not spelling; dropping rec here would retarget it. *)
let f x = x + 1

let retarget () =
  let rec f y = f y in
  f 3

(* Adversarial extra: the self-call hides inside a nested function — a
   group reference at any nesting depth still blocks. *)
let countdown n0 =
  let rec loop n =
    let step () = loop (n - 1) in
    if n = 0 then 0 else step ()
  in
  loop n0

(* A recursive value is a self-use. *)
let ones_head =
  let rec ones = 1 :: ones in
  List.hd ones

(* Structure-level groups dispatch too since the let_group widening:
   the C2-1 spec positive, flipped from a recorded false negative. *)
let toplevel_inert (* FIRE *) x = lex x

(* C2-2: a whole structure-level group of inert bindings. *)
let sa (* FIRE *) = 1
and sb = 2
