(* Fixture for manual-option-value: positives carry the FIRE marker; every
   other binding is a negative lookalike from the spec plus adversarial
   extras. *)

let default_name = "anon"

(* Literal default. *)
let p1 o = Option.value o ~default:0 (* FIRE *)

(* Reversed order, identifier default. *)
let p2 name = Option.value name ~default:default_name (* FIRE *)

(* Function form, nullary-constructor default: report only. *)
let p3 = function Some x -> x | None -> [] (* FIRE *)

(* Argument position: the parenthesized match's location includes the
   parentheses; the application replacement restores them. *)
let p4 o = succ (Option.value o ~default:0) (* FIRE *)

(* negative: an effectful default — the eager rewrite would change
   behavior (recorded deliberate false negative) *)
let compute () = 7
let n1 o = match o with Some x -> x | None -> compute ()

(* negative: a raising default is Option.get with intent *)
let n2 o = match o with Some x -> x | None -> raise Not_found

(* negative: the Some arm transforms — Option.fold territory *)
let n3 f o = match o with Some x -> f x | None -> 0

(* negative: a guard *)
let n4 o = match o with Some x when x > 0 -> x | Some _ -> 0 | None -> 0

(* negative (adversarial): user Some/None constructors *)
module UserOpt = struct
  type t = Some of int | None

  let get v = match v with Some x -> x | None -> 0
end

(* negative: unused payload — Option.is_some shaped *)
let n5 o = match o with Some _ -> 1 | None -> 0

(* negative (adversarial extra): an aliased payload is a different shape *)
let n6 o = match o with Some x as _s -> x | None -> 0

(* TODO negative, re-confirmed 2026-08-20: the class
   optional-argument elaboration still fires —
   [class c ?(x = 0) () = object end] elaborates to a trivial-default
   option match on the ghost [*opt*] scrutinee, and the claimed-Safe fix
   rewrites the default to [Option.value 0 ~default:0], which does not
   typecheck. The shape cannot join this fixture until the ghost-
   scrutinee guard lands (it would fire, breaking the markers); when the
   guard lands, add:

     class todo_cls ?(x = 0) () = object method x = x end

   as a compiled negative. Blocks graduation (maintainer decision). *)
