(* Expression-item compat, 5.3/5.4 leg: [let module M = … in …] is
   [Texp_letmodule] with a positional five-field payload, and no other
   structure item can occur in expression position. 5.5 removed the node
   (with [Texp_open] and [Texp_letexception]) in favor of
   [Texp_struct_item of structure_item * expression], which also admits
   expression-local [type] groups (see expr_item_55.ml). Selected by a
   copy rule in [dune] — the same version-selected-copy seam as lib/pat's
   apply_arg.

   Two accessors are the whole seam: the engine dispatches the
   [Rule.module_binding] kind's expression-level half and the
   [type_decl] kind's expression-local position through them, so the node
   churn never reaches litany_engine.ml. *)

(* [local_module e] is the bound ident and binder-name location when [e]
   is a let-module expression, and [None] otherwise. The whole binding's
   location is [e.exp_loc], read by the caller. *)
let local_module (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_letmodule (id, name, _, _, _) -> Some (id, name.Location.loc)
  | _ -> None

(* [type_group e] is the expression-local type-declaration group of [e] —
   never on this leg: the syntax arrives at 5.5. *)
let type_group (_ : Typedtree.expression) :
    (Location.t * Asttypes.rec_flag * Typedtree.type_declaration list) option =
  None
