(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type visibility = Public | Private | Unknown
type kind = Library | Executable | Test

let kind_to_string = function
  | Library -> "lib"
  | Executable -> "exe"
  | Test -> "test"

let kind_of_string = function
  | "lib" -> Some Library
  | "exe" -> Some Executable
  | "test" -> Some Test
  | _ -> None

let pp_visibility ppf v =
  Format.pp_print_string ppf
    (match v with
    | Public -> "public"
    | Private -> "private"
    | Unknown -> "unknown")

let pp_kind ppf k =
  Format.pp_print_string ppf
    (match k with
    | Library -> "library"
    | Executable -> "executable"
    | Test -> "test")

module Entry = struct
  type t = {
    source : string;
    cmt : string option;
    cmti : string option;
    preprocessed_source : string option;
    interface_source : string option;
    library : string option;
    visibility : visibility;
    kind : kind option;
  }

  let v ~source ?cmt ?cmti ?preprocessed_source ?interface_source ?library
      ?(visibility = Unknown) ?kind () =
    {
      source;
      cmt;
      cmti;
      preprocessed_source;
      interface_source;
      library;
      visibility;
      kind;
    }

  let source e = e.source
  let cmt e = e.cmt
  let cmti e = e.cmti
  let preprocessed_source e = e.preprocessed_source
  let interface_source e = e.interface_source
  let library e = e.library
  let visibility e = e.visibility
  let kind e = e.kind

  let pp ppf e =
    let opt pp_v ppf = function
      | None -> Format.pp_print_string ppf "-"
      | Some v -> pp_v ppf v
    in
    let str = Format.pp_print_string in
    Format.fprintf ppf
      "@[<hv 2>entry %s@ cmt %a@ cmti %a@ preprocessed %a@ interface %a@ \
       library %a@ visibility %a@ kind %a@]"
      e.source (opt str) e.cmt (opt str) e.cmti (opt str) e.preprocessed_source
      (opt str) e.interface_source (opt str) e.library pp_visibility
      e.visibility (opt pp_kind) e.kind

  (* Both metadata fields project rules need; see [project_capable]. *)
  let has_project_metadata e = Option.is_some e.library && Option.is_some e.kind
end

type t = { entries : Entry.t list; complete : bool; cmi_dirs : string list }

let v ?(complete = false) ?(cmi_dirs = []) entries =
  { entries; complete; cmi_dirs }

let entries r = r.entries
let complete r = r.complete
let cmi_dirs r = r.cmi_dirs

let project_capable r =
  r.complete && List.for_all Entry.has_project_metadata r.entries

let pp ppf r =
  let total = List.length r.entries in
  let with_metadata =
    List.length (List.filter Entry.has_project_metadata r.entries)
  in
  Format.fprintf ppf
    "@[roster: %d entries, %s, %d/%d with library+kind, %d cmi dirs@]" total
    (if r.complete then "complete" else "incomplete")
    with_metadata total (List.length r.cmi_dirs)
