(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

let bound_alias (p : Typedtree.pattern) =
  match p.pat_desc with
  | Typedtree.Tpat_alias (_, _, name, uid, _) -> Some (name, uid)
  | _ -> None
