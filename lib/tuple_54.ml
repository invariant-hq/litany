(* Tuple compat, 5.4/5.5 leg: the tuple payloads carry labeled components —
   [(string option * _) list] for [Texp_tuple] and [Tpat_tuple] (5.3 keeps
   plain lists; see tuple_53.ml). Selected by a copy rule in [dune] — the
   same version-selected-copy seam as apply_arg.

   Both views admit unlabeled tuples only: one [Some _] component label
   refuses the node, because a labeled tuple is a different shape from the
   [(a, b)] every rule speaks about. *)

(* [expr_components e] is the components of the unlabeled tuple expression
   [e], in source order, and [None] when [e] is not a tuple or any
   component is labeled. *)
let expr_components (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_tuple pes ->
      let rec go acc = function
        | [] -> Some (List.rev acc)
        | (None, (x : Typedtree.expression)) :: rest -> go (x :: acc) rest
        | (Some _, _) :: _ -> None
      in
      go [] pes
  | _ -> None

(* [pat_components p] is [expr_components] for tuple patterns. *)
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
