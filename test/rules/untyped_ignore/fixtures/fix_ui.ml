(* Fixture for untyped-ignore: positives carry the FIRE marker. *)

let pop q = Queue.pop q

(* The argument names no type. *)
let untyped q = ignore (pop q) (* FIRE *)

(* Through an opened module, the identity is still Stdlib.ignore. *)
let opened q = Stdlib.(ignore (pop q)) (* FIRE *)

(* A value bound to ignore is not followed: a recorded false negative. *)
let aliased q =
  let drop = ignore in
  drop (pop q)

(* The type is named: what the rule asks for. *)
let typed (q : int Queue.t) = ignore (pop q : int)

(* Passed as a value, ignore is applied to nothing here. *)
let as_value q = List.iter ignore [ pop q ]

(* A shadowing ignore is another function. *)
let shadowed q =
  let ignore _ = () in
  ignore (pop q)
