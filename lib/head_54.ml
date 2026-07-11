(* Description-head compat, 5.4/5.5 leg: [constructor_description] and
   [label_description] live in [Data_types] (5.3 keeps both in [Types]; see
   head_53.ml). Selected by a copy rule in [dune] — the same
   version-selected-copy seam as dep_kind, at the 5.4 boundary.

   The two accessors are what the module-use index needs from a
   description: the head path of its result type — the one path a
   qualified [M.C] or [M.field] use site stores. *)

(* [cstr cd] is the head path of the constructor's result type when that
   type is a type constructor, and [None] otherwise. *)
let cstr (cd : Data_types.constructor_description) =
  match Types.get_desc cd.Data_types.cstr_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

(* [cstr_ext cd] is the extension constructor's own path when the
   description is an extension ([Cstr_extension] carries it), and [None]
   for ordinary constructors. An extension use site's result-type head is
   the extended type (for exceptions, the predef [exn]) — the module the
   constructor is spelled through lives only in this tag path. *)
let cstr_ext (cd : Data_types.constructor_description) =
  match cd.Data_types.cstr_tag with
  | Data_types.Cstr_extension (p, _) -> Some p
  | _ -> None

(* [lbl ld] is [cstr] for label descriptions: the head path of the label's
   record type. *)
let lbl (ld : Data_types.label_description) =
  match Types.get_desc ld.Data_types.lbl_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

(* [package pt] is the package type's path and its spelled name — the
   [(module M.S)] carrier. The field names churn at 5.4 ([pack_path]/
   [pack_txt] in 5.3; [tpt_path]/[tpt_txt] here), which is why the read
   lives in this seam. *)
let package (pt : Typedtree.package_type) =
  (pt.Typedtree.tpt_path, pt.Typedtree.tpt_txt)
