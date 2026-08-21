(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Cmdliner

(* The one injection point of the wiring: the selected rule set —
   [--select]/[--ignore] (or the config file's select/extend/ignore, flags
   winning per [Cli_config.tokens]) resolved over the configured catalog by
   [Litany.Rule.select]. An unknown token is a refusal with a did-you-mean; a
   tombstone alias resolves with a rename warning on stderr. The full catalog
   still reaches the engine as its suppression [catalog], so an allow/expect
   naming an unselected rule stays silently inert instead of reading as
   unknown. *)
let selection ~catalog ~select ~ignore =
  (* The audit names print as rule names in output, so a user will paste
     them into --ignore; "unknown" would be the one wrong word. They are
     engine hygiene, not selection vocabulary — the config file's per-path
     [all] is the one instrument that covers them (Cli_config). *)
  match
    List.find_opt
      (fun tok -> List.mem tok Litany.Engine.audit_rules)
      (select @ ignore)
  with
  | Some tok ->
      Error
        (Cli_common.refuse "%S is engine-owned hygiene, not a selectable rule"
           tok)
  | None -> (
      match Litany.Rule.select ~catalog ~select ~ignore with
      | Error message -> Error (Cli_common.refuse "%s" message)
      | Ok (rules, warnings) ->
          List.iter (fun w -> Format.eprintf "litany: %s@." w) warnings;
          Ok rules)

(* {1 The INSIDE_DUNE vantages}

   INSIDE_DUNE says "a dune spawned this process"; it does not say from
   where, and the two vantages behave nothing alike. The discriminator is
   where cwd actually is — never the variable's value, never a guess
   (probed 2026-08-21, dune 3.21 nightly, scratch consumer project):

   - a rule action runs with cwd inside its build context —
     [<ws>/_build/<ctx>[/<dir>]] — while the project lock is held;
   - under [(sandbox always)] the action runs in a staged mirror,
     [<ws>/_build/.sandbox/<hash>/<ctx>[/<dir>]] — writes land in the
     copy and are discarded;
   - a [dune exec] child keeps the caller's cwd — the source workspace,
     not under any [_build] — and the lock is free while it runs.

   The LAST [_build] component decides: a workspace can itself sit under
   some outer build tree (litany's own cram sandboxes do), and the
   innermost [_build] is the one whose dune spawned us. [source_root] is
   absolute (the segments before that [_build]); [context] is the
   source-root-relative context directory, [.sandbox] hash included at
   the sandboxed vantage. *)
type vantage =
  | Shell  (** Not inside dune. *)
  | Exec  (** INSIDE_DUNE set, cwd not under a [_build]: a [dune exec] child. *)
  | Action of { source_root : string; context : string; subdir : string }
      (** A rule action: cwd inside [<source_root>/<context>/<subdir>]. [subdir]
          is the stanza directory relative to the context root ([""] for a root
          rule) — the report is scoped to it, so what the rule reports is
          exactly what its [(alias_rec ...)] deps keep fresh. *)
  | Sandboxed of {
      source_root : string;
      context : string;
      sandbox : string;
      subdir : string;
    }
      (** A sandboxed rule action — the dune lang 3.23 norm (every user rule is
          sandboxed there). [context] is the {e real} enclosing build context
          ([_build/<ctx>], root-relative) the staged mirror copies: the sandbox
          is not a read boundary and its alias deps stage zero artifact files,
          so the walk reads the real context against the real sources — the
          [(alias_rec check)] deps edge built them, exactly the unsandboxed
          lane's currency. [sandbox] is the staged mirror of that context root
          ([_build/.sandbox/<hash>/<ctx>], root-relative) — where the [--fix]
          lane writes [<source path>.corrected] files for dune's
          corrections/promotion flow instead of ever writing a source. *)

let vantage () =
  if not (Cli_common.inside_dune ()) then Shell
  else
    let segs = String.split_on_char '/' (Sys.getcwd ()) in
    let rec last_build i best = function
      | [] -> best
      | seg :: rest ->
          last_build (i + 1)
            (if String.equal seg "_build" then Some i else best)
            rest
    in
    match last_build 0 None segs with
    | None -> Exec
    | Some at -> (
        let source_root =
          match String.concat "/" (List.filteri (fun i _ -> i < at) segs) with
          | "" -> "/"
          | p -> p
        in
        match List.filteri (fun i _ -> i > at) segs with
        | ".sandbox" :: hash :: ctx :: rest when ctx <> "" ->
            Sandboxed
              {
                source_root;
                context = "_build/" ^ ctx;
                sandbox = "_build/.sandbox/" ^ hash ^ "/" ^ ctx;
                subdir = String.concat "/" rest;
              }
        | ctx :: rest when ctx <> "" && ctx <> ".sandbox" ->
            Action
              {
                source_root;
                context = "_build/" ^ ctx;
                subdir = String.concat "/" rest;
              }
        | _ -> Exec)

(* The roster and whether this run may trust the build system's editable→pp
   tracking ([build_current] in [Litany.Unit.load]). A refusal is printed by
   [Cli_common.refuse] and carried out as its exit code. [in_action_ctx] is
   the in-action lane's triple — the real context directory
   (root-relative), the stanza subdir, and, at the sandboxed vantage, the
   corrections mirror (the driver's fix sink; the roster never needs it) —
   [None] at every other vantage or when an explicit lane flag chose the
   roster source. *)
let roster_of_flags ~progress ~in_action_ctx ~root ~cmt_root ~units ~build
    ~trust_build =
  match (cmt_root, units) with
  | Some _, Some _ ->
      Error
        (Cli_common.refuse
           "--cmt-root and --units both name a roster source; pass one")
  | None, Some file -> (
      (* The unit-file lane: any build system's roster, no dune spawned, no
         build run — legitimate beside a watch server (the lock arbitrates
         dune-vs-dune, never litany's reads). [build_current] holds only
         under --trust-build: without it litany has no evidence of the
         producer's build, so Derived witnesses skip honestly. *)
      match In_channel.with_open_bin file In_channel.input_all with
      | exception Sys_error msg -> Error (Cli_common.refuse "%s" msg)
      | bytes -> (
          match Litany.Adapter.Unit_file.decode bytes with
          | Ok roster -> Ok (roster, trust_build)
          | Error e ->
              Error
                (Cli_common.refuse "%s: %a" file
                   Litany.Adapter.Unit_file.pp_error e)))
  | Some cmt_root, None -> (
      match Litany.Adapter.Walk.roster ~cmt_root ~source_root:root with
      | Ok roster -> Ok (roster, trust_build)
      | Error e -> Error (Cli_common.refuse "%a" Litany.Adapter.Walk.pp_error e)
      )
  | None, None -> (
      match in_action_ctx with
      | Some (context, subdir, _) -> (
          (* The in-action lane: litany check runs as the action of a
             user-written rule whose deps ([(alias_rec check)]) already
             built the artifacts — no dune subprocess ever (spawning dune
             inside dune deadlocks on the lock the parent holds). The
             caller rebased cwd onto the vantage's source root, so the
             walk covers the enclosing context and findings anchor at
             real source-tree paths. Build currency is dune's own
             dependency edge, exactly the [litany unit] judgment: the
             invoking rule's deps staged these artifacts.

             [context] is always the real build context — at the sandboxed
             vantage too (the 3.23 norm): the sandbox is not a read
             boundary, and its alias deps stage zero artifact files
             (probed), so the sandbox mirror is never worth walking — the
             walk reads the real artifacts the deps edge just built,
             against the real sources they mirror.

             An empty in-action roster is a refusal, never a silent green
             (Law 6: silence must stay distinguishable from cleanliness):
             a context that is missing or holds no artifacts means the
             rule's deps built nothing — a missing
             [(deps (alias_rec check))] line — and the refusal names that
             remedy. *)
          let empty_context () =
            Cli_common.refuse
              "the build context %s holds no compiled artifacts; give the rule \
               (deps (alias_rec check)) so the tree is built before litany \
               runs"
              context
          in
          match
            Litany.Adapter.Walk.roster ~cmt_root:context ~source_root:root
          with
          | Error (Litany.Adapter.Walk.Root_missing _) ->
              Error (empty_context ())
          | Ok roster ->
              let roster =
                if String.equal subdir "" then roster
                else begin
                  (* Report scope = deps scope: a rule in a subdirectory's
                     dune keeps only its own subtree fresh via
                     [(alias_rec ...)], so the report covers exactly that
                     subtree — anything wider would depend on unrelated
                     build history (verified: a stale sibling directory
                     otherwise reads green or bleeds findings). *)
                  let prefix = subdir ^ "/" in
                  let entries =
                    List.filter
                      (fun e ->
                        let src = Litany.Roster.Entry.source e in
                        String.length src > String.length prefix
                        && String.equal
                             (String.sub src 0 (String.length prefix))
                             prefix)
                      (Litany.Roster.entries roster)
                  in
                  Litany.Roster.v
                    ~complete:(Litany.Roster.complete roster)
                    ~cmi_dirs:(Litany.Roster.cmi_dirs roster)
                    entries
                end
              in
              if Litany.Roster.entries roster = [] then Error (empty_context ())
              else Ok (roster, true))
      | None -> (
          (* The dune-exec cell, decided, not accidental:
             under INSIDE_DUNE at the shell vantage the read-only dune
             lane still works. The build step is skipped — driving a
             build from inside dune is the actual hazard — and [dune
             describe] runs with the lock arbitrating dune-vs-dune, never
             litany's reads: at [dune exec] the lock is free (dune
             releases it while the child runs) and describe answers with
             findings; when another dune holds the root's lock, describe
             fails fast into the [Lock_held] refusal (probed: ~20 ms,
             dune errors naming the pid rather than blocking).
             [build_current] holds only when this run executed the build,
             or under --trust-build — otherwise there is no freshness
             evidence and Derived witnesses skip honestly. [--fix] never
             reaches here (refused up front at the exec vantage). *)
          let inside = Cli_common.inside_dune () in
          let build = build && not inside in
          match Litany.Adapter.Dune.roster ~progress ~build ~root () with
          | Ok roster -> Ok (roster, build || trust_build)
          | Error e ->
              Error (Cli_common.refuse "%a" Litany.Adapter.Dune.pp_error e)))

let check root cmt_root units no_build trust_build list_units select ignore fix
    unsafe format_flag jobs_flag cache_dir no_cache cache_stats explain_withheld
    no_progress =
  if match jobs_flag with Some n -> n < 1 | None -> false then
    Cli_common.refuse "--jobs must be at least 1"
  else
    let vantage = vantage () in
    match (fix, vantage) with
    | true, Sandboxed _ when cmt_root <> None || units <> None ->
        (* The sandboxed vantage's --fix is the corrections lane — no
           source is ever written; fixes become [.corrected] files dune
           diffs against the sources and applies on [dune promote]. That
           pairing works by the context mirror: corrected paths must be
           the auto roster's context-relative source paths. An explicit
           roster (--cmt-root/--units) keeps its own cwd and its own
           paths precisely because they were authored against the
           action's directory, so litany cannot mirror its fixes into
           corrections — and a direct write would land in the staged copy
           and be discarded with the sandbox. Read-only check still works
           here. *)
        Cli_common.refuse
          "refusing --fix: this action is sandboxed and the roster is explicit \
           (--cmt-root/--units), so fixes cannot ride dune's corrections — \
           litany mirrors only the context it walks itself; drop the roster \
           flag (with (corrections produce) in the rule, dune shows fixes as \
           diffs and dune promote applies), or run litany check --fix outside \
           dune"
    | true, Action _ ->
        (* Inside dune, litany never writes a source at any dune version
           (maintainer decision, 2026-08-21: the single-writer principle
           holds universally in-dune). The one in-dune fix transport is
           dune's corrections/promotion flow, and it exists only at
           (lang dune 3.23) — where every user rule is sandboxed, so this
           unsandboxed action vantage means an older dune language. Refuse
           toward the two lanes that do fix: the 3.23 corrections stanza,
           or the terminal. Read-only check at this vantage is untouched. *)
        Cli_common.refuse
          "refusing --fix: in-dune fixing requires (lang dune 3.23) and \
           (corrections produce) on the rule — dune then shows fixes as diffs \
           and dune promote applies them; on older dune, run litany check \
           --fix from the terminal instead"
    | true, Exec ->
        (* The exec vantage keeps its read-only posture: INSIDE_DUNE says
           a dune spawned us, and at [dune exec] that dune re-takes the
           tree the moment the child exits (a watch parent rebuilds over
           the writes). The installed binary at the shell is the writing
           lane. *)
        Cli_common.refuse
          "refusing --fix: this process runs inside dune (INSIDE_DUNE is set) \
           via `dune exec` or `dune tools exec`. Run the installed binary \
           instead (litany check --fix, e.g. via `opam exec -- litany` or your \
           PATH), or run litany check --fix as a build rule's action (see the \
           build-integration manual)."
    | _ -> (
        (* The in-action rebase, before anything reads the tree: cwd moves
       from the build context to the vantage's source root, so the config
       file, the cache's workspace key, the artifact walk, and every
       finding path resolve exactly as a terminal run's would. No in-dune
       vantage ever writes a source: the sandboxed vantage's [--fix]
       proposes dune corrections in the sandbox mirror (carried as the
       triple's third component), and every other in-dune [--fix] refused
       above. The rebase is the auto lane's alone: an explicit lane flag
       ([--units]/[--cmt-root]) keeps its own roster AND its own cwd —
       its relative arguments were authored against the invoking action's
       directory, and rebasing them out from under it would repoint the
       run at a different tree (litany's own cram sandboxes run exactly
       such invocations). *)
        let rebase source_root ctx =
          match Sys.chdir source_root with
          | () -> Ok (Some ctx)
          | exception Sys_error msg ->
              Error
                (Cli_common.refuse "cannot enter the workspace root %s: %s"
                   source_root msg)
        in
        match
          match vantage with
          | Action { source_root; context; subdir }
            when cmt_root = None && units = None ->
              rebase source_root (context, subdir, None)
          | Sandboxed { source_root; context; sandbox; subdir }
            when cmt_root = None && units = None ->
              rebase source_root (context, subdir, Some sandbox)
          | Action _ | Sandboxed _ | Shell | Exec -> Ok None
        with
        | Error code -> code
        | Ok in_action_ctx -> (
            match
              (* Explicit machine formats refuse the two text-surface modes; the
                 GITHUB_ACTIONS auto-selection is a default, not a mandate, and
                 yields to them silently. Inside a dune action nothing
                 changes: the text page is the grammar dune's diagnostic
                 parser accepts from a failing action, so the page a
                 terminal shows is the page dune serves to editors. *)
              match format_flag with
              | Some ((Litany.Driver.Json | Litany.Driver.Github) as f)
                when fix || list_units || explain_withheld ->
                  Error
                    (Cli_common.refuse
                       "--format %s renders the report page only; %s speaks \
                        the text surface"
                       (match f with
                       | Litany.Driver.Json -> "json"
                       | Litany.Driver.Github -> "github"
                       | Litany.Driver.Text -> assert false)
                       (if fix then "--fix"
                        else if list_units then "--list-units"
                        else "--explain-withheld"))
              | Some f -> Ok f
              | None ->
                  if
                    Sys.getenv_opt "GITHUB_ACTIONS" <> None
                    && (not fix) && not list_units
                  then Ok Litany.Driver.Github
                  else Ok Litany.Driver.Text
            with
            | Error code -> code
            | Ok format -> (
                match Cli_config.load ~root with
                | Error code -> code
                | Ok cfg -> (
                    match Cli_config.configured_catalog cfg with
                    | Error code -> code
                    | Ok catalog -> (
                        (* The config's [closed-world] bit reaches the two
                   cross-module rules here: their open-world defaults are
                   swapped for the closed variants before selection, so
                   tokens, keep, and the engine all see the effective
                   rules. The two names are the catalog's own; a
                   third-party catalog wires its own policy. *)
                        let catalog =
                          if not (Cli_config.closed_world cfg) then catalog
                          else
                            List.map
                              (fun r ->
                                match Litany.Rule.name r with
                                | "unused-export" ->
                                    Litany_rules.Unused_export.v
                                      ~closed_world:true
                                | "dead-code" ->
                                    Litany_rules.Dead_code.v ~closed_world:true
                                | _ -> r)
                              catalog
                        in
                        let eff_select, eff_ignore =
                          Cli_config.tokens cfg ~cli_select:(List.concat select)
                            ~cli_ignore:(List.concat ignore)
                        in
                        match
                          selection ~catalog ~select:eff_select
                            ~ignore:eff_ignore
                        with
                        | Error code -> code
                        | Ok rules -> (
                            (* The configured-but-silent trap, warned on the same
                       channel as selection's rename warnings: a
                       [(rule X ...)] form whose rule the run does not
                       select validates and then does nothing — loud,
                       never a refusal (the options may serve another
                       lane's selection). *)
                            List.iter
                              (fun n ->
                                if
                                  not
                                    (List.exists
                                       (fun r ->
                                         String.equal (Litany.Rule.name r) n)
                                       rules)
                                then
                                  Format.eprintf
                                    "litany: rule %S is configured but not \
                                     selected@."
                                    n)
                              (Cli_config.configured_rule_names cfg);
                            (* The mirror trap: a rule
                       that is inert until configured
                       ([Litany.Rule.requires_options]), selected with no
                       [(rule X ...)] form, runs and reports nothing —
                       equally invisible, and likelier during adoption (the
                       user enables first, means to add the policy next).
                       Same channel, a warning, never a refusal. *)
                            List.iter
                              (fun r ->
                                let n = Litany.Rule.name r in
                                if
                                  Litany.Rule.requires_options r
                                  && not
                                       (List.mem n
                                          (Cli_config.configured_rule_names cfg))
                                then
                                  Format.eprintf
                                    "litany: rule %S is selected but not \
                                     configured; it reports nothing without a \
                                     (rule %s ...) form@."
                                    n n)
                              rules;
                            let keep = Cli_config.keep cfg ~catalog in
                            (* The run's meter, from here to the last pass: the
                       adapter names its stretches on it, the driver counts
                       units into it, and it draws nothing unless standard
                       error is a terminal — so a pipe, a cram sandbox, and a
                       CI log see exactly the bytes they saw before. *)
                            let progress =
                              Litany.Progress.v ~enabled:(not no_progress)
                                ~jobs:(Option.value jobs_flag ~default:1)
                            in
                            match
                              roster_of_flags ~progress ~in_action_ctx ~root
                                ~cmt_root ~units ~build:(not no_build)
                                ~trust_build
                            with
                            | Error code -> code
                            | Ok (roster, build_current) ->
                                if list_units then begin
                                  Litany.Driver.listing roster ~build_current;
                                  Cli_common.exit_ok
                                end
                                else begin
                                  let cache =
                                    Litany.Driver.Result_cache.setup ~cache_dir
                                      ~no_cache ~root ~rules
                                  in
                                  (* The build capability: how litany re-runs this
                             roster's build, when it can — the shell dune
                             lane only (the design doc's lane table; the
                             in-action lane never spawns dune, so it is a
                             one-pass lane whose convergence spans dune's
                             own rebuilds). The driver converges iff it
                             holds one; the worker-count decision
                             (defaulting, the --fix serial clamp) is the
                             driver's too. *)
                                  let rebuild =
                                    if
                                      cmt_root = None && units = None
                                      && (not no_build)
                                      && not (Cli_common.inside_dune ())
                                    then
                                      Some
                                        (fun () ->
                                          Litany.Adapter.Dune.roster ~progress
                                            ~build:true ~root ())
                                    else None
                                  in
                                  let code =
                                    Litany.Driver.run_check ~progress ~rebuild
                                      ~format ~jobs:jobs_flag ~cache roster
                                      ~build_current ~rules ~catalog ~keep
                                      ~fix:
                                        (if fix then
                                           Some
                                             {
                                               Litany.Driver.unsafe;
                                               corrections =
                                                 (match in_action_ctx with
                                                 | Some (_, _, c) -> c
                                                 | None -> None);
                                             }
                                         else None)
                                      ~explain_withheld
                                  in
                                  Option.iter
                                    (fun c ->
                                      Litany.Driver.Result_cache.finish c
                                        ~stats:cache_stats)
                                    cache;
                                  code
                                end))))))

let cmt_root =
  let doc =
    "Walk $(docv) for .cmt artifacts instead of asking dune; sources are \
     paired under the workspace root. The adapter of last resort: no ownership \
     metadata, local rules only."
  in
  Arg.(value & opt (some string) None & info [ "cmt-root" ] ~docv:"DIR" ~doc)

let units_arg =
  let doc =
    "Take the roster from unit file $(docv) — written by $(b,litany units \
     --save), or emitted by any build system (csexp; see the format's \
     documentation). No dune is spawned and no build runs, so the lane works \
     beside a running watch server; per-unit witnesses still gate every join, \
     and stale entries surface as skips. Under $(b,--fix) exactly one pass \
     runs — rebuild and re-run to converge."
  in
  Arg.(value & opt (some string) None & info [ "units" ] ~docv:"FILE" ~doc)

let no_build =
  let doc =
    "Do not run $(b,dune build @check) first; stale artifacts surface as skips."
  in
  Arg.(value & flag & info [ "no-build" ] ~doc)

let trust_build_arg =
  let doc =
    "Assert that the build system's editable-to-preprocessed tracking is \
     current, so units the compiler read from a built pp file join under their \
     Derived witness instead of skipping derived-needs-build. For rosters \
     whose build litany did not run itself ($(b,--units), $(b,--cmt-root), \
     $(b,--no-build)); per-unit digest witnesses still gate every join, so a \
     genuinely stale unit stays a skip."
  in
  Arg.(value & flag & info [ "trust-build" ] ~doc)

let list_units =
  let doc =
    "List the units the run would admit and the skips that keep candidates \
     out, instead of running rules."
  in
  Arg.(value & flag & info [ "list-units" ] ~doc)

let select_arg =
  let doc =
    "Select the rules to run: rule names, group names (correctness, \
     suspicious, perf, style, pedantic, restriction), the nursery stability \
     tier, or the sets all and default. $(b,all) is every $(i,stable) rule \
     outside the restriction group — not the full catalog: nursery rules stay \
     off under every group and set except $(b,nursery), and restriction rules \
     are house policies meant to be cherry-picked by name (a bare \
     $(b,restriction) warns), so the full-catalog audit is $(b,--select \
     all,restriction,nursery). The summary line's leading count says how many \
     rules a run selected. Repeatable, comma-separated. Precedence against \
     $(b,--ignore) is specificity: an exact rule name outranks a group or \
     tier, which outranks all/default; at equal specificity $(b,--ignore) \
     wins. A given $(b,--select) replaces the config file's select and extend \
     lists together; an absent flag leaves them in force. Default: \
     $(b,default) — the stable correctness, suspicious, and perf rules."
  in
  Arg.(value & opt_all (list string) [] & info [ "select" ] ~docv:"NAMES" ~doc)

let ignore_arg =
  let doc =
    "Drop rules from the selection; same vocabulary and repeatability as \
     $(b,--select). An unknown name is a refusal, never a silent no-op. A \
     given $(b,--ignore) replaces the config file's ignore list; an absent \
     flag leaves it in force."
  in
  Arg.(value & opt_all (list string) [] & info [ "ignore" ] ~docv:"NAMES" ~doc)

let fix_arg =
  let doc =
    "Apply the findings' safe fixes after reporting: each file's digest is \
     re-checked against the admission-time witness before writing, the result \
     must reparse, and writes are atomic. Under the dune adapter convergence \
     spans builds — litany rebuilds, re-joins, and re-lints until clean, \
     applying deferred conflict losers, capped at 3 passes. Under \
     $(b,--cmt-root) or $(b,--no-build) exactly one pass runs — rebuild and \
     re-run to converge. Inside a dune action litany never writes a source: \
     the one in-dune fix transport is dune's corrections — $(b,(lang dune \
     3.23)) with $(b,(corrections produce)) on the rule — where one pass runs \
     per build, no source is written, the build fails showing each fix as a \
     diff, and $(b,dune promote) applies them (without the field dune discards \
     corrections silently, so the run's note always names it); at any other \
     in-dune vantage $(b,--fix) refuses toward that stanza or the terminal. \
     Findings hidden by [@litany.allow]/[@litany.expect] are never fixed."
  in
  Arg.(value & flag & info [ "fix" ] ~doc)

let unsafe_arg =
  let doc =
    "With $(b,--fix): also apply fixes marked unsafe — each may change \
     behavior, and its title says how. Consent is per-invocation and global; \
     $(b,--select)/$(b,--ignore) scope which rules run."
  in
  Arg.(value & flag & info [ "unsafe" ] ~doc)

let format_arg =
  let doc =
    "Report format: $(b,text) (the default — the report page on standard \
     output: per finding the compiler-shaped $(b,File)/$(b,Warning) block with \
     the quoted line and carets and its fix line, then one summary line; the \
     same page dune parses into diagnostics from a failing action, so findings \
     reach editors over dune RPC with nothing to configure), $(b,json) (JSON \
     Lines: one finding object per line, one summary trailer, on standard \
     output), or $(b,github) (workflow annotations — auto-selected when \
     $(b,GITHUB_ACTIONS) is set and no $(b,--format) is given; an explicit \
     $(b,--format) always wins). The two machine formats render the report \
     page only and refuse $(b,--fix) and $(b,--list-units); anything else the \
     run prints (build forwarding, rename warnings) keeps its own channel."
  in
  Arg.(
    value
    & opt
        (some
           (enum
              [
                ("text", Litany.Driver.Text);
                ("json", Litany.Driver.Json);
                ("github", Litany.Driver.Github);
              ]))
        None
    & info [ "format" ] ~docv:"FMT" ~doc)

let jobs_arg =
  let doc =
    "Analyze units with $(docv) worker processes (default: the machine's core \
     count). Results are merged into one report whose bytes are identical \
     across every worker count — parallelism is never observable in the \
     output. A crashed worker loses only its own shard: those units are \
     counted skips, everything else lands, and the exit code follows the \
     normal law. $(b,--fix) runs single-process this release."
  in
  Arg.(value & opt (some int) None & info [ "j"; "jobs" ] ~docv:"N" ~doc)

let cache_dir_arg =
  let doc =
    "Store per-unit results under $(docv) instead of the default location \
     ($(b,LITANY_CACHE_DIR), else $(b,XDG_CACHE_HOME)/litany, else \
     $(b,HOME)/.cache/litany). The cache is content-addressed over cmt, \
     source, configuration, selected rules, and the litany binary itself, so a \
     hit is byte-identical to recomputation by construction; it is advisory — \
     any cache failure only costs recomputation."
  in
  Arg.(value & opt (some string) None & info [ "cache-dir" ] ~docv:"DIR" ~doc)

let no_cache_arg =
  let doc = "Do not read or write the per-unit result cache." in
  Arg.(value & flag & info [ "no-cache" ] ~doc)

let cache_stats_arg =
  let doc =
    "Print one cache summary line (hits, misses, stores, evictions) on \
     standard error at the end of the run. The report itself never varies with \
     cache state."
  in
  Arg.(value & flag & info [ "cache-stats" ] ~doc)

let man =
  [
    `S Manpage.s_description;
    `P
      "$(iname) joins each candidate unit's editable source with its compiled \
       artifact, runs the selected rules over every admitted unit, and prints \
       the findings with one summary line. A candidate that cannot be admitted \
       is a counted skip, never a stale finding.";
    `P
      "By default the workspace's dune supplies the roster ($(b,dune build \
       @check), then one $(b,dune describe)). $(b,--cmt-root) walks a \
       directory of prebuilt artifacts instead, and $(b,--units) consumes a \
       unit file from $(b,litany units --save) or any other build system — no \
       dune spawned, no build run. $(b,--list-units) prints the admission \
       listing without running rules. $(b,--format) selects the report surface \
       (text, json, github).";
    `P
      "Run as a dune action — one user-written rule, typically $(b,(rule \
       (alias lint) (deps (alias_rec check)) (action (run litany check)))) — \
       no dune is spawned: litany detects the action vantage, walks the \
       enclosing build context for the artifacts the rule's deps just built, \
       and pairs them with the real source tree, so findings anchor at source \
       paths and — the report page being the grammar dune's diagnostic parser \
       accepts — land as dune diagnostics. With $(b,(corrections produce)) in \
       the rule and $(b,--fix) in the action — $(b,(lang dune 3.23)); litany \
       never writes a source from inside dune — fixes become dune corrections: \
       the build fails showing each as a diff and $(b,dune promote) applies \
       them. See the build-integration manual.";
    `P
      "Configuration, when wanted, is one $(b,litany) file at the workspace \
       root — closed schema, positioned errors, exit 2 on any mistake. Its \
       lint block feeds the same selection as $(b,--select)/$(b,--ignore) \
       (flags win); its per-path blocks select $(i,reports) away by path \
       (units are still analyzed); its rule blocks pass options to rules that \
       declare them.";
    `P
      "$(b,--select) and $(b,--ignore) choose the rules before analysis — an \
       unselected rule is not run at all. To silence one finding, annotate the \
       code instead: [@litany.allow \"rule-name: reason\"] on the construct \
       (floating [@@@litany.allow ...] covers the rest of the file), and \
       [@litany.expect ...] to also require the finding. A directive that \
       hides nothing while its rule ran is itself a finding (unused-allow, \
       unfulfilled-expect).";
  ]

let explain_withheld_arg =
  let doc =
    "After the report, print which skip blocked which cross-module (project) \
     rule — one line per (rule, blocking unit) pair, with the skip reason — or \
     that nothing was withheld. Project rules run only when every roster unit \
     joined; a single skip withholds them all. Text surface only."
  in
  Arg.(value & flag & info [ "explain-withheld" ] ~doc)

let no_progress_arg =
  let doc =
    "Do not draw the progress line. The line is standard error's, rewritten in \
     place, and already silent unless standard error is a terminal — so this \
     is for a terminal session that wants none (a recorded demo, a tool \
     reading litany's stderr from a pty). The environment variable \
     $(b,LITANY_NO_PROGRESS) does the same."
  in
  Arg.(value & flag & info [ "no-progress" ] ~doc)

let cmd =
  let info =
    Cmd.info "check" ~doc:"Run the rules over every admitted unit." ~man
      ~exits:Cli_common.exits
  in
  Cmd.v info
    Term.(
      const check $ Cli_common.root $ cmt_root $ units_arg $ no_build
      $ trust_build_arg $ list_units $ select_arg $ ignore_arg $ fix_arg
      $ unsafe_arg $ format_arg $ jobs_arg $ cache_dir_arg $ no_cache_arg
      $ cache_stats_arg $ explain_withheld_arg $ no_progress_arg)
