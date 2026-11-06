(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

let is_definition_to_declaration = function
  | Shape.Uid.Deps.Definition_to_declaration -> true
  | Shape.Uid.Deps.Declaration_to_declaration -> false
