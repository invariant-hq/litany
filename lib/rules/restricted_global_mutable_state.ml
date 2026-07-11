(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"restricted-global-mutable-state" ~group:Rule.Restriction
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"toplevel mutable state in library code"
    ~doc:
      {|A `ref`, `Hashtbl.t`, or mutable-record value bound at a library's
toplevel lives for the whole process: every consumer shares it, tests
interfere through it, two domains race on it, and no caller can create
a second independent instance. Litany's own law — pure core, state in
the driver — is this rule, self-applied.

    (* bad *)  let registry : (string, handler) Hashtbl.t = Hashtbl.create 16
    (* good *) a table created by the caller and passed down, or a
               `create`d value the API threads explicitly

Why restrict this? Deliberate globals are legitimate — fmt's style
store and cmdliner's uid counter are designed — and the field count is
small (2 sightings in ~9,700 reviewed lines), so a ban is house
policy, not a defect claim: off even under `--select all`,
cherry-picked by a
workspace whose libraries keep state in the caller. The known
false-positive shapes are named up front: memo tables, interning
pools, and caches are deliberate state, and `[@litany.allow]` with a
reason is the designed outlet — a lazy cache (`let table = lazy …`)
is already the blessed initialize-once spelling and stays clean by
shape.

Fires once per variable bound by an item of the unit's root structure —
a root `include struct ... end`'s items included: they land on the
unit's export surface like any root item — whose type's head is
`Stdlib.ref`, `Stdlib.Hashtbl.t`, or a record type declared at the
unit's root with a `mutable` field, in units whose roster kind is
`Library`. Executables and tests own their
process and never fire; a unit whose roster carries no kind is
deliberately silent — a metadata-gated rule degrades to silence,
never to guessing. Local bindings inside functions and
let-expressions, `lazy` thunks, pure records, and functions that
merely return fresh state deliberately do not fire. Arrays are out of
scope in v1: the array type does not distinguish a buffer from state —
a lookup-table literal and a mutable accumulator spell the same type —
so an array ban would claim a structural proof the type cannot give.
Abbreviation heads are compared as inferred, never expanded
(`type counter = int ref` stays clean), a mutable-record head the
unit does not declare at its own root — a nested module's, one
`include`d from a named module, another unit's — stays clean, and a
binding that binds no variable or destructures stays clean: each is a
recorded false negative in the safe direction. No fix: moving state
into the caller is an API redesign.|}
    ~kind_gated:true ()

let message =
  "toplevel mutable state in a library is a process-wide global; create it in \
   the caller and pass it down"

(* The named mutable heads, by declaration identity: aliases and opens
   resolve through, a same-spelled local module's [t] never matches. *)
let mutable_named_head = Pat.(typ "Stdlib.ref" ||| typ "Stdlib.Hashtbl.t")

(* The unit's root items, `include struct ... end` payloads flattened in:
   an included structure's bindings land on the unit's root surface, so
   its items are root items — the doc's own letter. The descent
   unwraps ascribing constraints and recurses
   through nested includes; any other module expression under [include]
   (a named module, a functor application) namespaces its contents away
   and stays out, like a [module M = struct ... end] item. *)
let root_item_exists u pred =
  let rec item (it : Typedtree.structure_item) =
    match it.Typedtree.str_desc with
    | Typedtree.Tstr_include incl -> included incl.Typedtree.incl_mod
    | _ -> pred it
  and included (m : Typedtree.module_expr) =
    match m.Typedtree.mod_desc with
    | Typedtree.Tmod_structure str -> List.exists item str.Typedtree.str_items
    | Typedtree.Tmod_constraint (m, _, _, _) -> included m
    | _ -> false
  in
  List.exists item (Unit.implementation u).Typedtree.str_items

(* [root_mutable_record u id] is [true] iff [id] is declared by a
   root-structure [type] item of [u] as a record with a [mutable] field.
   A [Pident] head can only name a root-scope declaration (nested
   modules' types escape through [Pdot] paths), so the root scan is the
   whole population. *)
let root_mutable_record u id =
  let mutable_label (l : Types.label_declaration) =
    match l.Types.ld_mutable with
    | Asttypes.Mutable -> true
    | Asttypes.Immutable -> false
  in
  let declares (d : Typedtree.type_declaration) =
    Ident.same d.typ_id id
    &&
    match d.typ_type.Types.type_kind with
    | Types.Type_record (labels, _) -> List.exists mutable_label labels
    | _ -> false
  in
  root_item_exists u (fun item ->
      match item.Typedtree.str_desc with
      | Typedtree.Tstr_type (_, decls) -> List.exists declares decls
      | _ -> false)

(* Head test only: no abbreviation expansion, no container walking —
   unknown heads stay clean (the invalid-hashtable-key posture). *)
let structurally_mutable u (ty : Types.type_expr) =
  match Pat.run mutable_named_head u ty () with
  | Some () -> true
  | None -> (
      match Types.get_desc ty with
      | Types.Tconstr (Path.Pident id, _, _) -> root_mutable_record u id
      | _ -> false)

(* The dispatched binding is toplevel iff it is a binding of a root
   structure item — physical identity, the engine dispatches the tree's
   own payloads (the missing-printer join). *)
let toplevel_binding u (vb : Typedtree.value_binding) =
  root_item_exists u (fun item ->
      match item.Typedtree.str_desc with
      | Typedtree.Tstr_value (_, vbs) -> List.memq vb vbs
      | _ -> false)

let rule =
  Rule.binding meta @@ fun u vb ->
  match Unit.kind u with
  | Some Unit.Library -> (
      match Pat.bound_var vb.Typedtree.vb_pat with
      | Some (name, _)
        when toplevel_binding u vb
             && structurally_mutable u vb.Typedtree.vb_pat.pat_type ->
          [ Finding.v ~loc:name.Location.loc message ]
      | Some _ | None -> [])
  | Some Unit.Executable | Some Unit.Test | None -> []
