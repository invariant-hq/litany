(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-unused-module-binding" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"module binding the unit never uses and never exports"
    ~doc:
      {|A named module binding that the unit never references, and that
nothing outside the unit can reference, is dead text: a local
`let module M = … in e` whose body never mentions `M`, or a toplevel
`module M = …` in a unit whose interface does not export `M`. The
compiler's warning 60 makes exactly this judgment soundly — and ships
disabled in every mainstream default, so in practice no one has ever
seen it. This rule makes the same judgment from the artifact,
config-independently: uses are counted by resolved identity over every
path the typedtree stores, and export is read from the unit's own
compiled interface.

    (* bad *)  let module Tbl = Hashtbl.Make (Int) in body  (* Tbl unseen *)
    (* good *) module _ = struct let () = register () end   (* effect-only *)

Fires at the binder's name when it is never used: for a `let module`
unit-wide emptiness is exactly body emptiness; for a toplevel binding
the interface must exist and hide the name — a unit without an `.mli`
exports everything through its inferred signature and stays silent,
exactly where an enabled warning 60 is also silent. Module bindings
nested inside sub-structures need per-path signature reasoning and are
recorded false negatives; `Pstr_recmodule` groups are not dispatched.
The anonymous `module _ = …` is the sanctioned effect-only spelling
and refuses by construction. The interface substrate is not
witness-checked in 1.0: a stale `.cmti` can misreport export and skew
this rule's gate — a named risk for the graduation review. No fix: a
module body can perform effects at initialization, so deletion is
never mechanical.|}
    ()

let local_message = "this local module is never used"

let toplevel_message =
  "this module is never used in the unit and its interface does not export it"

(* Export is by name at the interface; signature [include]s arrive
   pre-expanded in [sig_type]. Only [Exported]-visibility rows count —
   the hand-rolled walk carries the visibility filter. *)
let exports_module (sg : Typedtree.signature) name =
  List.exists
    (function
      | Types.Sig_module (id, _, _, _, Types.Exported) ->
          String.equal (Ident.name id) name
      | _ -> false)
    sg.sig_type

(* Structural gates first, [module_uses] last: units that
   cannot fire never build the index. *)
let rule =
  Rule.module_binding meta @@ fun u mb ->
  match Rule.Module_binding.id mb with
  | None -> []
  | Some m ->
      let position = Rule.Module_binding.position mb in
      let eligible =
        (not (Rule.Module_binding.loc mb).Location.loc_ghost)
        &&
        match position with
        | Rule.Module_binding.Local -> true
        | Rule.Module_binding.Nested -> false
        | Rule.Module_binding.Toplevel -> (
            match Unit.interface u with
            | None -> false
            | Some sg -> not (exports_module sg (Ident.name m)))
      in
      if eligible && Unit.module_uses u m = [] then
        let message =
          match position with
          | Rule.Module_binding.Local -> local_message
          | Rule.Module_binding.Toplevel | Rule.Module_binding.Nested ->
              toplevel_message
        in
        [ Finding.v ~loc:(Rule.Module_binding.name_loc mb) message ]
      else []
