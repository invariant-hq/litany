(* Tuple compat, 5.3 leg: the tuple payloads are plain lists —
   [expression list] for [Texp_tuple], [value general_pattern list] for
   [Tpat_tuple] (5.4 added labeled components; see tuple_54.ml). Selected
   by a copy rule in [dune] — the same version-selected-copy seam as
   apply_arg.

   No component can be labeled on this leg, so every tuple is the
   unlabeled shape the views admit. *)

(* [expr_components e] is the components of the tuple expression [e], in
   source order, and [None] when [e] is not a tuple. *)
let expr_components (e : Typedtree.expression) =
  match e.exp_desc with Typedtree.Texp_tuple es -> Some es | _ -> None

(* [pat_components p] is [expr_components] for tuple patterns. *)
let pat_components (p : Typedtree.pattern) =
  match p.pat_desc with Typedtree.Tpat_tuple ps -> Some ps | _ -> None
