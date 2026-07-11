(* Dependency-kind compat, 5.5 leg: the kind type lives in
   [Shape.Uid.Deps.kind]. Selected by a copy rule in [dune]; 5.3/5.4 keep it
   in [Cmt_format.dependency_kind] (see dep_kind_54.ml). *)

type kind = Shape.Uid.Deps.kind

let is_definition_to_declaration = function
  | Shape.Uid.Deps.Definition_to_declaration -> true
  | Shape.Uid.Deps.Declaration_to_declaration -> false
