(* Engine-kinds fixture: type groups, let groups, and module bindings at
   every dispatch position — root, nested structure, and expression level.
   The suite fishes positions out with [where], so layout is free. *)

type single = { field : int }
type nonrec alias = int

type t1 = A of t2
and t2 = B of int

let uses_single r = r.field
let of_alias (a : alias) = a
let build = A (B 1)
let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

let pair_a = 2
and pair_b = 3

exception Kaboom

module M = struct
  type nested = C of single

  exception Inner_boom

  let inner = 4

  module Deep = struct end
end

module _ = struct end

let local_groups () =
  let x = 5 in
  let rec loop n = if n = 0 then x else loop (n - 1) in
  let module L = List in
  (loop 1, L.length [])
