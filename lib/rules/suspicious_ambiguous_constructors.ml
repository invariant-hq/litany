(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-ambiguous-constructors" ~group:Rule.Suspicious
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"constructor that shadows a standard constructor"
    ~doc:
      {|A variant that declares a constructor named `Some`, `None`, `Ok`,
`Error`, `::`, or `[]` shadows a predefined or stdlib constructor for
the rest of the scope: every later unannotated `Some x` builds this
type, option/result code nearby starts needing type-directed
disambiguation, and the reader must track which `Some` is which. The
compiler's own diagnostics (warnings 41/42) fire only at use sites,
only when force-enabled, and are off in vanilla and dune-dev defaults
alike — the declaration, where the decision is actually made, is dark
everywhere.

    (* bad *)  type str_option = Some of string | None
    (* good *) type str_option = Found of string | Missing

Fires once per shadowing constructor, at its declaration. A re-export
(`type 'a maybe = 'a option = None | Some of 'a`) redeclares
constructors that already exist by construction and is exempt: a
variant kind with a manifest is necessarily the re-export form.
`exception Error of string` shadows identically but is an extension
constructor, not a variant declaration — a recorded false negative. No
fix: the remedy (rename, or prefix with the domain) is a design
decision, and a DSL that deliberately re-models this vocabulary should
carry `[@litany.allow]` with the reason at the declaration.|}
    ()

let shadowed = [ "Some"; "None"; "Ok"; "Error"; "::"; "[]" ]

let message name =
  Printf.sprintf
    "constructor %s shadows the standard %s: unannotated uses below this point \
     resolve here"
    name name

(* A variant kind with a manifest is necessarily the re-export form
   [type t = expr = A | B], whose constructors are declared elsewhere —
   the exemption is the manifest test, no path identity needed. *)
let decl_findings (d : Typedtree.type_declaration) =
  match (d.typ_kind, d.typ_manifest) with
  | Typedtree.Ttype_variant cds, None ->
      List.filter_map
        (fun (cd : Typedtree.constructor_declaration) ->
          if List.mem cd.cd_name.txt shadowed then
            Some (Finding.v ~loc:cd.cd_loc (message cd.cd_name.txt))
          else None)
        cds
  | _, _ -> []

let rule = Rule.type_decl meta @@ fun _u ds -> List.concat_map decl_findings ds
