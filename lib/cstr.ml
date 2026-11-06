(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

let name (cd : Data_types.constructor_description) = cd.Data_types.cstr_name

let res_head (cd : Data_types.constructor_description) =
  match Types.get_desc cd.Data_types.cstr_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

type lbl = Data_types.label_description

let lbl_name (l : lbl) = l.Data_types.lbl_name

let lbl_res_head (l : lbl) =
  match Types.get_desc l.Data_types.lbl_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

let lbl_mutable (l : lbl) =
  match l.Data_types.lbl_mut with
  | Asttypes.Mutable -> true
  | Asttypes.Immutable -> false
