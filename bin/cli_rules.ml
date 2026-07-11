(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Cmdliner

(* Everything derives from [Rule.meta] — the one-declaration law: this
   table cannot drift from what the engine runs because there is nothing
   else to read. The default-state column is [Litany.Rule.on_by_default],
   the very predicate selection's [default] token resolves through —
   never re-spelled here. *)

let rules () =
  let catalog = Cli_common.catalog in
  let name_w =
    List.fold_left
      (fun w r -> max w (String.length (Litany.Rule.name r)))
      0 catalog
  in
  List.iter
    (fun r ->
      Printf.printf "%-*s  %-11s  %-7s  %-9s  %-3s  %s\n" name_w
        (Litany.Rule.name r)
        (Litany.Rule.Group.to_string (Litany.Rule.group r))
        (Litany.Rule.Stability.to_string (Litany.Rule.stability r))
        (Cli_common.fix_word r)
        (if Litany.Rule.on_by_default r then "on" else "off")
        (Litany.Rule.summary r))
    catalog;
  let n = List.length catalog in
  let on = List.length (List.filter Litany.Rule.on_by_default catalog) in
  let restriction =
    List.length
      (List.filter
         (fun r -> Litany.Rule.group r = Litany.Rule.Restriction)
         catalog)
  in
  let nursery =
    List.length
      (List.filter
         (fun r -> Litany.Rule.stability r = Litany.Rule.Stability.Nursery)
         catalog)
  in
  (* The census names the tier's one distinguishing fact — outside [all],
     cherry-picked — so a reader without the manual can see it from the
     table alone. *)
  Printf.printf
    "%d rules · %d on by default (stable correctness, suspicious, perf) · %d \
     restriction (cherry-picked; outside all) · %d nursery\n"
    n on restriction nursery;
  Cli_common.exit_ok

let man =
  [
    `S Manpage.s_description;
    `P
      "$(iname) lists the built-in catalog, one rule per line: name, group \
       (correctness, suspicious, perf, style, pedantic, restriction), \
       stability tier (stable or nursery), fix promise (never, sometimes, \
       always), whether the rule is on by default, and its one-line summary. \
       The table derives from the same declarations the engine runs, so it \
       cannot drift.";
    `P
      "Group is policy: correctness findings render as errors, everything else \
       as warnings; stable correctness, suspicious, and perf rules are the \
       default set. Nursery rules are off under every group and set until \
       graduated — select them with $(b,--select nursery) or by exact name. \
       Restriction rules are house policies over legitimate code — outside \
       $(b,all), cherry-picked by exact name. $(b,litany explain) $(i,RULE) \
       prints one rule's full story.";
  ]

let cmd =
  let info =
    Cmd.info "rules" ~doc:"List the rule catalog." ~man ~exits:Cli_common.exits
  in
  Cmd.v info Term.(const rules $ const ())
