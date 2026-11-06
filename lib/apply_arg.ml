(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The apply combinators probe every application node of every unit but run
   the callee pattern first, so the common failing path never reaches these:
   the list is built only after the callee matched. *)

let unlabeled_all args =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | (Asttypes.Nolabel, Typedtree.Arg (e : Typedtree.expression)) :: rest ->
        go (e :: acc) rest
    | _ -> None
  in
  go [] args

let unlabeled_opt_all args =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | (Asttypes.Nolabel, Typedtree.Arg (e : Typedtree.expression)) :: rest ->
        go (e :: acc) rest
    | (Asttypes.Optional _, _) :: rest -> go acc rest
    | ((Asttypes.Nolabel | Asttypes.Labelled _), _) :: _ -> None
  in
  go [] args
