(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

module Uid = struct
  type t = Shape.Uid.t

  (* Synthetic identities — test universes and the dead-code rule's
     unit-level nodes — ride the [Compilation_unit] constructor: total order
     and printing shared with real declaration UIDs, no parallel namespace.
     [of_compilation_unit_id] is deterministic (it records the ident's
     name). *)
  let v s = Shape.Uid.of_compilation_unit_id (Ident.create_persistent s)
  let to_string uid = Format.asprintf "%a" Shape.Uid.print uid
  let equal = Shape.Uid.equal
  let compare = Shape.Uid.compare
  let pp = Shape.Uid.print
end

module Decl = struct
  type t = { uid : Uid.t; owner : string; root : bool }

  let v ~uid ~owner ~root = { uid; owner; root }
  let uid decl = decl.uid
  let owner decl = decl.owner
  let is_root decl = decl.root

  let equal left right =
    Uid.equal left.uid right.uid
    && String.equal left.owner right.owner
    && Bool.equal left.root right.root

  let compare left right =
    let order = String.compare left.owner right.owner in
    if order <> 0 then order
    else
      let order = Uid.compare left.uid right.uid in
      if order <> 0 then order else Bool.compare left.root right.root

  let pp ppf decl =
    Format.fprintf ppf "%s/%a%s" decl.owner Uid.pp decl.uid
      (if decl.root then " (root)" else "")
end

module Edge = struct
  type t = { user : Uid.t; used : Uid.t }

  let v ~user ~used = { user; used }
  let user edge = edge.user
  let used edge = edge.used

  let equal left right =
    Uid.equal left.user right.user && Uid.equal left.used right.used

  let compare left right =
    let order = Uid.compare left.user right.user in
    if order <> 0 then order else Uid.compare left.used right.used

  let pp ppf edge =
    Format.fprintf ppf "%a uses %a" Uid.pp edge.user Uid.pp edge.used
end

module Uid_map = Map.Make (Uid)

(* Merge duplicate facts: one declaration per uid, root iff any duplicate is a
   root. An owner conflict is a corrupt universe — fail loudly. *)
let merged_decls decls =
  List.fold_left
    (fun merged decl ->
      Uid_map.update (Decl.uid decl)
        (function
          | None -> Some decl
          | Some previous ->
              if not (String.equal (Decl.owner previous) (Decl.owner decl)) then
                invalid_arg
                  (Format.asprintf
                     "Dead_code_solver.unreachable: uid %a declared by both %s \
                      and %s"
                     Uid.pp (Decl.uid decl) (Decl.owner previous)
                     (Decl.owner decl))
              else if Decl.is_root decl then Some decl
              else Some previous)
        merged)
    Uid_map.empty decls

let unreachable ~decls ~edges =
  let decls = merged_decls decls in
  let count = Uid_map.cardinal decls in
  let index_of_uid = Hashtbl.create (max 16 count) in
  let decl_array = Array.make (max 1 count) None in
  let next = ref 0 in
  Uid_map.iter
    (fun uid decl ->
      Hashtbl.replace index_of_uid uid !next;
      decl_array.(!next) <- Some decl;
      incr next)
    decls;
  let successors = Array.make (max 1 count) [] in
  List.iter
    (fun edge ->
      match
        ( Hashtbl.find_opt index_of_uid (Edge.user edge),
          Hashtbl.find_opt index_of_uid (Edge.used edge) )
      with
      | Some user, Some used -> successors.(user) <- used :: successors.(user)
      | (None | Some _), (None | Some _) -> ())
    edges;
  let reached = Array.make (max 1 count) false in
  let stack = Stack.create () in
  Array.iteri
    (fun index decl ->
      match decl with
      | Some decl when Decl.is_root decl ->
          reached.(index) <- true;
          Stack.push index stack
      | Some _ | None -> ())
    decl_array;
  while not (Stack.is_empty stack) do
    let index = Stack.pop stack in
    List.iter
      (fun used ->
        if not reached.(used) then begin
          reached.(used) <- true;
          Stack.push used stack
        end)
      successors.(index)
  done;
  let dead = ref [] in
  Array.iteri
    (fun index decl ->
      match decl with
      | Some decl when not reached.(index) -> dead := decl :: !dead
      | Some _ | None -> ())
    decl_array;
  List.sort Decl.compare !dead
