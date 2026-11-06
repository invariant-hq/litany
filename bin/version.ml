(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* git archive writes the tag here, by .gitattributes's export-subst: the
   version lives in the tag alone, and a release is that archive. A checkout
   holds the placeholder. *)
let tag = "$Format:%(describe:tags=true)$"
let current = if String.starts_with ~prefix:"$Format" tag then "dev" else tag
