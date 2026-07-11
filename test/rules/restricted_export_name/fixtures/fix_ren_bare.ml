(* Fixture for restricted-export-name, the ml-only unit: without an
   mli the inferred signature is the export surface, so every root
   declaration is exported and the same policy condemns root names
   directly. Local names stay invisible to the export walk. *)

(* The exported prime type — exported by the derived signature. *)
type u' = string (* FIRE *)

(* negative: a well-named root type. *)
type ok_shape = { label : string }

(* The exported prime value. *)
let go' n = n - 1 (* FIRE *)

(* Over the (max-underscores 3) limit. *)
let total_count_of_all_things = 0 (* FIRE *)

(* negative: a well-named root value. *)
let fine_name = 2

(* negative: local bindings are not exports, whatever their spelling. *)
let scoped () =
  let inner' = 3 in
  let deep_local_name_with_many_parts = inner' + fine_name in
  deep_local_name_with_many_parts

(* negative: a nested module's members are submodule exports — outside
   the root surface, a recorded false negative. *)
module Inner = struct
  let nested' = go' 1
end
