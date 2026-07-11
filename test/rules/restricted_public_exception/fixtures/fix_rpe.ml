(* Fixture for restricted-public-exception, the mli-backed unit: the mli
   is the export surface, so each marked line is the implementation
   anchor of an exception the interface declares. The suite runs this
   unit as a public library — and re-runs the same artifact as an
   executable, a test, a private library, and a kindless unit, all
   silent. *)

(* The exported exception. *)
exception Boom of string (* FIRE *)

(* negative: an exception the mli hides — unexported. *)
exception Hidden

(* The exported rebind: a root [exception] declaration like any other. *)
exception Rebound = Stdlib.Not_found (* FIRE *)

(* negative: a local exception never reaches the export surface. *)
let trigger () =
  let exception Local in
  if Sys.word_size = 0 then raise Local;
  raise Hidden

(* negative: a non-exception extension constructor contributes no row. *)
type ext = ..
type ext += Case

(* negative: a submodule exception is a dotted row — outside the root
   surface, a recorded false negative. *)
module Sub = struct
  exception Nested
end
