(* Apply-argument compat, 5.4/5.5 leg: [Texp_apply] arguments are
   [(arg_label * apply_arg) list] with [apply_arg = Arg of expression |
   Omitted of unit]. Selected by a copy rule in [dune]; 5.3 keeps
   [(arg_label * expression option) list] (see apply_arg_53.ml).

   List views: the apply combinators probe every application node of every
   unit but run the callee pattern first, so the common failing path — an
   application whose callee is not the sought identity — never reaches
   these; the list is built only after the callee matched, and allocation
   is proportional to the prefix scanned, so an early labeled argument
   costs almost nothing. *)

(* [unlabeled_all args] is every argument, in source order, when each is
   unlabeled and evaluated, and [None] otherwise. The list is non-empty:
   [Texp_apply] carries at least one argument. *)
let unlabeled_all args =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | (Asttypes.Nolabel, Typedtree.Arg (e : Typedtree.expression)) :: rest ->
        go (e :: acc) rest
    | _ -> None
  in
  go [] args

(* [unlabeled_opt_all args] is every unlabeled, evaluated argument, in
   source order, in any interleaving with optional arguments — omitted or
   evaluated, all skipped. A labeled argument, or an omitted unlabeled
   argument, refuses. *)
let unlabeled_opt_all args =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | (Asttypes.Nolabel, Typedtree.Arg (e : Typedtree.expression)) :: rest ->
        go (e :: acc) rest
    | (Asttypes.Optional _, _) :: rest -> go acc rest
    | ((Asttypes.Nolabel | Asttypes.Labelled _), _) :: _ -> None
  in
  go [] args
