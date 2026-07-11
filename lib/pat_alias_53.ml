(* Alias-pattern compat, 5.3 leg: [Tpat_alias] carries four arguments.
   Selected by a copy rule in [dune]; 5.4 added the aliased pattern's type
   as a fifth (see pat_alias_54.ml). *)

(* [bound_alias p] is the alias name and declaration uid when [p] is
   [p' as x], and [None] otherwise. *)
let bound_alias (p : Typedtree.pattern) =
  match p.pat_desc with
  | Typedtree.Tpat_alias (_, _, name, uid) -> Some (name, uid)
  | _ -> None
