(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-exit-in-library" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never ~summary:"exit referenced in library code"
    ~doc:
      {|`Stdlib.exit` terminates the process, runs the `at_exit` handlers,
and denies every caller above the library a say. Inside library code
that is a policy usurpation and a classic source of test hostility:
the test runner dies with the library. Executables own their exit;
libraries raise.

    (* bad *)  let load path = if bad path then exit 1 else parse path
    (* good *) let load path = if bad path then invalid_arg "load" else parse path

Fires once per resolved reference to `Stdlib.exit` — aliasing an exit
is an exit — and only in units whose roster kind is `Library`; a unit
whose roster carries no kind is deliberately silent: a metadata-gated
rule degrades to silence, never to guessing. `raise Exit` constructs
the `Stdlib.Exit` exception, not a reference to `exit`; `at_exit` is a
different declaration; a shadowing local `exit` resolves to a local
declaration — none fire. A library's deliberate `fatal`/`usage` helper
is what `[@litany.allow "suspicious-exit-in-library: ..."]` with a
reason documents. No fix: the replacement error path is a design
decision.|}
    ~kind_gated:true ()

let exit_ident = Pat.(ident "Stdlib.exit")

let rule =
  Rule.expr meta @@ fun u e ->
  match Unit.kind u with
  | Some Unit.Library -> (
      match Pat.run exit_ident u e () with
      | Some () ->
          [
            Finding.v ~loc:e.exp_loc
              "exit in library code terminates the whole process";
          ]
      | None -> [])
  | Some Unit.Executable | Some Unit.Test | None -> []
