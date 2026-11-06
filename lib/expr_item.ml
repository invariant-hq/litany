(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

let local_module (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_struct_item ({ str_desc = Typedtree.Tstr_module mb; _ }, _)
    ->
      Some (mb.Typedtree.mb_id, mb.Typedtree.mb_name.Location.loc)
  | _ -> None

let type_group (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_struct_item
      ({ str_desc = Typedtree.Tstr_type (rf, ds); str_loc; _ }, _) ->
      Some (str_loc, rf, ds)
  | _ -> None
