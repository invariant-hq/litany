(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"needless-and-binding" ~group:Rule.Style
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"let rec binding riding an and-chain it does not need"
    ~doc:
      {|A `let rec … and …` chain asserts co-dependence. A binding that
neither calls itself through the group nor participates in any
reference cycle with its siblings is riding a chain it doesn't need:
readers assume the bindings are entangled, and the group resists being
split or moved.

    (* bad *)  let rec is_even n = n = 0 || is_odd (n - 1)
               and is_odd n = n <> 0 && is_even (n - 1)
               and double x = x + x
    (* good *) let rec is_even n = n = 0 || is_odd (n - 1)
               and is_odd n = n <> 0 && is_even (n - 1)
               let double x = x + x

Fires once per binding of a recursive multi-binding group that is
mutually reachable with no sibling over the identity-resolved
reference graph — self-recursive-only bindings extract as their own
`let rec`, inert bindings as a plain `let`; the message says which.
Members of a genuine cycle never fire, and groups where no binding
references the group at all are suspicious-rec-without-recursion's
finding, never this rule's — an exact partition. Edges are proved from
the unit's use index by declaration identity, so a same-spelled inner
rebinding contributes no edge; an unplaceable use or a non-variable
pattern refuses the group conservatively. Warning 39 is silent on
every positive here (it needs the whole group inert). No fix:
extraction reorders bindings above or below the group — guidance, not
an edit.|}
    ()

let self_message name =
  Printf.sprintf
    "%s is recursive but not mutually recursive with its group — extract it as \
     its own let rec"
    name

let inert_message name =
  Printf.sprintf
    "%s references no binding of its group — extract it as a plain let" name

let span_of_loc (loc : Location.t) =
  let start = loc.Location.loc_start.Lexing.pos_cnum
  and stop = loc.Location.loc_end.Lexing.pos_cnum in
  if start < 0 || stop < start then None else Some (Span.v ~start ~stop)

(* Edges from the use index by identity: [i -> j] iff a use of binding
   [j]'s UID lands inside binding [i]'s body span. An unplaceable use
   refuses the group — the sibling rule's posture, verbatim. *)
let rule =
  Rule.let_group meta @@ fun u ~loc:_ rf vbs ->
  match (rf, vbs) with
  | Asttypes.Nonrecursive, _ | Asttypes.Recursive, ([] | [ _ ]) -> []
  | Asttypes.Recursive, vbs -> (
      let rec rows acc = function
        | [] -> Some (Array.of_list (List.rev acc))
        | vb :: rest -> (
            match
              ( Pat.bound_var vb.Typedtree.vb_pat,
                span_of_loc vb.Typedtree.vb_expr.exp_loc )
            with
            | Some (name, uid), Some body ->
                rows
                  ((name, uid, body, vb.Typedtree.vb_pat.pat_loc) :: acc)
                  rest
            | _, _ -> None)
      in
      match rows [] vbs with
      | None -> []
      | Some rows ->
          let n = Array.length rows in
          let reach = Array.make_matrix n n false in
          let placeable = ref true in
          Array.iteri
            (fun j (_, uid, _, _) ->
              List.iter
                (fun use_loc ->
                  match span_of_loc use_loc with
                  | None -> placeable := false
                  | Some use ->
                      Array.iteri
                        (fun i (_, _, body, _) ->
                          if Span.includes body use then reach.(i).(j) <- true)
                        rows)
                (Unit.uses u uid))
            rows;
          let any_edge = Array.exists (Array.exists Fun.id) reach in
          if (not !placeable) || not any_edge then []
          else begin
            let self = Array.init n (fun i -> reach.(i).(i)) in
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
              (List.init n (fun i ->
                   if mutual i then []
                   else
                     let name, _, _, anchor = rows.(i) in
                     let message =
                       if self.(i) then self_message name.Location.txt
                       else inert_message name.Location.txt
                     in
                     [ Finding.v ~loc:anchor message ]))
          end)
