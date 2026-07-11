(* Fixture for restricted-global-mutable-state: each marked line binds a
   root-structure variable whose type head is structurally mutable — a
   ref, a Hashtbl.t, or a root-declared record with a mutable field.
   The other lines are the spec's negatives plus adversarial extras.
   The kind gate is roster metadata, so the suite runs this one
   artifact under Library (fires), Executable, Test, and no kind (all
   silent). *)

(* Toplevel refs: the bare and the qualified spelling of one head. *)
let counter = ref 0 (* FIRE *)
let gate = Stdlib.ref false (* FIRE *)

(* A toplevel table. *)
let registry : (string, int) Hashtbl.t = Hashtbl.create 16 (* FIRE *)

(* The known-FP shape fires too: a memo table is deliberate state, and
   [@litany.allow "restricted-global-mutable-state: …"] with a reason
   is the designed outlet — the rule never guesses intent. *)
let memo : (int, int) Hashtbl.t = Hashtbl.create 64 (* FIRE *)

(* A mutable-record global: the head is declared at this unit's root. *)
type state = { mutable hits : int; label : string }

let stats = { hits = 0; label = "totals" } (* FIRE *)

(* Alias transparency: the alias's [t] is still Stdlib's Hashtbl.t. *)
module H = Hashtbl

let aliased : (string, int) H.t = H.create 16 (* FIRE *)

(* negative: a pure record is a value, not state. *)
type point = { x : int; y : int }

let origin = { x = 0; y = 0 }

(* negative: a ref local to a function lives in its frame. *)
let tick () =
  let c = ref 0 in
  incr c;
  !c

(* negative: a lazy cache is the blessed initialize-once spelling. *)
let table : (string, int) Hashtbl.t lazy_t = lazy (Hashtbl.create 16)

(* negative: a function returning fresh state constructs, not holds. *)
let make_counter () = ref 0

(* negative (out of scope v1): the array type does not distinguish a
   buffer from state. *)
let buffer = Array.make 4 0.

(* negative (recorded FN, pinned): abbreviation heads are never
   expanded. *)
type counter = int ref

let hidden : counter = ref 0

(* negative (recorded FN, pinned): a destructuring binding binds no
   single variable; its components escape the head test. *)
let one, two = (ref 0, ref 1)

(* negative: a binding that binds no name is dropped, not state. *)
let _ = ref 0

(* negative (recorded FN, pinned): a mutable-record head from a nested
   module is reached through a module path, not a root declaration. *)
module Nested = struct
  type cell = { mutable value : int }
end

let nested_cell : Nested.cell = { Nested.value = 0 }

(* negative (adversarial): a same-spelled local Hashtbl resolves to its
   own immutable [t], never to Stdlib's. *)
module Hashtbl = struct
  type ('a, 'b) t = Empty

  let create (_ : int) : ('a, 'b) t = Empty
end

let shadowed : (string, int) Hashtbl.t = Hashtbl.create 16

(* A root [include struct ... end] lands its items on the unit's root
   surface: the binding and the mutable-record head both
   join as root items. *)
include struct
  let hidden_cache : int list ref = ref [] (* FIRE *)

  type icell = { mutable v : int }

  let included_cell = { v = 0 } (* FIRE *)
end

(* negative (recorded FN, pinned): [include] of a named module
   namespaces the binding away from the root join — the item lives in
   the named module's structure, not the unit's root. *)
module Named_state = struct
  let named_ref = ref 0
end

include Named_state
