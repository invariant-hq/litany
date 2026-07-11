(* Constructor-description compat, 5.4/5.5 leg: [constructor_description]
   lives in [Data_types] (5.3 keeps it in [Types]; see cstr_53.ml).
   Selected by a copy rule in [dune] — the same version-selected-copy seam
   as apply_arg.

   The two accessors are exactly what constructor identity needs: the
   declared name and the head path of the result type. Rule code never
   sees the description's module home. *)

(* [name cd] is the constructor's declared name ([cstr_name]). *)
let name (cd : Data_types.constructor_description) = cd.Data_types.cstr_name

(* [res_head cd] is the head path of the constructor's result type when
   that type is a type constructor, and [None] otherwise. *)
let res_head (cd : Data_types.constructor_description) =
  match Types.get_desc cd.Data_types.cstr_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

(* Label descriptions share the constructor description's module-home churn
   ([Types] in 5.3, [Data_types] from 5.4); the three accessors below are
   the label half of the seam, added with the record views. Rule code
   never sees the description's module home. *)

(* The type for label descriptions, re-exported so [litany_pat] can
   name it without naming the module home. *)
type lbl = Data_types.label_description

(* [lbl_name l] is the label's declared name ([lbl_name]). *)
let lbl_name (l : Data_types.label_description) = l.Data_types.lbl_name

(* [lbl_res_head l] is the head path of the label's record type when that
   type is a type constructor, and [None] otherwise. *)
let lbl_res_head (l : Data_types.label_description) =
  match Types.get_desc l.Data_types.lbl_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

(* [lbl_mutable l] is [true] iff the label is [mutable]. *)
let lbl_mutable (l : Data_types.label_description) =
  match l.Data_types.lbl_mut with
  | Asttypes.Mutable -> true
  | Asttypes.Immutable -> false
