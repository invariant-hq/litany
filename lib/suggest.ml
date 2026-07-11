(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* One-row dynamic programming: [row.(j)] holds the distance from [a]'s
   first [i] bytes to [b]'s first [j] bytes as [i] advances. *)
let levenshtein a b =
  let la = String.length a and lb = String.length b in
  let row = Array.init (lb + 1) Fun.id in
  for i = 1 to la do
    let diag = ref row.(0) in
    row.(0) <- i;
    for j = 1 to lb do
      let cost = if a.[i - 1] = b.[j - 1] then 0 else 1 in
      let v = min (min (row.(j) + 1) (row.(j - 1) + 1)) (!diag + cost) in
      diag := row.(j);
      row.(j) <- v
    done
  done;
  row.(lb)

let suggest ~candidates s =
  List.fold_left
    (fun best c ->
      let d = levenshtein s c in
      if d > 2 then best
      else
        match best with
        | Some (bd, bc) when (bd, bc) <= (d, c) -> best
        | _ -> Some (d, c))
    None candidates
  |> Option.map snd
