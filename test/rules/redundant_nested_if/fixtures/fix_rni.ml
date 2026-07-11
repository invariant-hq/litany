(* Fixture for redundant-nested-if: positives carry the FIRE marker;
   every other line is a negative lookalike from the spec plus one
   adversarial extra. *)

let launch () = ()
let draw _ _ = ()
let act () = ()

(* Both ifs else-less, immediately nested: finding and fix. *)
let p1 ok ready = if ok then if ready then launch () (* FIRE *)

(* Non-atomic conditions re-atomize: (a || b) && (c > 0). *)
let p2 a b c = if a || b then if c > 0 then act () (* FIRE *)

(* begin/end is transparent in the tree: the finding fires, the gap
   slice refuses the fix. *)
let p3 x y = if x > 0 then begin if y > 0 then draw x y end (* FIRE *)

(* Deeper nests fire once per level; the parenthesized (and commented)
   gaps refuse the fixes. *)
let p4 a b c =
  if a then (* FIRE *)
    (if b then (* FIRE *)
       (if c then act ()))

(* negative: inner else — collapse would change what runs when c1 is
   false vs c2 false *)
let n1 c1 c2 = if c1 then (if c2 then print_newline () else print_string "x")

(* negative: outer else — same reason *)
let n2 c1 c2 = if c1 then (if c2 then print_newline ()) else print_newline ()

(* negative: not immediate — a let intervenes *)
let n3 c1 c2 f g = if c1 then (let x = f () in if c2 then g x)

(* negative: literal outer condition — suspicious-literal-condition
   owns it (adversarial no-double-report) *)
let n4 c = if true then if c then print_newline ()

(* negative: literal inner condition — same owner *)
let n5 c = if c then if false then print_newline ()

(* negative: else-if chains are the idiom; the shape only ever looks
   into the then-branch *)
let n6 a b = if a then print_newline () else if b then print_string "y"

(* negative (adversarial extra): a sequence intervenes — the inner if
   is not the entire then-branch *)
let n7 a b = if a then (print_newline (); if b then print_newline ())
