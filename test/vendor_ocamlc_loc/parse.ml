(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Cram-side oracle: reads a report page on stdin, parses it with dune's
   vendored ocamlc-loc parser, and prints one deterministic line per parsed
   report — the same shape as test_render's [show_report] — so the CLI
   crams can prove that what litany emits is what dune's editor pipeline
   receives. Prints "0 reports" for an unparseable stream: an empty pin
   would read as "nothing ran". *)

module Ocamlc_loc = Vendor_ocamlc_loc.Ocamlc_loc

let show_loc (l : Ocamlc_loc.loc) =
  let lines =
    match l.lines with
    | Ocamlc_loc.Single n -> string_of_int n
    | Ocamlc_loc.Range (a, b) -> Printf.sprintf "%d-%d" a b
  in
  let chars =
    match l.chars with None -> "?" | Some (a, b) -> Printf.sprintf "%d-%d" a b
  in
  Printf.sprintf "%s:%s:%s" l.path lines chars

let show_severity = function
  | Ocamlc_loc.Warning { Ocamlc_loc.code; name } ->
      Printf.sprintf "warning %d [%s]" code name
  | Ocamlc_loc.Error None -> "error"
  | Ocamlc_loc.Error (Some _) -> "error(structured)"
  | Ocamlc_loc.Alert { name; source } ->
      Printf.sprintf "alert %s %s" name source

let show_report (r : Ocamlc_loc.report) =
  Printf.sprintf "%s %s %S%s" (show_loc r.loc) (show_severity r.severity)
    r.message
    (String.concat ""
       (List.map
          (fun (l, m) -> Printf.sprintf " [related %s %S]" (show_loc l) m)
          r.related))

let () =
  let input = In_channel.input_all In_channel.stdin in
  match Ocamlc_loc.parse input with
  | [] -> print_string "0 reports\n"
  | reports -> List.iter (fun r -> print_endline (show_report r)) reports
