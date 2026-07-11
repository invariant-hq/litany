(* Module-use index fixture: one use per carrier form the query's
   completeness contract enumerates (module_uses — the engine-kinds
   package). The suite asserts a recorded use inside each marked
   region, so every carrier line is load-bearing. *)

module M = struct
  type t = Leaf
  type r = { lab : int }
  type mut = { mutable mf : int }
  type c8 = C8 of int
  type vt = [ `V ]

  module type S = sig
    val v : int
  end

  module Inner : S = struct
    let v = 8
  end

  exception E

  class cl = object end

  let f x = x + 1
end

(* expression ident *)
let use_expr = M.f 1

open M

let use_open = f 2

module Included = struct
  include M
end

module A = M
module F2 (X : sig end) = struct end
module App = F2 (M)

let packed = (module M.Inner : M.S)

module Y : M.S = struct
  let v = 9
end

module type WITH_ALIAS = sig
  module A2 = M
end

let leaf : M.t = M.Leaf
let is_leaf x = match x with M.Leaf -> true
let c8v = M.C8 3
let un_c8 (M.C8 n) = n
let r0 = { M.lab = 4 }
let get_lab (r : M.r) = r.M.lab
let set_mf (x : M.mut) = x.mf <- 5
let { M.lab = l0 } = r0
let o = new M.cl

class sub = M.cl

class type ct2 = M.cl

let topen : M.(t) = Leaf
let pat_open x = match x with M.(Leaf) -> 0
let pat_type (x : M.vt) = match x with #M.vt -> 0
let unpack_arg (x : (module M.S)) = x
let ext = [%extension_constructor M.E]

exception E2 = M.E

(* expression-side extension constructor: the result-type head is the
   predef exn, so only the Cstr_extension tag path carries M *)
let raise_e () = raise M.E

(* pattern-side extension constructor *)
let catch f = try f () with M.E -> 0

(* never mentioned after its binding *)
module Quiet = struct
  let q = 0
end

(* same spelling, different idents: the unit signature refuses toplevel
   rebinding, so the second binding nests *)
module Shadow = struct
  let s1 = 1
end

let use_shadow_1 = Shadow.s1

module Nest = struct
  module Shadow = struct
    let s2 = 2
  end

  let use_shadow_2 = Shadow.s2
end
