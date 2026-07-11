(* Dependency-kind compat, 5.3/5.4 leg: the kind type lives in
   [Cmt_format.dependency_kind]. Selected by a copy rule in [dune]; 5.5 moved
   the type to [Shape.Uid.Deps.kind] (see dep_kind_55.ml). *)

type kind = Cmt_format.dependency_kind

let is_definition_to_declaration = function
  | Cmt_format.Definition_to_declaration -> true
  | Cmt_format.Declaration_to_declaration -> false
