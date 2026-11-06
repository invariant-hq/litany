(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

let pat_components (p : Typedtree.pattern) =
  match p.pat_desc with
  | Typedtree.Tpat_tuple pps ->
      let rec go acc = function
        | [] -> Some (List.rev acc)
        | (None, (x : Typedtree.pattern)) :: rest -> go (x :: acc) rest
        | (Some _, _) :: _ -> None
      in
      go [] pps
  | _ -> None
