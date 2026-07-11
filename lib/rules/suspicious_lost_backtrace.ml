(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-lost-backtrace" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"work between catching and re-raising can overwrite the backtrace"
    ~doc:
      {|`raise e` on a handler-bound exception compiles to a backtrace-
preserving reraise — but what it preserves is the *current* per-domain
backtrace buffer, and any raise that happens in between, even one that
is caught, rewrites that buffer. A handler that logs, unlocks, or cleans
up before re-raising can therefore report the wrong backtrace.

    (* bad *)  try f () with e -> log_error e; raise e
    (* good *) try f () with
               | e ->
                   let bt = Printexc.get_raw_backtrace () in
                   log_error e;
                   Printexc.raise_with_backtrace e bt

Fires on `try` handlers and `match … with exception` arms that bind
their exception to a bare variable without a guard, do at least one
statement of work (a sequence or `let` spine), and end in `raise` of
exactly that variable; the finding anchors at the final reraise. The
bare `try f () with e -> raise e` already preserves the backtrace and
does not fire; neither do guards, `raise_notrace` (explicit discard),
`Printexc.raise_with_backtrace` (the remedy), re-raises of a different
or wrapped exception, or handlers matching a specific exception pattern.
No fix: the rewrite introduces a binding and reorders the handler.|}
    ()

let message =
  "work before this reraise can overwrite the backtrace it preserves; capture \
   Printexc.get_raw_backtrace first and finish with \
   Printexc.raise_with_backtrace"

(* The two hosts, each surfacing its case list: [try_] tolerates effect
   cases, [match_] refuses effect-carrying matches (the view contracts). *)
let try_handlers = Pat.(try_ drop __)
let match_arms = Pat.(match_ drop __)

(* A handler case binding its exception to a bare variable, guard-less. *)
let handler_case = Pat.(case pvar none __)
let exception_arm = Pat.(case (pexception pvar) none __)

(* The statement spine: sequences (keep the right leg) and lets (keep
   the body). [let P = E in BODY] with a constructor pattern — [let () =
   restore () in …] especially — typechecks as a one-case match, and a
   guard-less single value case cannot select: it is a let in compiled
   form and belongs to the spine too (pinned in the fixture). *)
let let_match = Pat.(match_ drop (case (pvalue drop) none __ ^:: nil))
let spine_step = Pat.(seq_ drop __ ||| let_body __ ||| let_match)

(* The residue must be exactly [raise e] on the bound variable. *)
let reraise = Pat.(apply (ident "Stdlib.raise") (var ^:: nil))

let check_case u (id, rhs) =
  let rec strip n e =
    match Pat.run spine_step u e Fun.id with
    | Some e' -> strip (n + 1) e'
    | None -> (n, e)
  in
  let steps, residue = strip 0 rhs in
  if steps = 0 then None
  else
    match Pat.run reraise u residue Fun.id with
    | Some p when Path.same p (Path.Pident id) ->
        Some (Finding.v ~loc:residue.Typedtree.exp_loc message)
    | Some _ | None -> None

let rule =
  Rule.expr meta @@ fun u e ->
  let per_case p cs =
    List.filter_map
      (fun c ->
        Option.bind (Pat.run p u c (fun id rhs -> (id, rhs))) (check_case u))
      cs
  in
  match Pat.run try_handlers u e Fun.id with
  | Some cs -> per_case handler_case cs
  | None -> (
      match Pat.run match_arms u e Fun.id with
      | Some cs -> per_case exception_arm cs
      | None -> [])
