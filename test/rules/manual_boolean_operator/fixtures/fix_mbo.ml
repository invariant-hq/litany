(* Fixture for manual-boolean-operator: positives carry the FIRE marker;
   every other line is a negative lookalike from the spec plus one
   adversarial extra. Every fix cell is Unsafe, so the .fixed golden's
   bytes equal this file's — --fix without --unsafe changes nothing. *)

let retry () = true
let compute () = false

(* All four rewrite cells. *)
let p1 found = if found then true else retry () (* FIRE *)
let p2 valid = if valid then compute () else false (* FIRE *)
let p3 c t = if c then t else true (* FIRE *)
let p4 c t = if c then false else t (* FIRE *)

(* Argument position: the parenthesized if's location includes the
   parentheses, and the operator replacement is not self-delimiting —
   the fix restores the pair (pinned by the unsafe golden). *)
let p5 found = string_of_bool (if found then true else retry ()) (* FIRE *)

(* Trailing-open operand: the if is the unparenthesized right operand of
   an infix operator. The bare rewrite would re-associate — `a && c || e`
   is `(a && c) || e` — so the fix adds the pair; the truth table below
   pins the semantics, and the fixture's runtest leg executes it on both
   this file and the unsafe golden. *)
let p6 a c e = a && if c then true else e (* FIRE *)
let p7 a c e = a || if c then false else e (* FIRE *)

(* A let body is not an operand: the bare rewrite, no pair added. *)
let p8 c e =
  let b (* FIRE *) = if c then true else e in
  b

(* Already parenthesized under &&: the author's pair is restored once,
   never doubled (ocamlformat would strip the pair, hence the opt-out). *)
let p9 a c e = a && (if c then true else e) (* FIRE *)
[@@ocamlformat "disable"]

let () =
  List.iter
    (fun a ->
      List.iter
        (fun c ->
          List.iter
            (fun e ->
              assert (p6 a c e = (a && (c || e)));
              assert (p7 a c e = (a || ((not c) && e)));
              assert (p8 c e = (c || e));
              assert (p9 a c e = (a && (c || e))))
            [ true; false ])
        [ true; false ])
    [ true; false ]

(* negative: two-literal branches are redundant-if-bool's *)
let n1 c = if c then true else false

(* negative: a literal condition is suspicious-literal-condition's *)
let n2 = if true then true else retry ()

(* negative: equal literals in both branches — degenerate *)
let n3 c = if c then true else true

(* negative: no literal branch *)
let n4 c f g = if c then f () else g ()

(* negative: integer literals are not booleans *)
let n5 c = if c then 1 else 0

(* negative: user constructors, not the predefined booleans *)
type t = True | False

let n6 c = if c then True else False

(* negative (adversarial extra): polymorphic-variant lookalikes *)
let n7 c = if c then `True else `False

(* A fix-site scope that shadows a spliced operator:
   the operator rewrites are Unsafe, so --fix leaves the line alone. *)
let cor02 c t =
  let ( || ) a _ = a in
  if c then true (* FIRE *) else t || false
