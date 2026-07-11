(* Spike A's probe, recreated as a fixture: a workspace unit without an mli,
   unwrapped. Each binding is one identity scenario the resolver must
   distinguish; test_ident harvests the use-site uids from this unit's cmt. *)

let direct xs = List.length xs

module L = List

let aliased xs = L.length xs

module Shadow = struct
  let length _ = 42
end

let shadowed xs = Shadow.length xs
let equal_op a b = a = b

module Int_map = Map.Make (Int)

let functor_use m = Int_map.find_opt 1 m

module Outer = struct
  module Inner = struct
    let v = 42
  end
end

module Base = struct
  let bv = 11
end

(* A local alias records [Mty_alias] of a non-persistent ident: the resolver
   must hop within this signature, never to a same-named foreign cmi. *)
module AliasB = Base

let use_aliasb = AliasB.bv

module Sigs = struct
  module type S = sig
    val sv : int
  end
end

(* A local [Pdot] prefix in [Mty_ident]: [Sigs] is a non-persistent head on
   the module-type path. *)
module Concrete : Sigs.S = struct
  let sv = 7
end

let use_sv = Concrete.sv

(* Type-namespace scenarios: a unit-level type, a nested-module type, and
   a result-typed value whose head names Stdlib.result. *)
type shade = Light | Dark

let tint = Light
let dim = Dark
let res_head : (int, string) result = Ok 0

module Tones = struct
  type tone = Warm | Cool

  let warm = Warm
  let cool = Cool
end
