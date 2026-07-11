(* Alias-pattern compat, 5.4/5.5 leg: [Tpat_alias] carries the aliased
   pattern's type as a fifth argument (added in 5.4). Selected by a copy
   rule in [dune]; 5.3 has four arguments (see pat_alias_53.ml). *)

(* [bound_alias p] is the alias name and declaration uid when [p] is
   [p' as x], and [None] otherwise. *)
let bound_alias (p : Typedtree.pattern) =
  match p.pat_desc with
  | Typedtree.Tpat_alias (_, _, name, uid, _) -> Some (name, uid)
  | _ -> None
