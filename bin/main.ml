(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The composition root: cmdliner group, one [Cli_*] module per subcommand.
   Adapters, loader, engine and renderer are assembled here and only here —
   no [lib/] domain has a process entry. *)

open Cmdliner

(* dune-build-info is not in the lock; the version is pinned at the first
   release. *)
let version = "dev"

let man =
  [
    `S Manpage.s_description;
    `P
      "$(mname) lints OCaml through the compiler's own artifacts: it joins \
       each compilation unit's editable source with its compiled .cmt and runs \
       rules over the typedtree the compiler already built.";
    `P
      "$(b,litany check) runs the built-in rules over every admitted unit \
       ($(b,--list-units) prints the admission listing; $(b,--fix) applies the \
       findings' safe fixes; $(b,--format) picks the report surface). \
       $(b,litany rules) lists the catalog and $(b,litany explain) prints one \
       rule's full documentation — both derive from the declarations the \
       engine runs.";
    `P
      "The build-integration commands: $(b,litany unit) lints one unit inside \
       the build (its argv is the roster), and $(b,litany units) saves the \
       workspace roster as the unit file any build system can produce for \
       $(b,litany check --units). Under dune, $(b,litany check) itself runs as \
       a build action through one user-written rule (see the build-integration \
       manual).";
  ]

(* [`Auto]: pager on a terminal, plain text into a pipe. *)
let default = Term.(ret (const (`Help (`Auto, None))))

(* The public surface is exactly these five (maintainer directive): the
   linter and its build integration, no developer workflows. *)
let tool =
  let info =
    Cmd.info "litany" ~version ~doc:"Lint OCaml from its compiled artifacts."
      ~man ~exits:Cli_common.exits
  in
  Cmd.group ~default info
    [
      Cli_check.cmd; Cli_rules.cmd; Cli_explain.cmd; Cli_unit.cmd; Cli_units.cmd;
    ]

let () = exit (Cli_common.code_of_eval (Cmd.eval' tool))
