(* Fixture for suspicious-swallowed-cancellation: positives carry the
   FIRE marker; negatives are the spec's disciplined shapes plus
   adversarial extras. The [Eio] unit is the fixture's vendored stub —
   [Pat.from_unit] matches by compilation-unit name. *)

exception Wrapped of exn

let nf : (string list, exn) result = Error Not_found

(* A total var arm converts to a value; the specific sibling arm does
   not pass Cancelled through, so the handler still fires. *)
let p1 path =
  let r =
    try Ok (Eio.Path.read_dir (Filename.concat path "sub")) with
    | Not_found -> nf
    | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
    | e -> Error e (* FIRE *)
  in
  r

(* An inline total arm: the finding fires; the fix needs the arm on its
   own [| ]-prefixed line and is withheld. *)
let p2 path = try Ok (Eio.Path.stat path) with e -> Error e (* FIRE *)

(* A wildcard total arm. *)
let p3 path =
  let r =
    try Some (Eio.Path.read_dir (Filename.concat path "sub")) with
    | Not_found -> None
    | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
    | _ -> None (* FIRE *)
  in
  r

(* A wrap-raise still converts cancellation into a non-cancellation;
   inline arm, so no fix. *)
let p4 path = try Eio.Path.stat path with e -> raise (Wrapped e) (* FIRE *)

(* The match form's exception cases; the region is the scrutinee. *)
let p5 g path =
  let r =
    match g (Eio.Path.read_dir (Filename.concat path "sub")) with
    | names -> Ok names
    | exception (Eio.Cancel.Cancelled _ as cancelled) -> raise cancelled
    | exception e -> Error e (* FIRE *)
  in
  r

(* negative: the alias-arm re-raise discipline — the Cancelled guard arm above. *)
let n1 path =
  try Ok (Eio.Path.read_dir path) with
  | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
  | e -> Error (Printexc.to_string e)

(* negative: the guard above a wrap-raise. *)
let n2 path =
  try Eio.Path.stat path with
  | Eio.Cancel.Cancelled _ as e -> raise e
  | e -> raise (Wrapped e)

(* negative: the total arm re-raises its binder — nothing converts. *)
let n3 path = try Eio.Path.stat path with e -> raise e

let n4 bt path =
  try Eio.Path.stat path with e -> Printexc.raise_with_backtrace e bt

(* negative: a total handler around pure code — not eio-bearing. *)
let n5 g = try Ok (g 1) with e -> Error e

(* negative: an eio function passed as an argument is not an
   application head — the region test wants applied eio operations. *)
let n6 f = try Ok (f Eio.Path.stat) with e -> Error e

(* negative (recorded delta, pinned): a sibling alias arm re-raising a
   non-Cancelled exception silences — the spec's constructor-identity
   condition needs a pattern-side exception view. *)
let n7 path =
  try Ok (Eio.Path.read_dir path) with
  | Failure _ as f -> raise f
  | e -> Error (Printexc.to_string e)

(* negative: a match's value cases are not a handler. *)
let n8 r = match r with Some x -> Ok x | None -> Error "none"
