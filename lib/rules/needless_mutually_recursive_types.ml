(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"needless-mutually-recursive-types" ~group:Rule.Style
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"and-chained type that is not mutually recursive with its group"
    ~doc:
      {|An `and`-chained type group asserts to the reader that its members
are mutually recursive. A member that participates in no reference
cycle with its siblings makes the assertion false coupling: the group
reads as co-dependent, refactors move it as a block, and the actual
dependency structure is hidden.

    (* bad *)  type t1 = A of t2 and t2 = B of t1 and t3 = C of t1
    (* good *) type t1 = A of t2 and t2 = B of t1
               type t3 = C of t1

Fires once per member of a multi-declaration group that is mutually
reachable with no sibling over the identity-resolved reference graph —
each such declaration can stand as its own `type` item (type
declarations are recursive by default, so even a self-recursive
singleton extracts cleanly, unlike `let`). Members of a genuine cycle
never fire, and a singleton group has no `and` to indict. Edges are by
declaration identity, so a same-named outer type never confuses the
graph, and under `nonrec` no sibling edge can exist — every member of
a multi-declaration `nonrec` group reports, derived rather than
special-cased. No fix: splitting the group is a reordering of
declarations, not a span edit, and computing a correct order is out of
scope.|}
    ()

let message name =
  Printf.sprintf
    "%s is declared with 'and' but is not mutually recursive with its group — \
     declare it as its own type"
    name

(* Edges by declaration identity: [di -> dj] iff [dj]'s ident appears as
   a [Pident] head in [di]'s type references. Sibling references are
   always unqualified (group members live in no module), so the [Pident]
   head is the complete carrier; a same-named outer type is a different
   [Ident] and contributes no edge. Reachability is a closure over the
   tiny group — quadratic is fine at fixture-scale groups. *)
let rule =
  Rule.type_decl meta @@ fun _u ds ->
  match ds with
  | [] | [ _ ] -> []
  | _ ->
      let arr = Array.of_list ds in
      let n = Array.length arr in
      let ids = Array.map (fun d -> d.Typedtree.typ_id) arr in
      let reach = Array.make_matrix n n false in
      Array.iteri
        (fun i d ->
          List.iter
            (function
              | Path.Pident id ->
                  Array.iteri
                    (fun j tj -> if Ident.same id tj then reach.(i).(j) <- true)
                    ids
              | _ -> ())
            (Pat.type_refs d))
        arr;
      for k = 0 to n - 1 do
        for i = 0 to n - 1 do
          for j = 0 to n - 1 do
            if reach.(i).(k) && reach.(k).(j) then reach.(i).(j) <- true
          done
        done
      done;
      let mutual i =
        let found = ref false in
        for j = 0 to n - 1 do
          if j <> i && reach.(i).(j) && reach.(j).(i) then found := true
        done;
        !found
      in
      List.concat
        (List.mapi
           (fun i (d : Typedtree.type_declaration) ->
             if mutual i then []
             else [ Finding.v ~loc:d.typ_name.loc (message d.typ_name.txt) ])
           ds)
