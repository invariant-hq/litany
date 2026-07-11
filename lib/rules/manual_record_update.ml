(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-record-update" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never ~summary:"record rebuilt field by field from one base"
    ~doc:
      {|A record expression that copies two or more fields verbatim from one
base record is `{ base with ... }` written longhand: more text, and the
reader must verify field by field that the copies are copies. When every
field is a verbatim copy of an immutable record, the expression is the
base itself.

    (* bad *)  { x = r.x; y = r.y; z = 15 }
    (* good *) { r with z = 15 }

Fires once per extension-less record expression in which some identifier
base has at least two fields copied verbatim — `l = b.l`, same label by
declaration identity: equal name and `Path.same` record head, so the
base necessarily has the constructed type and a cross-type rewrite —
suggesting `{ b with … }` against a different record type — is
structurally impossible. Fields copied from a different base, and
punned fields (which elaborate to bare identifiers, not accesses),
count as overrides and simply stay spelled out. When every field is a
copy the message says the record is the base itself — unless some
label is mutable, where the full rebuild is the deliberate copy idiom
and the rule stays silent. A base that is not an identifier
(`(get r).x`) never counts: re-evaluating it under `with` would change
effects. A one-copy record does not fire — `{ b with ... }` would
rewrite nearly the whole literal, a deliberate narrowing: one copied
field is not evidence of an update idiom. No fix: the rewrite deletes
and reorders fields;
the message shows the target form. Fields arrive in the record type's
declaration order (the typedtree does not record source order), so
multi-override messages list overrides in declaration order — a
cosmetic note, not a defect. Same-typed serialization boilerplate that
copies deliberately for explicitness is what Style/off respects.|}
    ()

(* A record literal with no [with] extension — an expression already
   using [with] is the remedy and refuses at the view. *)
let plain_record = Pat.(erecord none)

(* One candidate copy source: a field access [b.l] on an identifier
   base, capturing the accessed label and the base path. *)
let copy_source = Pat.(efield var)

(* Same label by declaration identity: equal name and [Path.same]
   record-type head. Same label implies same record type, so the base
   has the constructed type — the probe-pinned cross-type refusal. *)
let same_label l l' =
  String.equal (Pat.Lbl.name l) (Pat.Lbl.name l')
  &&
  match (Pat.Lbl.res_head l, Pat.Lbl.res_head l') with
  | Some p, Some p' -> Path.same p p'
  | _, _ -> false

(* [copy_base u f] is the base path when field [f] is defined as a
   verbatim copy [l = b.l] of the very label it defines, and [None]
   when the field is an override of any kind. *)
let copy_base u f =
  match Pat.Field.definition f with
  | None -> None
  | Some d ->
      Option.join
        (Pat.run copy_source u d (fun lbl base ->
             if same_label (Pat.Field.label f) lbl then Some base else None))

let count_copies base sources =
  List.length
    (List.filter
       (function Some p -> Path.same p base | None -> false)
       sources)

(* The base with the most verbatim copies; ties resolve to the first
   base in field order, keeping the finding deterministic. *)
let best_base sources =
  let distinct =
    List.rev
      (List.fold_left
         (fun acc -> function
           | Some p when not (List.exists (Path.same p) acc) -> p :: acc
           | _ -> acc)
         [] sources)
  in
  List.fold_left
    (fun best p ->
      let n = count_copies p sources in
      match best with Some (_, m) when m >= n -> best | _ -> Some (p, n))
    None distinct

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run plain_record u e Fun.id with
  | None -> []
  | Some fields -> (
      let sources = List.map (copy_base u) fields in
      match best_base sources with
      | Some (base, n) when n >= 2 ->
          let b = Path.name base in
          if n = List.length fields then
            if
              List.exists
                (fun f -> Pat.Lbl.is_mutable (Pat.Field.label f))
                fields
            then [] (* full rebuild of a mutable record: the copy idiom *)
            else
              [
                Finding.v ~loc:e.exp_loc
                  (Printf.sprintf
                     "this record rebuilds %s field by field; it is %s itself" b
                     b);
              ]
          else
            let overrides =
              List.filter_map
                (fun (f, src) ->
                  match src with
                  | Some p when Path.same p base -> None
                  | Some _ | None -> Some (Pat.Lbl.name (Pat.Field.label f)))
                (List.combine fields sources)
            in
            [
              Finding.v ~loc:e.exp_loc
                (Printf.sprintf "copy the base with { %s with %s }" b
                   (String.concat "; "
                      (List.map (fun l -> l ^ " = ...") overrides)));
            ]
      | Some _ | None -> [])
