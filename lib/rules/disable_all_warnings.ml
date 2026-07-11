(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"disable-all-warnings" ~group:Rule.Suspicious ~since:"1.0"
    ~fix:Rule.Never ~summary:"a warning attribute disables every warning"
    ~doc:
      {|`[@@@warning "-a"]` (and its spellings `"-A"` and `"a"`) clears
warning set `a` — OCaml's complete warning set — hiding every problem the
compiler would otherwise report from that point on.

    (* bad *)  [@@@warning "-a"]
    (* good *) [@@@warning "-27-32"]   (* name the warnings, with a reason *)

Fires on `warning` and `ocaml.warning` attributes, attached or floating,
whose payload is exactly one of the standalone disable-everything
specifications. Selective or compound specifications (`"-27"`, `"-a+31"`),
enabling specifications (`"+a"`), other payload shapes, and similarly
named attributes deliberately do not fire. A finding describes the
directive, not the final warning state after sibling or inherited
attributes. No fix: removing or narrowing an override needs knowledge of
the warnings intentionally managed at that scope.|}
    ()

(* The standalone disable-everything spellings: lowercase clears set [a]
   (every warning), and the minus sign makes the uppercase spelling clear it
   too. Anything longer states a narrower intent. *)
let disables_all = function "-A" | "-a" | "a" -> true | _ -> false

let rule =
  (* Declared names gate the engine's parse demand: a source that spells
     neither attribute name never pays the pre-PPX parse for this rule. *)
  Rule.attribute ~names:[ "warning"; "ocaml.warning" ] meta @@ fun _unit attr ->
  match attr.Parsetree.attr_name.txt with
  | "warning" | "ocaml.warning" -> (
      match Pat.payload_string attr.attr_payload with
      | Some (spec, _) when disables_all spec ->
          [
            Finding.v ~loc:attr.attr_loc
              "attribute disables all compiler warnings";
          ]
      | Some _ | None -> [])
  | _ -> []
