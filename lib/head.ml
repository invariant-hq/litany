(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

let cstr (cd : Data_types.constructor_description) =
  match Types.get_desc cd.Data_types.cstr_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

let cstr_ext (cd : Data_types.constructor_description) =
  match cd.Data_types.cstr_tag with
  | Data_types.Cstr_extension (p, _) -> Some p
  | _ -> None

let lbl (ld : Data_types.label_description) =
  match Types.get_desc ld.Data_types.lbl_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

let package (pt : Typedtree.package_type) =
  (pt.Typedtree.tpt_path, pt.Typedtree.tpt_txt)
