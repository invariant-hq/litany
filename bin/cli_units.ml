(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Cmdliner

(* {1 The human dump}

   The codec's canonical shape — same header, same field order, one form
   per line — spelled as human sexps: bare atoms where the dune lexis
   allows, quoted with escapes otherwise. Not part of the codec (csexp is
   the wire; this is for eyes), but field-for-field the same document, so
   reading a dump teaches the file format. *)

let atom buf s =
  let bare =
    s <> ""
    && String.for_all
         (fun c ->
           match c with
           | ' ' | '\t' | '\n' | '\r' | '(' | ')' | '"' | ';' -> false
           | _ -> true)
         s
  in
  if bare then Buffer.add_string buf s
  else begin
    Buffer.add_char buf '"';
    String.iter
      (fun c ->
        match c with
        | '"' -> Buffer.add_string buf "\\\""
        | '\\' -> Buffer.add_string buf "\\\\"
        | '\n' -> Buffer.add_string buf "\\n"
        | '\t' -> Buffer.add_string buf "\\t"
        | '\r' -> Buffer.add_string buf "\\r"
        | c -> Buffer.add_char buf c)
      s;
    Buffer.add_char buf '"'
  end

let dump roster =
  let buf = Buffer.create 1024 in
  let field name value =
    Buffer.add_string buf " (";
    Buffer.add_string buf name;
    Buffer.add_char buf ' ';
    atom buf value;
    Buffer.add_char buf ')'
  in
  Buffer.add_string buf "(litany-units 1)\n";
  if not (Litany.Roster.complete roster) then
    Buffer.add_string buf "(complete false)\n";
  (match Litany.Roster.cmi_dirs roster with
  | [] -> ()
  | dirs ->
      Buffer.add_string buf "(cmi-dirs";
      List.iter
        (fun d ->
          Buffer.add_char buf ' ';
          atom buf d)
        dirs;
      Buffer.add_string buf ")\n");
  List.iter
    (fun entry ->
      let module E = Litany.Roster.Entry in
      Buffer.add_string buf "(unit (source ";
      atom buf (E.source entry);
      Buffer.add_char buf ')';
      Option.iter (field "cmt") (E.cmt entry);
      Option.iter (field "cmti") (E.cmti entry);
      Option.iter (field "pp-source") (E.preprocessed_source entry);
      Option.iter (field "library") (E.library entry);
      (match E.visibility entry with
      | Litany.Roster.Public -> field "public" "true"
      | Litany.Roster.Private -> field "public" "false"
      | Litany.Roster.Unknown -> ());
      Option.iter
        (fun k -> field "kind" (Litany.Roster.kind_to_string k))
        (E.kind entry);
      Buffer.add_string buf ")\n")
    (Litany.Roster.entries roster);
  Buffer.contents buf

(* {1 The command} *)

let roster_of_flags ~root ~cmt_root ~build =
  match cmt_root with
  | Some cmt_root -> (
      match Litany.Adapter.Walk.roster ~cmt_root ~source_root:root with
      | Ok roster -> Ok roster
      | Error e -> Error (Cli_common.refuse "%a" Litany.Adapter.Walk.pp_error e)
      )
  | None -> (
      if Cli_common.inside_dune () then
        Error
          (Cli_common.refuse
             "refusing to spawn dune from inside a dune action (INSIDE_DUNE is \
              set).@ Pass --cmt-root DIR to enumerate prebuilt artifacts.")
      else
        match Litany.Adapter.Dune.roster ~build ~root () with
        | Ok roster -> Ok roster
        | Error e ->
            Error (Cli_common.refuse "%a" Litany.Adapter.Dune.pp_error e))

let units root cmt_root no_build save do_dump =
  match roster_of_flags ~root ~cmt_root ~build:(not no_build) with
  | Error code -> code
  | Ok roster -> (
      (* [--dump] is the default action: a bare [litany units] shows the
         roster rather than silently doing nothing. *)
      if do_dump || save = None then print_string (dump roster);
      match save with
      | None -> Cli_common.exit_ok
      | Some file -> (
          match Litany.Adapter.Unit_file.encode roster with
          | exception Invalid_argument msg ->
              (* Duplicate sources in a roster litany itself assembled: an
                 adapter bug, not a user mistake. *)
              Format.eprintf "litany: internal error: %s@." msg;
              Cli_common.exit_internal
          | bytes -> (
              match
                Out_channel.with_open_bin file (fun oc ->
                    Out_channel.output_string oc bytes)
              with
              | () -> Cli_common.exit_ok
              | exception Sys_error msg -> Cli_common.refuse "%s" msg)))

let save_arg =
  let doc =
    "Write the roster to $(docv) as a unit file — canonical csexp, \
     byte-deterministic, consumed by $(b,litany check --units). Lossless for \
     any path bytes."
  in
  Arg.(value & opt (some string) None & info [ "save" ] ~docv:"FILE" ~doc)

let dump_arg =
  let doc =
    "Pretty-print the roster as human-readable s-expressions on standard \
     output — the same document as $(b,--save), for eyes. The default when \
     $(b,--save) is not given."
  in
  Arg.(value & flag & info [ "dump" ] ~doc)

let cmt_root =
  let doc =
    "Enumerate the .cmt artifacts under $(docv) instead of asking dune; \
     sources are paired under the workspace root. No ownership metadata: the \
     resulting file carries no library/kind fields."
  in
  Arg.(value & opt (some string) None & info [ "cmt-root" ] ~docv:"DIR" ~doc)

let no_build =
  let doc =
    "Do not run $(b,dune build @check) first; entries for stale artifacts \
     surface as skips when the file is consumed."
  in
  Arg.(value & flag & info [ "no-build" ] ~doc)

let man =
  [
    `S Manpage.s_description;
    `P
      "$(iname) enumerates the workspace's units the same way $(b,litany \
       check) does — dune by default, $(b,--cmt-root) for a bare artifact walk \
       — and serializes the roster: $(b,--save FILE) writes the canonical unit \
       file (csexp; atoms are length-prefixed raw bytes, so any filename \
       round-trips), $(b,--dump) pretty-prints it for humans.";
    `P
      "The saved file is the one interface any build system can target: \
       $(b,litany check --units FILE) consumes it from any producer, dune not \
       required. Capture one while a watch server is stopped, then lint beside \
       the running server: $(b,litany check --no-build --units FILE). Per-unit \
       witnesses still gate every join — a stale or wrong file costs skips, \
       never findings.";
  ]

let cmd =
  let info =
    Cmd.info "units" ~doc:"Save or dump the workspace's unit roster." ~man
      ~exits:Cli_common.exits
  in
  Cmd.v info
    Term.(
      const units $ Cli_common.root $ cmt_root $ no_build $ save_arg $ dump_arg)
