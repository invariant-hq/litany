(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-physical-equality" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"physical comparison with a non-immediate operand"
    ~doc:
      {|`==` and `!=` compare identity, not contents: on boxed values two
structurally equal operands may or may not share one allocation, so the
answer depends on the program's allocation history.

    (* bad *)  "a" ^ "b" == "ab"
    (* good *) "a" ^ "b" = "ab"

Fires only when the operator resolves to `Stdlib.(==)` or `Stdlib.(!=)`
and at least one operand's type is proved non-immediate: a function, a
tuple, or a predefined boxed type (`string`, `bytes`, `float`, `array`,
and kin). Operands whose immediacy is unknown — type variables,
abbreviations, user-defined types — deliberately do not fire, and neither
do shadowed operators or partial applications. Physical identity can be
intentional, so there is no automatic fix.|}
    ()

let physical =
  Pat.(apply (ident "Stdlib.(==)" ||| ident "Stdlib.(!=)") (__ ^:: __ ^:: nil))

(* Predefined types with a proven boxed representation. Everything else —
   abbreviations included, which are deliberately not expanded — reads
   unknown and stays clean, deliberate conservatism. [iarray]
   and [atomic_loc] are absent from the support window's older minors and
   are not listed. *)
let boxed_paths =
  Predef.
    [
      path_string;
      path_bytes;
      path_float;
      path_floatarray;
      path_array;
      path_nativeint;
      path_int32;
      path_int64;
    ]

let non_immediate (e : Typedtree.expression) =
  match Types.get_desc e.exp_type with
  | Types.Tarrow _ | Types.Ttuple _ -> true
  | Types.Tconstr (p, _, _) -> List.exists (Path.same p) boxed_paths
  | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  match
    Pat.run physical u e (fun l r -> non_immediate l || non_immediate r)
  with
  | Some true ->
      [
        Finding.v ~loc:e.exp_loc
          "physical comparison has a non-immediate operand";
      ]
  | Some false | None -> []
