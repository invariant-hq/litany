(* Constructor-description compat, 5.3 leg: [constructor_description]
   lives in [Types] (5.4 moved it to [Data_types]; see cstr_54.ml).
   Selected by a copy rule in [dune] — the same version-selected-copy seam
   as apply_arg.

   The two accessors are exactly what constructor identity needs: the
   declared name and the head path of the result type. Rule code never
   sees the description's module home. *)

(* [name cd] is the constructor's declared name ([cstr_name]). *)
let name (cd : Types.constructor_description) = cd.Types.cstr_name

(* [res_head cd] is the head path of the constructor's result type when
   that type is a type constructor, and [None] otherwise. *)
let res_head (cd : Types.constructor_description) =
  match Types.get_desc cd.Types.cstr_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

(* Label descriptions share the constructor description's module-home churn
   ([Types] in 5.3, [Data_types] from 5.4); the three accessors below are
   the label half of the seam, added with the record views. Rule code
   never sees the description's module home. *)

(* The type for label descriptions, re-exported so [litany_pat] can
   name it without naming the module home. *)
type lbl = Types.label_description

(* [lbl_name l] is the label's declared name ([lbl_name]). *)
let lbl_name (l : Types.label_description) = l.Types.lbl_name

(* [lbl_res_head l] is the head path of the label's record type when that
   type is a type constructor, and [None] otherwise. *)
let lbl_res_head (l : Types.label_description) =
  match Types.get_desc l.Types.lbl_res with
  | Types.Tconstr (p, _, _) -> Some p
  | _ -> None

(* [lbl_mutable l] is [true] iff the label is [mutable]. *)
let lbl_mutable (l : Types.label_description) =
  match l.Types.lbl_mut with
  | Asttypes.Mutable -> true
  | Asttypes.Immutable -> false
