(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"restricted-public-exception" ~group:Rule.Restriction
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"exception declared in a public library interface"
    ~doc:
      {|An exception in a public interface is an untyped failure path every
consumer inherits: the type checker tracks no `exception` the way it
tracks a `result`, so callers learn about the escape at run time, and
the interface's signatures stop telling the whole truth about what a
call can do.

    (* bad *)  exception Parse_error of string
    (* good *) type error = [ `Parse of string ]
               val parse : string -> (t, error) result

Why restrict this? Declared exceptions are legitimate OCaml across the
ecosystem — `Not_found` and `Exit` in the standard library,
`Scanf.Scan_failure`, the error exception of nearly every parser — so
no default may claim them as defects and this is never a Suspicious
rule. A result-typed house style (errors as typed `result` values) is
policy a workspace adopts, cherry-picked by exact name, off even under
`--select all`.

Fires once per exception of the export surface of a public library
unit — the interface when the unit has one, the implementation's own
inferred signature when it does not — anchored at the implementation's
matching root `exception` declaration (the emit contract owns findings
to the editable source). The gate is the roster's: only units whose
stanza kind is `Library` and whose visibility is `Public` fire
(`Unknown` visibility is treated as `Public`, the roster's own root
convention). Executables and tests have no consumers to protect and
never fire; a private library's exceptions are the workspace's own
business; a unit whose roster carries no kind is deliberately silent —
a metadata-gated rule degrades to silence, never to guessing. An
exception the `.mli` hides, a `let exception` inside a function, and
`type t += …` extension constructors deliberately do not fire.
Recorded false negatives, in the safe direction: exceptions of
submodule signatures (the export surface joins interface to
implementation at the unit's root only) and an interface exception
satisfied by `include` (no root declaration to anchor at). No fix:
replacing an exception with a `result` is an API redesign.|}
    ~kind_gated:true ()

(* [anchor u name] is the name's location in the implementation's root
   [exception] declaration of [name] — the missing-printer seam:
   findings anchor in the editable source, joined by name at the unit's
   root, the last declaration winning exactly as the signature's row
   does. [None] — an [include]-satisfied interface exception — stays
   silent, a recorded false negative. *)
let anchor u name =
  List.fold_left
    (fun acc (item : Typedtree.structure_item) ->
      match item.Typedtree.str_desc with
      | Typedtree.Tstr_exception ext ->
          let n = ext.Typedtree.tyexn_constructor.Typedtree.ext_name in
          if String.equal n.Location.txt name then Some n.Location.loc else acc
      | _ -> acc)
    None (Unit.implementation u).Typedtree.str_items

let rule =
  Rule.export meta @@ fun u x ->
  match Unit.kind u with
  | Some Unit.Executable | Some Unit.Test | None -> []
  | Some Unit.Library -> (
      match Unit.visibility u with
      | Unit.Private -> []
      | Unit.Public | Unit.Unknown -> (
          match Unit.Export.kind x with
          | Unit.Export.Value | Unit.Export.Type | Unit.Export.Module -> []
          | Unit.Export.Exception -> (
              let name = Unit.Export.name x in
              (* Dotted rows are submodule exceptions: outside the root
                 surface this rule claims (recorded false negative). *)
              if String.contains name '.' then []
              else
                match anchor u name with
                | Some loc ->
                    [
                      Finding.v ~loc
                        (Printf.sprintf
                           "exception %s is declared in a public library \
                            interface; return a result instead"
                           name);
                    ]
                | None -> [])))
