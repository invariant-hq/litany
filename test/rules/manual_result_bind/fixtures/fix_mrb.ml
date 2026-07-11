(* Fixture for manual-result-bind: positives carry the FIRE marker; every
   other binding is a negative lookalike from the spec plus adversarial
   extras. The alias spelling is a recorded false negative until a
   pattern-alias view lands — pinned below without a marker. *)

let submit d = Ok (d + 1)
let resolve x = if x > 0 then Ok x else Error "neg"
let wrap e = "w:" ^ e

(* The bind shape, error-first order. *)
let p1 r = match r with Error e -> Error e | Ok d -> submit d (* FIRE *)

(* Ok-first order. *)
let p2 r = match r with Ok x -> resolve x | Error e -> Error e (* FIRE *)

(* A ladder yields one finding per rung — one-line rungs keep each
   marker on its own match line. *)
let rung before =
  match submit before with Error e -> Error e | Ok a -> resolve a (* FIRE *)

let ladder t =
  match resolve t with Error e -> Error e | Ok b -> rung b (* FIRE *)

(* A hand-defined binding operator is literally the bind definition. *)
let ( let* ) result f =
  match result with Ok v -> f v | Error e -> Error e (* FIRE *)

let use_star r =
  let* v = r in
  resolve v

(* The bare-function form. *)
let p5 = function Ok x -> resolve x | Error e -> Error e (* FIRE *)

(* negative: the error payload is transformed, not rebuilt. *)
let n1 f r = match r with Ok x -> f x | Error e -> Error (wrap e)

(* negative: the Ok arm is an Ok construction — manual-result-map's
   territory, exact partition. *)
let n2 r = match r with Ok x -> Ok x | Error e -> Error e

(* negative: the Error right-hand side is an application, not an Error
   construction — no canonical rewrite. *)
let response_error e = Error (wrap e)
let n3 r = match r with Ok v -> resolve v | Error e -> response_error e

(* negative: the error is dropped, not propagated. *)
let n4 r = match r with Ok x -> resolve x | Error _ -> Error "dropped"

(* negative: a guard. *)
let n5 r = match r with Ok x when x > 0 -> resolve x | r' -> r'

(* negative: an exception arm is a third case. *)
let n8 g =
  match g () with
  | Ok x -> resolve x
  | Error e -> Error e
  | exception Not_found -> Error "nf"

(* negative (recorded false negative, pinned): the alias spelling needs a
   pattern-alias view. *)
let n9 r = match r with Ok x -> resolve x | Error _ as e -> e

(* negative (adversarial): a user variant spelling Ok/Error. *)
module UserRes = struct
  type ('a, 'e) t = Ok of 'a | Error of 'e

  let keep g v = match v with Ok x -> g x | Error e -> Error e
end

(* negative: a deep payload pattern. *)
let n10 r =
  (match r with Ok (Some x) -> resolve x | Error e -> Error e) [@warning "-8"]

(* negative (adversarial): the rebuild widens through a coercion, where
   Result.bind would not typecheck — the typing side condition refuses. *)
let resolve2 x : (int, [ `A | `B ]) result = if x > 0 then Ok x else Error `B

let n11 (r : (int, [ `A ]) result) : (int, [ `A | `B ]) result =
  match r with Ok x -> resolve2 x | Error e -> Error (e :> [ `A | `B ])

(* negative (self-definition gate, stdppx.ml:295): a module named Result
   defining its own like-named bind must not be told to use Result.bind. *)
module Result = struct
  let bind t ~f = match t with Ok a -> f a | Error e -> Error e
end

(* still fires: the like-named bind outside a module named Result — the
   gate is the module, not the name. *)
let bind r g = match r with Ok x -> g x | Error e -> Error e (* FIRE *)
