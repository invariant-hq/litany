(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Cmdliner

(* The stable exit contract: 0 clean, 1 findings, 2 could-not-run, 3 internal
   error — one table, declared on every command. The codes themselves live
   with the driver ([Litany.Driver] — its results are these codes); this
   module re-exports them beside the cmdliner-facing mapping below. *)
let exit_ok = Litany.Driver.exit_ok
let exit_findings = Litany.Driver.exit_findings
let exit_refusal = Litany.Driver.exit_refusal
let exit_internal = Litany.Driver.exit_internal

let exits =
  [
    Cmd.Exit.info exit_ok ~doc:"the run completed with no findings.";
    Cmd.Exit.info exit_findings ~doc:"the run completed with findings.";
    Cmd.Exit.info exit_refusal
      ~doc:"refusal: adapter error or unusable invocation.";
    Cmd.Exit.info exit_internal ~doc:"internal error: a rule failed.";
  ]

(* cmdliner reserves 124 for command-line parse errors and 125 for
   unexpected exceptions; the former folds into refusal (2) and
   the latter is internal (3). The mapping lives here so the contract
   has one home. *)
let code_of_eval = function
  | 124 -> exit_refusal
  | 125 -> exit_internal
  | code -> code

let refuse = Litany.Driver.refuse

let root =
  let doc = "Run against the workspace rooted at $(docv)." in
  Arg.(value & opt dir "." & info [ "root" ] ~docv:"DIR" ~doc)

(* Any value counts as set and is never parsed — dune's own declared
   contract for "you are running as an action" (the single-writer model's
   ownership signal, doc/dev/design.md, Fixes). *)
let inside_dune () = Sys.getenv_opt "INSIDE_DUNE" <> None

(* The two [Rule.meta]-vocabulary helpers more than one command renders:
   the fix-promise word and name-or-alias resolution
   over the built-in catalog. Refusal wording (did-you-mean, rename
   warnings) stays with each caller — the voices differ, the lookup must
   not. *)
let fix_word r = Litany.Fix.availability_to_string (Litany.Rule.fix r)

(* The built-in catalog, spelled once for the whole CLI:
   every subcommand reads it here, so a custom binary's full-CLI
   copy extends the catalog at exactly one site. *)
let catalog = Litany_rules.all

let find_rule name =
  match
    List.find_opt (fun r -> String.equal (Litany.Rule.name r) name) catalog
  with
  | Some r -> Some (`Exact r)
  | None ->
      Option.map
        (fun r -> `Renamed r)
        (List.find_opt
           (fun r -> List.mem name (Litany.Rule.renamed_from r))
           catalog)
