(* Whitespace-only differences between the branches: normalization
   equates the slices. Layout is load-bearing here, so this file is
   listed in .ocamlformat-ignore. *)

let choose c x = if c then max x   1 else max x 1 (* FIRE *)

let spread c x =
  if c then (* FIRE *) min (x + 1)
    (x + 2)
  else min (x + 1) (x + 2)
