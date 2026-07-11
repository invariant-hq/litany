(* Fixture for invalid-hashtable-key: positives carry the FIRE marker; the
   rest are the spec's negatives plus adversarial lookalikes. *)

let f x = x + 1
let tbl : (int -> int, string) Hashtbl.t = Hashtbl.create 7

(* Functional subjects at the covered arities. *)
let p1 = Hashtbl.mem tbl f (* FIRE *)
let p2 = Hashtbl.find tbl f (* FIRE *)
let p3 = Hashtbl.find_opt tbl f (* FIRE *)
let p4 = Hashtbl.find_all tbl f (* FIRE *)
let p5 = Hashtbl.remove tbl f (* FIRE *)
let p6 = Hashtbl.hash f (* FIRE *)
let p7 = Hashtbl.seeded_hash 42 f (* FIRE *)

(* Containers of functions prove a function through list/array/option. *)
let tbl_list : ((int -> int) list, string) Hashtbl.t = Hashtbl.create 7
let p8 = Hashtbl.mem tbl_list [ f ] (* FIRE *)
let tbl_opt : ((int -> int) option, string) Hashtbl.t = Hashtbl.create 7
let p9 = Hashtbl.mem tbl_opt (Some f) (* FIRE *)
let tbl_arr : ((int -> int) array, string) Hashtbl.t = Hashtbl.create 7
let p10 = Hashtbl.mem tbl_arr [| f |] (* FIRE *)

(* A shadowed Hashtbl is a different identity. *)
let n1 =
  let module Hashtbl = struct
    let mem _ _ = false
  end in
  Hashtbl.mem tbl f

(* An abbreviation hides the arrow: the walk expands nothing — the
   documented false negative. *)
type callback = int -> int

let g : callback = fun x -> x
let tbl_cb : (callback, string) Hashtbl.t = Hashtbl.create 7
let n2 = Hashtbl.mem tbl_cb g

(* The arity-3 legs (the apply3 leg): add and
   replace hash their key argument, hash_param its third. *)
let p11 = Hashtbl.add tbl f "kept" (* FIRE *)
let p12 = Hashtbl.replace tbl f "kept" (* FIRE *)
let p13 = Hashtbl.hash_param 10 100 f (* FIRE *)

(* A *value* that is a function is fine; only the key position is
   hashed and compared. *)
let tbl_v : (int, int -> int) Hashtbl.t = Hashtbl.create 7
let n3 = Hashtbl.add tbl_v 3 f

(* A Hashtbl.Make instance carries the functor's own identities — and its
   custom hash is exactly the remedy. *)
module H = Hashtbl.Make (struct
  type t = int -> int

  let equal _ _ = true
  let hash _ = 0
end)

let inst : string H.t = H.create 7
let n4 = H.mem inst f

(* Partial application refuses by arity. *)
let n5 = Hashtbl.mem tbl

(* A vendored Base lookalike carries local identities: out of scope. *)
module Base = struct
  module Hashtbl = struct
    let mem _ _ = false
  end
end

let n6 = Base.Hashtbl.mem 0 f

(* Adversarial: a type variable proves nothing. *)
let lookup t k = Hashtbl.mem t k

(* Spec positive pinned clean for now: tuple components are not walked
   until a version-stable tuple seam exists. *)
let tbl_pair : ((int -> int) * int, string) Hashtbl.t = Hashtbl.create 7
let n7 = Hashtbl.mem tbl_pair (f, 3)
