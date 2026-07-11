(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Cmdliner

(* Resolution mirrors selection ([Cli_common.find_rule] is the lookup):
   exact name, then tombstone alias with the same rename warning wording
   [Litany.Rule.select] prints; unknown is a refusal with a did-you-mean
   over names and aliases — never a silent nothing. *)
let resolve name =
  match Cli_common.find_rule name with
  | Some (`Exact r) -> Ok r
  | Some (`Renamed r) ->
      Format.eprintf "litany: rule %S was renamed to %S@." name
        (Litany.Rule.name r);
      Ok r
  | None ->
      let candidates =
        List.concat_map
          (fun r -> Litany.Rule.name r :: Litany.Rule.renamed_from r)
          Cli_common.catalog
      in
      Error
        (match Litany.Rule.suggest ~candidates name with
        | Some near ->
            Cli_common.refuse "unknown rule %S (did you mean %S?)" name near
        | None -> Cli_common.refuse "unknown rule %S" name)

(* The doc is markdown and is printed as markdown — the maintainer decision:
   rule docs are one markdown source, rendered by odoc on the docs site and
   emitted verbatim here, where markdown is its own terminal rendering. *)
let explain name =
  match resolve name with
  | Error code -> code
  | Ok r ->
      Printf.printf "%s — %s\n" (Litany.Rule.name r) (Litany.Rule.summary r);
      Printf.printf "%s · %s · %s · since %s · fix: %s · %s\n"
        (Litany.Rule.Group.to_string (Litany.Rule.group r))
        (match Litany.Rule.Severity.of_group (Litany.Rule.group r) with
        | Litany.Rule.Severity.Error -> "error"
        | Litany.Rule.Severity.Warning -> "warning")
        (Litany.Rule.Stability.to_string (Litany.Rule.stability r))
        (Litany.Rule.since r) (Cli_common.fix_word r)
        (if Litany.Rule.on_by_default r then "on by default"
         else "off by default");
      print_newline ();
      let doc = Litany.Rule.doc r in
      print_string doc;
      (* The doc contract does not require a trailing newline; the page
         always ends with one. *)
      if doc = "" || doc.[String.length doc - 1] <> '\n' then print_newline ();
      Cli_common.exit_ok

let name_arg =
  let doc = "The rule to explain — a rule name or a former (renamed) name." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"RULE" ~doc)

let man =
  [
    `S Manpage.s_description;
    `P
      "$(iname) prints one rule's full story: a header line (name and \
       summary), its policy line (group, derived severity, stability, \
       introducing release, fix promise, default state), then the rule's \
       complete Markdown documentation — what fires, why it matters, a \
       bad/good pair, and what deliberately does not fire. The text is the \
       same declaration the engine runs and the docs site renders; it cannot \
       drift.";
    `P
      "A former name resolves to the renamed rule with a note on standard \
       error; an unknown name is a refusal with a suggestion, never a silent \
       nothing.";
  ]

let cmd =
  let info =
    Cmd.info "explain" ~doc:"Print one rule's full documentation." ~man
      ~exits:Cli_common.exits
  in
  Cmd.v info Term.(const explain $ name_arg)
