(* Expression-item compat, 5.5 leg: [let module M = … in …] elaborates to
   [Texp_struct_item] carrying a [Tstr_module] item (5.5 removed
   [Texp_letmodule]; 5.3/5.4 keep the positional five-field payload, see
   expr_item_54.ml), and the same node admits expression-local [type]
   groups ([type t = … in e], a [Tstr_type] item in expression position).
   Selected by a copy rule in [dune] — the same version-selected-copy
   seam as lib/pat's apply_arg.

   Two accessors are the whole seam: the engine dispatches the
   [Rule.module_binding] kind's expression-level half and the
   [type_decl] kind's expression-local position through them, so the node
   churn never reaches litany_engine.ml. The embedded item is a bare
   [structure_item] — a member of no [structure] — so the engine's
   structure-hook dispatch (which reads [str_items]) never sees it as a
   structure-level binding: no double dispatch, and [Tstr_recmodule] in
   expression position stays excluded exactly as at structure level. *)

(* [local_module e] is the bound ident and binder-name location when [e]
   is a let-module expression, and [None] otherwise. The whole binding's
   location is [e.exp_loc], read by the caller. *)
let local_module (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_struct_item ({ str_desc = Typedtree.Tstr_module mb; _ }, _)
    ->
      Some (mb.Typedtree.mb_id, mb.Typedtree.mb_name.Location.loc)
  | _ -> None

(* [type_group e] is the expression-local type-declaration group of [e]
   when [e] is [type … in e'] — dispatched as an ordinary [type_decl]
   group ([loc] is the embedded item's, starting at the [type] keyword) —
   and [None] otherwise. *)
let type_group (e : Typedtree.expression) :
    (Location.t * Asttypes.rec_flag * Typedtree.type_declaration list) option =
  match e.exp_desc with
  | Typedtree.Texp_struct_item
      ({ str_desc = Typedtree.Tstr_type (rf, ds); str_loc; _ }, _) ->
      Some (str_loc, rf, ds)
  | _ -> None
