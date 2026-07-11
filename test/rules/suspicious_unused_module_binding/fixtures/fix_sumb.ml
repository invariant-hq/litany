(* Fixture for suspicious-unused-module-binding: each FIRE marker sits
   on the name of a module binding the unit never uses — toplevel ones
   hidden by the interface, local ones with an M-free body; every other
   binding is a spec negative plus one adversarial extra. Warning 60,
   the compiler's own sound version of this judgment, is disabled in
   every mainstream default — including dune's dev profile building
   this fixture. *)

let f x = x + 1

(* Spec positive 1: an interface-hidden helper orphaned by a
   refactor. *)
module Cache (* FIRE *) = struct
  let default = 1
end

(* Spec positive 3: an unused alias hidden by the interface is dead
   text even at zero runtime cost. *)
module L (* FIRE *) = List

(* Spec positive 2: a local module the body never mentions. *)
let g () =
  let module Tbl (* FIRE *) = Hashtbl.Make (Int) in
  0

(* Negative: a used local module. *)
let h () =
  let module Two = struct
    let two = 2
  end in
  Two.two

(* Spec negative 1: interface-hidden but used in the unit — a use
   anywhere counts. *)
module Used = struct
  let id x = x
end

let use_it = Used.id 3

(* Spec negative 3: the anonymous effect-only spelling refuses by
   construction. *)
module _ = struct
  let () = ignore (f 1)
end

(* Spec negative 4, the adversarial shadow pair, realized at let-module
   level (structure items refuse duplicate module names outright): the
   second binding's include carries the first binding's ident, so the
   first is used, and the body's call keeps the second clean —
   identity-keying makes shadowing cost nothing. *)
let shadow_pair () =
  let module M = List in
  let module M = struct
    include M
  end in
  M.length []

(* Spec negative 5, the windtrap shape (run.ml:492): a local module
   mentioned only through its exception constructor — constructed in an
   expression, matched in a pattern — is used. The constructor's
   result-type head is the predef [exn]; the module home lives in the
   extension tag path, which the use index must also count. *)
let constructor_use (type a) (x : a) =
  let module Cell = struct
    exception Value of a
  end in
  match Cell.Value x with Cell.Value v -> v | _ -> x
