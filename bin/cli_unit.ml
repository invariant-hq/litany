(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Cmdliner

(* The one-unit engine pass. The argv is the roster: one entry, loaded once
   here and handed to the engine as an already-answered [load] (the engine
   calls it exactly once). The default rule set runs — the in-build lane
   reads no config file: its invocation is a build rule, and a build action
   that silently read mutable configuration would make the same rule mean
   different things on different checkouts. Suppression attributes work as
   everywhere ([catalog] is the full launch catalog). *)
let analyze ~cmt ~source =
  let entry = Litany.Roster.Entry.v ~source ~cmt () in
  let resolver =
    Litany.Naming.Resolver.create
      ~cmi_dirs:[ Filename.dirname cmt; Config.standard_library ]
  in
  (* Build currency for Derived witnesses: inside dune the [%{cmt:...}]
     dependency edge is dune's own freshness guarantee (the loader's
     "inside dune with the artifact among the invoking rule's deps"
     judgment); at a bare shell there is no such evidence. *)
  match
    Litany.Unit.load ~resolver ~build_current:(Cli_common.inside_dune ()) entry
  with
  | Error sk ->
      Error
        (Cli_common.refuse "cannot lint %s: %s" source
           (Litany.Unit.Skip.message sk))
  | Ok u -> (
      let catalog = Cli_common.catalog in
      match Litany.Rule.select ~catalog ~select:[] ~ignore:[] with
      | Error message -> Error (Cli_common.refuse "%s" message)
      | Ok (rules, _) ->
          let roster = Litany.Roster.v [ entry ] in
          let report =
            Litany.Engine.run ~rules ~catalog ~roster ~load:(fun _ -> Ok u) ()
          in
          Ok (u, report))

(* The gate lane: the report page on stdout — the grammar dune's
   diagnostic parser accepts from a failing action (dune parses
   [stdout ^ stderr]), exit 1 on findings. Excerpts come from the bytes
   the unit was admitted on: the loaded unit's own source and interface
   source, the same snapshots the loader digested. Isolated rule failures
   print on the page after the summary (exit 3 dominates). *)
let gate u report =
  let source_of_path path =
    if String.equal path (Litany.Unit.path u) then Some (Litany.Unit.source u)
    else
      Option.bind (Litany.Unit.interface_source u) (fun src ->
          if String.equal (Litany.Source.path src) path then Some src else None)
  in
  Litany.Render.text ~color:(Litany.Driver.color ()) ~source_of_path
    Format.std_formatter report;
  Format.pp_print_flush Format.std_formatter ();
  Litany.Engine.Report.exit_code report

(* Path hygiene at the argv boundary: dune's [%{dep:...}] may expand with a
   [./] prefix, which would otherwise ride verbatim into every finding's
   [File "..."] header. *)
let clean_path p =
  let rec strip p =
    if String.length p > 2 && String.sub p 0 2 = "./" then
      strip (String.sub p 2 (String.length p - 2))
    else p
  in
  strip p

let lint _name cmt source =
  let cmt = clean_path cmt and source = clean_path source in
  match analyze ~cmt ~source with
  | Error code -> code
  | Ok (u, report) -> gate u report

let name_arg =
  let doc =
    "The unit's name — the module the rule lints. Identity only: the artifact \
     and source paths carry the join."
  in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"NAME" ~doc)

let cmt_arg =
  let doc =
    "The unit's compiled .cmt artifact — under dune, $(b,%{cmt:name}), which \
     also makes it a rule dependency so dune's scheduler holds freshness."
  in
  Arg.(required & opt (some string) None & info [ "cmt" ] ~docv:"PATH" ~doc)

let source_arg =
  let doc = "The unit's editable source, the file findings anchor in." in
  Arg.(required & opt (some string) None & info [ "source" ] ~docv:"PATH" ~doc)

let man =
  [
    `S Manpage.s_description;
    `P
      "$(iname) lints exactly one unit: its argv is the roster — no \
       subprocess, no lock, no workspace query. The report page prints on \
       standard output — the same page as $(b,litany check): per finding the \
       compiler-shaped $(b,File)/$(b,Warning) block, then one summary line — \
       and the exit is the gate: 1 when findings exist. Dune parses that \
       grammar from failing actions and serves it over RPC, so a rule running \
       $(iname) surfaces findings in editors as ordinary compiler diagnostics. \
       It is the per-module gate for build systems that wire one rule per \
       unit; under dune the whole-workspace lane is one $(b,litany check) rule \
       (see the build-integration manual).";
    `P
      "The default rule set runs; the workspace $(b,litany) file is not read — \
       a build rule must mean the same thing on every checkout. Attribute \
       suppression ([@litany.allow]/[@litany.expect]) works as everywhere.";
  ]

let cmd =
  let info =
    Cmd.info "unit" ~doc:"Lint one unit inside the build." ~man
      ~exits:Cli_common.exits
  in
  Cmd.v info Term.(const lint $ name_arg $ cmt_arg $ source_arg)
