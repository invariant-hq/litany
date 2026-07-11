(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

module Report = struct
  type outcome = Linted | Facts_only | Skipped of Unit.Skip.t
  type failure = { rule : string; unit_path : string; message : string }

  type project_block =
    | Not_capable
    | Incomplete of (string * Unit.Skip.t) list
    | Ambiguous of (string * string list) list
    | Collect_failed of string list

  type degradation = Offsets | Resolution of { cmi : string; reason : string }

  (* One admitted unit's whole contribution to a report — the payload record,
     promoted to the report's substrate. [t] stores these rows and every
     reader below is a derivation over them, so a replayed unit, a demoted
     unit, and a fresh one are the same data answering the same questions. *)
  type contribution = {
    unit_name : string;
        (** The compilation unit name the compiler recorded — the ambiguity
            tabulation reads it on fresh and replayed rows alike. *)
    generated : string option;
        (** The generated marker: [Some why] is a facts-only unit. *)
    kept : (string * Finding.t) list;  (** (rule name, finding). *)
    audits : (string * Finding.t) list;
    suppressed : (Suppress.Directive.kind * string * string * Finding.t) list;
        (** (directive kind, rule, reason, finding), emission order — the claim
            is typed at the source, so [expected] is a filter, never a second
            list. *)
    notes : string list;
    dropped : int;
    degradations : degradation list;
    failures : (string * string) list;  (** (rule, message), sorted. *)
    facts : (string * string list) list;
        (** Project-rule facts by rule name, each fact one [Marshal] frame
            sealed by [Rule.project]'s constructor — bytes at the seam, so every
            payload channel and the report phase hand the same bytes. *)
  }

  type row = Skip of Unit.Skip.t | Unit of contribution

  (* The memoized flattened views: the substrate is [rows]; these exist so
     [iter_findings] stays allocation-free per call. Demoting rebuilds them. *)
  type view = {
    v_findings : (string * Rule.Severity.t * Finding.t) list;
    v_suppressed : (Suppress.Directive.kind * string * string * Finding.t) list;
  }

  type t = {
    rows : (string * row) list;  (** Roster order — the ledger. *)
    project_names : string list;
        (** The selected project rules, selection order. *)
    capable : bool;  (** [Roster.project_capable] at the run. *)
    project_findings : (string * Finding.t) list;
        (** (rule name, finding) as the report phase emitted them — raw: [keep],
            severity, and the block gate apply in the view. *)
    project_dropped : int;
    withheld_rules : (string * string) list;
        (** Kind-gated local rules structurally silent in this run — (rule,
            reason) pairs in selection order — silence enumerated, never read as
            cleanliness. *)
    failures : failure list;
    rules_selected : int;
    keep : path:string -> rule:string -> bool;
    severity_of : string -> Rule.Severity.t option;
    view : view Lazy.t;
  }

  (* The report's total order: (path, start offset, rule name, end offset,
     message). Once path and start are equal, [Finding.compare]
     reduces to exactly the end-offset-then-message tail, so it supplies
     it. *)
  let compare_keyed r1 f1 r2 f2 =
    let l1 = (Finding.loc f1).Location.loc_start
    and l2 = (Finding.loc f2).Location.loc_start in
    let c = String.compare l1.pos_fname l2.pos_fname in
    if c <> 0 then c
    else
      let c = Int.compare l1.pos_cnum l2.pos_cnum in
      if c <> 0 then c
      else
        let c = String.compare r1 r2 in
        if c <> 0 then c else Finding.compare f1 f2

  let compare_reported (r1, _, f1) (r2, _, f2) = compare_keyed r1 f1 r2 f2

  let compare_suppressed (k1, r1, why1, f1) (k2, r2, why2, f2) =
    let c = compare_keyed r1 f1 r2 f2 in
    if c <> 0 then c else compare (k1, why1) (k2, why2)

  (* Two roster entries for one source path — two artifact copies of
     one unit — emit identical rows; sorting makes the copies adjacent and an
     identical report row is one row, not two. One closure, applied uniformly
     to every sorted view. *)
  let dedup_sorted ~compare sorted =
    List.rev
      (List.fold_left
         (fun acc x ->
           match acc with
           | prev :: _ when compare prev x = 0 -> acc
           | _ -> x :: acc)
         [] sorted)

  let outcome_of_row = function
    | Skip sk -> Skipped sk
    | Unit c -> (
        match c.generated with Some _ -> Facts_only | None -> Linted)

  let units rep = List.map (fun (p, row) -> (p, outcome_of_row row)) rep.rows

  (* {2 The project-rule disposition algebra}

     Everything derives from the rows, so the run's report gate and every
     consumer page read one function and cannot disagree. *)

  let skipped_pairs rows =
    List.filter_map (function p, Skip sk -> Some (p, sk) | _ -> None) rows

  (* Admitted units tabulated by compilation unit name: a name declared by
     two distinct paths makes every name-keyed cross-module join ambiguous,
     so the engine blocks every project [report] rather than let one report
     over a collapsed identity. Two rows with one path — two artifact copies
     of one unit — are one unit, never a duplicate. Names sorted; paths in
     roster order.

     Dune's generated per-stanza executable alias modules ([dune__exe.ml-gen],
     every one compilation unit [Dune__exe]) would trip this tabulation on any
     workspace with two multi-module executable or test stanzas — a guaranteed
     layout, so project rules would be blocked forever. Of the two candidate
     fixes (exclude the alias units from the roster, or path-key them out of
     this tabulation), exclusion at the roster is the chosen one and
     lives in the dune adapter: a path-keyed exemption here would readmit
     duplicate-named units whose name-keyed joins (the fact rows' unit-name
     targets, the solver's synthetic [link]/[all] nodes) stay exactly as
     ambiguous as this gate exists to refuse — qualifying identity by owner
     path everywhere is the eventual fix, deferred past 1.0.
     The tabulation itself is deliberately total: a real duplicate — two
     executables both named [main.ml] — still blocks, and any non-dune
     adapter that feeds duplicate alias units gets the same honest block
     instead of a silent exemption. *)
  let ambiguities rows =
    let paths_by_name : (string, string list) Hashtbl.t = Hashtbl.create 16 in
    List.iter
      (fun (p, row) ->
        match row with
        | Skip _ -> ()
        | Unit c ->
            let paths =
              Option.value
                (Hashtbl.find_opt paths_by_name c.unit_name)
                ~default:[]
            in
            if not (List.mem p paths) then
              Hashtbl.replace paths_by_name c.unit_name (paths @ [ p ]))
      rows;
    List.sort
      (fun (a, _) (b, _) -> String.compare a b)
      (Hashtbl.fold
         (fun name paths acc ->
           match paths with _ :: _ :: _ -> (name, paths) :: acc | _ -> acc)
         paths_by_name [])

  let collect_failed_units rows name =
    List.filter_map
      (fun (p, row) ->
        match row with
        | Unit c when List.mem_assoc name c.failures -> Some p
        | Unit _ | Skip _ -> None)
      rows

  let block_of ~capable ~rows name =
    if not capable then Some Not_capable
    else
      match skipped_pairs rows with
      | _ :: _ as blocking -> Some (Incomplete blocking)
      | [] -> (
          match ambiguities rows with
          | _ :: _ as dups -> Some (Ambiguous dups)
          | [] -> (
              match collect_failed_units rows name with
              | [] -> None
              | paths -> Some (Collect_failed paths)))

  let project_rules rep =
    List.map
      (fun name -> (name, block_of ~capable:rep.capable ~rows:rep.rows name))
      rep.project_names

  (* {2 The derived views} *)

  let make_view ~rows ~capable ~project_findings ~keep ~severity_of =
    lazy
      (let keep_finding name f =
         keep ~path:(Finding.loc f).Location.loc_start.pos_fname ~rule:name
       in
       let unit_rows =
         (* [keep] selects by the file a finding is in: the unit's own path
            for every lane but the interface text lane, whose findings carry
            the interface source's path. Audit findings are engine-owned
            warnings: no [Rule.t] backs them, so there is no group to
            derive severity from — warnings by definition. A row naming a
            rule outside the selected set cannot arise under the payload
            channels' contracts; dropped defensively rather than crash on a
            corrupt byte. *)
         List.concat_map
           (fun (_, row) ->
             match row with
             | Skip _ -> []
             | Unit c ->
                 List.filter_map
                   (fun (name, f) ->
                     match severity_of name with
                     | Some sev when keep_finding name f -> Some (name, sev, f)
                     | Some _ | None -> None)
                   c.kept
                 @ List.filter_map
                     (fun (name, f) ->
                       if keep_finding name f then
                         Some (name, Rule.Severity.Warning, f)
                       else None)
                     c.audits)
           rows
       in
       let project_rows =
         (* A project rule's findings stand only while nothing blocks it —
            demoting a unit blocks every project rule, so universal claims
            never outlive the universe they quantified over. *)
         List.filter_map
           (fun (name, f) ->
             if block_of ~capable ~rows name = None && keep_finding name f then
               match severity_of name with
               | Some sev -> Some (name, sev, f)
               | None -> None
             else None)
           project_findings
       in
       let v_findings =
         dedup_sorted ~compare:compare_reported
           (List.stable_sort compare_reported (unit_rows @ project_rows))
       in
       let v_suppressed =
         dedup_sorted ~compare:compare_suppressed
           (List.stable_sort compare_suppressed
              (List.concat_map
                 (fun (_, row) ->
                   match row with Skip _ -> [] | Unit c -> c.suppressed)
                 rows))
       in
       { v_findings; v_suppressed })

  let findings rep =
    List.map (fun (rule, _, f) -> (rule, f)) (Lazy.force rep.view).v_findings

  let iter_findings rep fn =
    List.iter
      (fun (rule, severity, f) -> fn ~rule ~severity f)
      (Lazy.force rep.view).v_findings

  let suppressed rep =
    List.map
      (fun (_, rule, reason, f) -> (rule, f, reason))
      (Lazy.force rep.view).v_suppressed

  let expected rep =
    List.filter_map
      (function
        | Suppress.Directive.Expect, rule, reason, f -> Some (rule, f, reason)
        | Suppress.Directive.Allow, _, _, _ -> None)
      (Lazy.force rep.view).v_suppressed

  let degradation_message = function
    | Offsets ->
        "editable source does not parse — attribute rules, attribute \
         suppression, and corroboration unavailable"
    | Resolution { cmi; reason } ->
        Printf.sprintf
          "canonical-name resolution degraded: unreadable cmi %s (%s) \
           \xe2\x80\x94 rules mentioning names it defines match nothing"
          cmi reason

  let degradations rep =
    (* Resolution rows carry per-unit deltas; a payload replayed beside
       another that saw the same cmi first must not double the note, so the
       first row in roster order wins — the same dedup assembly applies. *)
    let seen = Hashtbl.create 4 in
    List.concat_map
      (fun (p, row) ->
        match row with
        | Skip _ -> []
        | Unit c ->
            List.filter_map
              (fun d ->
                match d with
                | Offsets -> Some (p, d)
                | Resolution { cmi; reason } ->
                    if Hashtbl.mem seen (cmi, reason) then None
                    else begin
                      Hashtbl.add seen (cmi, reason) ();
                      Some (p, d)
                    end)
              c.degradations)
      rep.rows

  let degraded rep =
    List.map (fun (p, d) -> (p, degradation_message d)) (degradations rep)

  let notes rep =
    List.concat_map
      (fun (p, row) ->
        match row with
        | Skip _ -> []
        | Unit c ->
            (match c.generated with
              | Some why ->
                  [ (p, Printf.sprintf "generated (%s) — facts-only" why) ]
              | None -> [])
            @ List.map (fun n -> (p, n)) c.notes)
      rep.rows

  let withheld_rules rep = rep.withheld_rules
  let failures rep = rep.failures

  let dropped rep =
    List.fold_left
      (fun acc (_, row) ->
        match row with Skip _ -> acc | Unit c -> acc + c.dropped)
      rep.project_dropped rep.rows

  let rules_selected rep = rep.rules_selected

  let exit_code rep =
    if rep.failures <> [] then 3
    else if (Lazy.force rep.view).v_findings <> [] then 1
    else 0

  let remake rep ~rows ~project_findings =
    {
      rep with
      rows;
      project_findings;
      view =
        make_view ~rows ~capable:rep.capable ~project_findings ~keep:rep.keep
          ~severity_of:rep.severity_of;
    }

  (* End-of-run revalidation, pointwise on the ledger: demoting an admitted unit removes its whole contribution —
     findings, suppressed findings, notes, degradations — and, because every
     project-rule disposition derives from the rows, moves every project rule
     to [Incomplete] with the demoted unit among the blockers, dropping
     project findings from the page. Rule failures stay — they happened, and
     exit 3's dominance must not silently soften. *)
  let demote ~path skip rep =
    if List.mem_assoc path rep.rows then
      let rows =
        List.map
          (fun (p, row) ->
            if String.equal p path then
              (p, match row with Unit _ -> Skip skip | Skip _ -> row)
            else (p, row))
          rep.rows
      in
      remake rep ~rows ~project_findings:rep.project_findings
    else
      (* A path that is no unit's own but anchors findings — an interface
         source of the text lane: exactly those findings go, project
         findings included, no outcome or disposition touched. *)
      let elsewhere f =
        not (String.equal (Finding.loc f).Location.loc_start.pos_fname path)
      in
      let rows =
        List.map
          (fun (p, row) ->
            match row with
            | Skip _ -> (p, row)
            | Unit c ->
                ( p,
                  Unit
                    {
                      c with
                      kept = List.filter (fun (_, f) -> elsewhere f) c.kept;
                      audits = List.filter (fun (_, f) -> elsewhere f) c.audits;
                      suppressed =
                        List.filter
                          (fun (_, _, _, f) -> elsewhere f)
                          c.suppressed;
                    } ))
          rep.rows
      in
      remake rep ~rows
        ~project_findings:
          (List.filter (fun (_, f) -> elsewhere f) rep.project_findings)
end

(* One summary, derived once: the text page prints it and the json trailer
   serializes it field-for-field, so the human and machine channels cannot
   disagree on the truth set. *)
module Summary = struct
  type t = {
    rules_selected : int;
    linted : int;
    facts_only : int;
    units : int;
    findings : int;
    fixable : int;
    suppressed : int;
    skipped : int;
    skipped_by_reason : (string * int) list;
    dropped : int;
    degraded : int;
    exit_code : int;
  }

  let of_report rep =
    let linted = ref 0 and facts_only = ref 0 and skipped = ref 0 in
    let skips = Hashtbl.create 8 in
    List.iter
      (fun (_, outcome) ->
        match (outcome : Report.outcome) with
        | Report.Linted -> incr linted
        | Report.Facts_only -> incr facts_only
        | Report.Skipped sk ->
            incr skipped;
            (* Grouped by the skip taxonomy's machine slug, in
               declaration-order rank — the vocabulary both renderers share. *)
            let key = (Unit.Skip.rank sk, Unit.Skip.slug sk) in
            Hashtbl.replace skips key
              (1 + Option.value (Hashtbl.find_opt skips key) ~default:0))
      (Report.units rep);
    let findings = ref 0 and fixable = ref 0 in
    Report.iter_findings rep (fun ~rule:_ ~severity:_ f ->
        incr findings;
        if Finding.fix f <> None then incr fixable);
    {
      rules_selected = Report.rules_selected rep;
      linted = !linted;
      facts_only = !facts_only;
      units = !linted + !facts_only;
      findings = !findings;
      fixable = !fixable;
      suppressed = List.length (Report.suppressed rep);
      skipped = !skipped;
      skipped_by_reason =
        List.map
          (fun ((_, slug), n) -> (slug, n))
          (List.sort compare
             (Hashtbl.fold (fun k n acc -> (k, n) :: acc) skips []));
      dropped = Report.dropped rep;
      degraded = List.length (Report.degraded rep);
      exit_code = Report.exit_code rep;
    }
end

(* {1 Registry validation}

   Pure checks over the selected rule set. Duplicate names are refused before
   any unit loads; the fix promise is checked per emitted finding. *)

(* [duplicate_name rules] is the first rule name declared twice, in list
   order. *)
let duplicate_name rules =
  let seen = Hashtbl.create 16 in
  List.find_map
    (fun r ->
      let n = Rule.name r in
      if Hashtbl.mem seen n then Some n
      else begin
        Hashtbl.add seen n ();
        None
      end)
    rules

(* [breaks_promise r f] is [true] iff [r] promised [Never] and [f] carries a
   fix — a rule failure, checked here because only the engine sees both. *)
let breaks_promise rule finding =
  (match Rule.fix rule with
    | Fix.Never -> true
    | Fix.Sometimes | Fix.Always -> false)
  && Finding.fix finding <> None

(* {1 Kind index}

   The selected rules, partitioned once per run by the node kind their
   constructor subscribed them to — dispatch then pays O(rules subscribed to
   that kind) per node. Source callbacks are wrapped to take the unit so
   every kind dispatches through the one [dispatch_all]. *)

type kinds = {
  exprs : (Rule.t * (Unit.t -> Typedtree.expression -> Finding.t list)) list;
  patterns : (Rule.t * (Unit.t -> Typedtree.pattern -> Finding.t list)) list;
  bindings :
    (Rule.t * (Unit.t -> Typedtree.value_binding -> Finding.t list)) list;
  type_decls :
    (Rule.t * (Unit.t -> Typedtree.type_declaration list -> Finding.t list))
    list;
  let_groups :
    (Rule.t
    * (Unit.t ->
      Location.t * Asttypes.rec_flag * Typedtree.value_binding list ->
      Finding.t list))
    list;
      (** The labelled [Let_group] callback uncurried over one payload value, so
          the one [dispatch_all] serves this kind too. *)
  module_bindings :
    (Rule.t * (Unit.t -> Rule.Module_binding.t -> Finding.t list)) list;
  exports : (Rule.t * (Unit.t -> Unit.Export.t -> Finding.t list)) list;
  attributes :
    (Rule.t * (Unit.t -> Parsetree.attribute -> Finding.t list)) list;
  attr_names : string list option;
      (** The union of the attribute rules' declared interests
          ([Rule.attribute ?names]); [None] when any selected attribute rule
          declared none — the parse demand gate in [analyze]. *)
  sources : (Rule.t * (Unit.t -> Source.t -> Finding.t list)) list;
}

(* [List.fold_right] keeps each field in [rules] order without a reversal
   pass; the match is exhaustive so a new rule kind fails to compile here
   instead of silently not dispatching. *)
let index_kinds rules =
  List.fold_right
    (fun r k ->
      match Rule.callback r with
      | Rule.Expr f -> { k with exprs = (r, f) :: k.exprs }
      | Rule.Pattern f -> { k with patterns = (r, f) :: k.patterns }
      | Rule.Binding f -> { k with bindings = (r, f) :: k.bindings }
      | Rule.Type_decl f -> { k with type_decls = (r, f) :: k.type_decls }
      | Rule.Let_group f ->
          {
            k with
            let_groups =
              (r, fun u (loc, rf, vbs) -> f u ~loc rf vbs) :: k.let_groups;
          }
      | Rule.Module_binding f ->
          { k with module_bindings = (r, f) :: k.module_bindings }
      | Rule.Export f -> { k with exports = (r, f) :: k.exports }
      | Rule.Attribute (names, f) ->
          {
            k with
            attributes = (r, f) :: k.attributes;
            attr_names =
              (match (k.attr_names, names) with
              | Some acc, Some ns -> Some (List.rev_append ns acc)
              | None, _ | _, None -> None);
          }
      | Rule.Source f ->
          { k with sources = (r, fun _ src -> f src) :: k.sources }
      | Rule.Project _ ->
          (* No per-node dispatch: [collect] runs once per admitted unit in
             [run]'s roster loop, [report] once at assembly. *)
          k)
    rules
    {
      exprs = [];
      patterns = [];
      bindings = [];
      type_decls = [];
      let_groups = [];
      module_bindings = [];
      exports = [];
      attributes = [];
      attr_names = Some [];
      sources = [];
    }

(* [contains_sub s sub ~anchor] is [true] iff [sub] occurs in [s] — the
   demand gates' byte scan. Candidate positions come from
   [String.index_from_opt] on [sub.[anchor]] (memchr, so the whole-file scan
   runs at C speed between hits) — pick the needle's rarest byte. The
   ["[@"]/["litany"] conjunction in [analyze] must stay equivalent to
   [Suppress.spelled]. *)
let contains_sub s sub ~anchor =
  let n = String.length s and m = String.length sub in
  let c = sub.[anchor] in
  let rec eq i j = j = m || (s.[i + j] = sub.[j] && eq i (j + 1)) in
  let rec at i =
    (* [i] is the next candidate position of the anchor byte. *)
    if i >= n then false
    else
      match String.index_from_opt s i c with
      | None -> false
      | Some j ->
          let start = j - anchor in
          (start >= 0 && start + m <= n && eq start 0) || at (j + 1)
  in
  at anchor

(* {1 Suppression}

   The audit rules are engine-owned: no catalog rule may take their names,
   and no directive can suppress their findings. Directive rule names
   resolve against the run's [catalog] (canonical names and tombstone
   aliases); the per-name status decides whether matching and the
   gated audits are live for it. *)

let audit_allow = "unused-allow"
let audit_expect = "unfulfilled-expect"
let audit_rules = [ audit_allow; audit_expect ]
let engine_owned n = String.equal n audit_allow || String.equal n audit_expect

type rule_status =
  | Runs  (** Selected and locally dispatched: matching and audits live. *)
  | Text  (** Selected text rule: never attribute-suppressible. *)
  | Project
      (** Known project rule, selected or not: project findings answer to
          configuration only in this release, so the directive is inert — but
          named in a per-unit note, never silently swallowed (ALT-PROJ-06). *)
  | Off  (** Known local rule not running per-unit: unselected. *)

type resolution =
  | Engine_owned
  | Unknown of string option  (** The did-you-mean hint, if any. *)
  | Known of { canonical : string; alias : bool; status : rule_status }

type suppress_ctx = { resolve : string -> resolution }

let suppress_ctx ~catalog ~rules =
  let status : (string, rule_status) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun r ->
      let s =
        if Rule.is_project r then Project
        else match Rule.callback r with Rule.Source _ -> Text | _ -> Runs
      in
      Hashtbl.replace status (Rule.name r) s)
    rules;
  (* Catalog rules outside [rules] are known-but-not-run: [Off], their
     audits withheld — except text rules, whose directives can never match
     under any selection (text findings are config-suppressed only). That is a
     syntactic fact, not an absence claim, so they audit from the catalog
     even unselected. *)
  List.iter
    (fun r ->
      let n = Rule.name r in
      if not (Hashtbl.mem status n) then
        Hashtbl.replace status n
          (if Rule.is_project r then Project
           else match Rule.callback r with Rule.Source _ -> Text | _ -> Off))
    catalog;
  (* Written name -> (canonical, alias). Canonical names are registered
     before aliases so a name that is both stays a rule, not an alias. *)
  let names : (string, string * bool) Hashtbl.t = Hashtbl.create 32 in
  let universe = catalog @ rules in
  List.iter
    (fun r ->
      let n = Rule.name r in
      if not (Hashtbl.mem names n) then Hashtbl.add names n (n, false))
    universe;
  List.iter
    (fun r ->
      List.iter
        (fun a ->
          if not (Hashtbl.mem names a) then
            Hashtbl.add names a (Rule.name r, true))
        (Rule.renamed_from r))
    universe;
  let vocabulary =
    List.sort_uniq String.compare
      (Hashtbl.fold (fun n _ acc -> n :: acc) names [])
  in
  let resolve written =
    if engine_owned written then Engine_owned
    else
      match Hashtbl.find_opt names written with
      | Some (canonical, alias) ->
          let s =
            Option.value (Hashtbl.find_opt status canonical) ~default:Off
          in
          Known { canonical; alias; status = s }
      | None -> Unknown (Rule.suggest ~candidates:vocabulary written)
  in
  { resolve }

(* {1 Per-unit analysis} *)

(* The dispatch lane an emission arrived from — the emit contract's checks
   are lane-indexed. [Typed] findings corroborate against the pre-PPX parse;
   [Untyped] (parsed, attribute, and source dispatch over the editable
   source) skip corroboration — those substrates are pre-PPX by
   construction; [Intf] (source rules over the paired interface source)
   answers to the interface file instead: ownership
   is its exact path, consistency its line index, and the path needs no
   rewrite — the rule built the location from the interface source itself. *)
type lane = Typed | Untyped | Intf

type unit_result = {
  kept : (Rule.t * bool * Finding.t) list;
      (** (rule, offset-consistent, finding), emission order — the bool is the
          emit contract's consistency verdict, carried so suppression never
          matches the offsets the contract distrusts. *)
  unit_suppressed :
    (Suppress.Directive.kind * string * string * Finding.t) list;
      (** (directive kind, rule, reason, finding), emission order — the claim is
          typed at the source; [expect]'s subset is a filter downstream. *)
  unit_audits : (string * Finding.t) list;
      (** (audit rule, finding), attribute order. *)
  unit_notes : string list;  (** Deduplicated, attribute order. *)
  unit_dropped : int;
  unit_degraded : bool;
      (** The parse substrate was demanded and the source does not parse. *)
  unit_failures : (string * string) list;  (** (rule, message), sorted. *)
}

(* [parse_spans tree] is the set of (start, stop) byte spans of every location
   recorded in [tree] — the corroboration witness for typed findings: a span
   present here existed in the pre-PPX source. *)
let parse_spans tree =
  let tbl = Hashtbl.create 512 in
  let default = Ast_iterator.default_iterator in
  let iterator =
    {
      default with
      Ast_iterator.location =
        (fun _ (l : Location.t) ->
          Hashtbl.replace tbl (l.loc_start.pos_cnum, l.loc_end.pos_cnum) ());
    }
  in
  iterator.structure iterator tree;
  tbl

let analyze ~kinds ~suppress u =
  (* Rule failure isolation: the first exception (or promise violation) of a
     rule on this unit records the failure, stops further dispatch of that
     rule here, and discards its findings on this unit. *)
  let failed : (string, string) Hashtbl.t = Hashtbl.create 4 in
  let fail rule msg =
    let n = Rule.name rule in
    if not (Hashtbl.mem failed n) then Hashtbl.add failed n msg
  in
  let emissions = ref [] in
  (* Recursive rather than [List.iter] so per node no closure is built, and
     the empty [failed] table — every healthy unit — short-circuits before
     hashing any rule name. *)
  let rec dispatch_all :
      'a.
      lane:lane ->
      (Rule.t * (Unit.t -> 'a -> Finding.t list)) list ->
      'a ->
      unit =
   fun ~lane rules node ->
    match rules with
    | [] -> ()
    | (rule, cb) :: rest ->
        (if
           Hashtbl.length failed = 0
           || not (Hashtbl.mem failed (Rule.name rule))
         then
           match cb u node with
           | [] -> ()
           | fs ->
               List.iter
                 (fun f -> emissions := (rule, lane, f) :: !emissions)
                 fs
           | exception e -> fail rule (Printexc.to_string e));
        dispatch_all ~lane rest node
  in
  (* One [Tast_iterator] traversal for every typed kind; skipped entirely
     when no typed rule is selected. The declaration-side kinds
     ([type_decl]/[let_group]/[module_binding]) ride this same pass behind
     non-empty-kind gates — no second traversal exists. Structure-level
     groups dispatch from the [structure] hook (each structure's own
     [str_items]), not [structure_item]: on the 5.5 leg a [let module] or
     [type … in] embeds a bare [structure_item] in expression position
     ([Expr_item] is the seam), and reading [str_items] keeps such
     items off the structure-level dispatch without a context flag. *)
  if
    kinds.exprs <> [] || kinds.patterns <> [] || kinds.bindings <> []
    || kinds.type_decls <> [] || kinds.let_groups <> []
    || kinds.module_bindings <> []
  then begin
    let default = Tast_iterator.default_iterator in
    (* [Module_binding.position]'s Toplevel/Nested split: structural, O(1)
       — [at_root] is [true] only while the walk is among the root
       structure's own items; flipped off on entering any module
       expression (functor bodies included) or class body, restored on
       the way out. *)
    let at_root = ref true in
    let nested walk sub node =
      let saved = !at_root in
      at_root := false;
      walk sub node;
      at_root := saved
    in
    let decl_kinds =
      kinds.type_decls <> [] || kinds.let_groups <> []
      || kinds.module_bindings <> []
    in
    let iterator =
      {
        default with
        Tast_iterator.expr =
          (fun sub e ->
            dispatch_all ~lane:Typed kinds.exprs e;
            (if kinds.let_groups <> [] then
               match e.exp_desc with
               | Typedtree.Texp_let (rf, vbs, _) ->
                   dispatch_all ~lane:Typed kinds.let_groups (e.exp_loc, rf, vbs)
               | _ -> ());
            (if kinds.module_bindings <> [] then
               match Expr_item.local_module e with
               | Some (id, name_loc) ->
                   dispatch_all ~lane:Typed kinds.module_bindings
                     (Rule.Module_binding.v ~id ~name_loc ~loc:e.exp_loc
                        ~position:Rule.Module_binding.Local)
               | None -> ());
            (if kinds.type_decls <> [] then
               (* 5.5's expression-local [type … in e] groups dispatch
                  as ordinary [type_decl] groups ([None] always on the
                  5.3/5.4 leg). *)
               match Expr_item.type_group e with
               | Some (_, _, ds) -> dispatch_all ~lane:Typed kinds.type_decls ds
               | None -> ());
            default.expr sub e);
        pat =
          (fun (type k) sub (p : k Typedtree.general_pattern) ->
            (match Typedtree.classify_pattern p with
            | Typedtree.Value -> dispatch_all ~lane:Typed kinds.patterns p
            | Typedtree.Computation -> ());
            default.pat sub p);
        value_binding =
          (fun sub vb ->
            dispatch_all ~lane:Typed kinds.bindings vb;
            default.value_binding sub vb);
        structure =
          (fun sub s ->
            (if decl_kinds then
               let toplevel = !at_root in
               List.iter
                 (fun (item : Typedtree.structure_item) ->
                   match item.str_desc with
                   | Typedtree.Tstr_type (_, ds) when kinds.type_decls <> [] ->
                       dispatch_all ~lane:Typed kinds.type_decls ds
                   | Typedtree.Tstr_value (rf, vbs) when kinds.let_groups <> []
                     ->
                       dispatch_all ~lane:Typed kinds.let_groups
                         (item.str_loc, rf, vbs)
                   | Typedtree.Tstr_module mb when kinds.module_bindings <> []
                     ->
                       (* [Tstr_recmodule] is deliberately not dispatched:
                          self- and cross-references are its point. *)
                       dispatch_all ~lane:Typed kinds.module_bindings
                         (Rule.Module_binding.v ~id:mb.Typedtree.mb_id
                            ~name_loc:mb.Typedtree.mb_name.Location.loc
                            ~loc:mb.Typedtree.mb_loc
                            ~position:
                              (if toplevel then Rule.Module_binding.Toplevel
                               else Rule.Module_binding.Nested))
                   | _ -> ())
                 s.Typedtree.str_items);
            default.structure sub s);
        module_expr = (fun sub me -> nested default.module_expr sub me);
        class_expr = (fun sub ce -> nested default.class_expr sub ce);
      }
    in
    iterator.structure iterator (Unit.implementation u)
  end;
  (* The export index walk: one dispatch per row of [Unit.exports],
     in signature order, after the typed traversal. Gated on the kind so a
     run without export rules never demands the index (and never pays an
     interface decode); findings answer to the Typed lane's full emit
     contract — export rules anchor in the editable source like every
     typed rule. *)
  if kinds.exports <> [] then
    List.iter
      (fun x -> dispatch_all ~lane:Typed kinds.exports x)
      (Unit.exports u);
  (* The parse substrate is demand-gated: touched only when an attribute
     rule is selected, or a typed finding needs corroborating. A demand
     that finds no parse marks the unit degraded. When every attribute
     rule declares its names ([Rule.attribute ?names]) the demand
     narrows to sources that can hold one — an explicitly written
     attribute spells ["[@"] and its name literally, so the byte scan is
     exact for written attributes; no scan hit means no demand, no
     dispatch, and no degradation note. *)
  let parse_demand_failed = ref false in
  let demand_parse () =
    match Unit.parsetree u with
    | Some tree -> Some tree
    | None ->
        parse_demand_failed := true;
        None
  in
  (* One ["[@"] scan feeds both demand gates: the attribute rules' name
     gate here and the suppression scan below. *)
  let text = Source.contents (Unit.source u) in
  let has_attr = contains_sub text "[@" ~anchor:1 in
  let parse_wanted =
    kinds.attributes <> []
    &&
    match kinds.attr_names with
    | None -> true
    | Some names ->
        has_attr && List.exists (fun nm -> contains_sub text nm ~anchor:0) names
  in
  if parse_wanted then
    begin match demand_parse () with
    | None -> ()
    | Some tree ->
        let default = Ast_iterator.default_iterator in
        let iterator =
          {
            default with
            Ast_iterator.attribute =
              (fun sub a ->
                dispatch_all ~lane:Untyped kinds.attributes a;
                default.attribute sub a);
          }
        in
        iterator.structure iterator tree
    end;
  dispatch_all ~lane:Untyped kinds.sources (Unit.source u);
  (* The interface text lane: source rules run
     over the unit's paired interface source too, so a companion [.mli] is
     text-linted exactly as an interface-only unit's would be. Findings
     anchor in the interface file; nothing else — the parse, the typedtree,
     attribute suppression — derives from it. *)
  (match Unit.interface_source u with
  | Some isrc -> dispatch_all ~lane:Intf kinds.sources isrc
  | None -> ());
  let emissions = List.rev !emissions in
  (* Promise pass first: a violation anywhere fails the rule on the whole
     unit, discarding its other findings here too. *)
  List.iter
    (fun (rule, _, f) ->
      if (not (Hashtbl.mem failed (Rule.name rule))) && breaks_promise rule f
      then fail rule "returned a fix but its meta promises Never")
    emissions;
  (* The emit contract. *)
  let src = Unit.source u in
  let upath = Unit.path u in
  let unit_base = Filename.basename upath in
  let anchor_base = Filename.basename (Unit.Witness.anchor (Unit.witness u)) in
  (* Ownership (b): compiler-recorded names are compared as strings against
     the unit's own names — the editable source or the witness anchor (the
     file the compiler actually read) — by basename, exactly as admission
     compares recorded source names; they are never resolved as paths. *)
  let owned_name fname =
    let b = Filename.basename fname in
    String.equal b unit_base || String.equal b anchor_base
  in
  let owned (l : Location.t) =
    owned_name l.loc_start.pos_fname && owned_name l.loc_end.pos_fname
  in
  let consistent (l : Location.t) =
    Source.consistent src l.loc_start
    && Source.consistent src l.loc_end
    && l.loc_start.pos_cnum <= l.loc_end.pos_cnum
  in
  let rewrite_pos (p : Lexing.position) = { p with pos_fname = upath } in
  let rewrite_loc (l : Location.t) =
    {
      l with
      loc_start = rewrite_pos l.loc_start;
      loc_end = rewrite_pos l.loc_end;
    }
  in
  let spans =
    lazy
      (match demand_parse () with
      | None -> None
      | Some tree -> Some (parse_spans tree))
  in
  (* Corroboration (d) gates typed findings only: parse and text substrates
     are pre-PPX by construction, so nothing there can be PPX-fabricated.
     Offset-inconsistent findings skip it — their offsets are exactly what
     cannot be trusted — and are kept line-anchored per (c). *)
  let corroborated ~typed cons (l : Location.t) =
    (not typed) || (not cons)
    ||
    match Lazy.force spans with
    | None -> true (* waived: the unit is marked degraded *)
    | Some tbl -> Hashtbl.mem tbl (l.loc_start.pos_cnum, l.loc_end.pos_cnum)
  in
  (* The interface lane's own checks: ownership is the interface source's
     exact path — the rule built the location from [Source.location]
     on it, so basename comparison would be looser than the truth — and
     consistency is its line index. *)
  let intf_owned, intf_consistent =
    match Unit.interface_source u with
    | None -> ((fun (_ : Location.t) -> false), fun (_ : Location.t) -> false)
    | Some isrc ->
        let ipath = Source.path isrc in
        ( (fun (l : Location.t) ->
            String.equal l.loc_start.pos_fname ipath
            && String.equal l.loc_end.pos_fname ipath),
          fun (l : Location.t) ->
            Source.consistent isrc l.loc_start
            && Source.consistent isrc l.loc_end
            && l.loc_start.pos_cnum <= l.loc_end.pos_cnum )
  in
  let seen = Hashtbl.create 32 in
  let kept = ref [] in
  let dropped = ref 0 in
  List.iter
    (fun (rule, lane, f) ->
      if not (Hashtbl.mem failed (Rule.name rule)) then begin
        let typed = lane = Typed in
        let loc = Finding.loc f in
        let cons =
          match lane with Intf -> intf_consistent loc | _ -> consistent loc
        in
        let owned_here =
          match lane with Intf -> intf_owned loc | _ -> owned loc
        in
        (* The drop conditions, in contract order — [||] preserves the
           short-circuit, so [corroborated] is unreached for ghost or
           unowned findings. ([consistent] is a pure, guarded lookup, safe
           on any position.) *)
        if
          loc.Location.loc_ghost || (not owned_here)
          || not (corroborated ~typed cons loc)
        then incr dropped
        else begin
          let fix =
            match Finding.fix f with
            | None -> None
            | Some fx ->
                (* Line-anchored findings render display-only fixes, as do
                   typed findings whose corroboration was waived — their
                   spans count preprocessed bytes and must never reach an
                   applier; preprocessed units earn no [Safe]. The
                   interface lane skips the preprocessed downgrade: the
                   interface source is read directly, never through a
                   preprocessor, so its offsets are its own bytes. *)
                if (not cons) || (typed && Option.is_none (Lazy.force spans))
                then Some (Fix.with_applicability Fix.Display fx)
                else if
                  lane <> Intf && Unit.preprocessed u
                  && Fix.applicability fx = Fix.Safe
                then Some (Fix.with_applicability Fix.Unsafe fx)
                else Some fx
          in
          (* No rewrite on the interface lane: the location's path is the
             adapter-supplied interface path already. *)
          let loc' = match lane with Intf -> loc | _ -> rewrite_loc loc in
          let f' = Finding.v ?fix ~loc:loc' (Finding.message f) in
          let key = (Rule.name rule, Finding.loc f', Finding.message f') in
          if not (Hashtbl.mem seen key) then begin
            Hashtbl.add seen key ();
            kept := (rule, cons, f') :: !kept
          end
        end
      end)
    emissions;
  let kept = List.rev !kept in
  (* Suppression: filter the kept findings through the unit's attribute
     directives, then audit the directives. The policy is demanded only when
     the source can spell a directive — the byte scan is exact for written
     attributes — and shares the unit's cached parse; a positive scan on a
     non-parsing source marks the unit degraded through [demand_parse],
     exactly as a parsed-rule demand does. *)
  let policy =
    (* Equivalent to [Suppress.spelled text], sharing the ["[@"] scan
       with the attribute gate above — keep the conjunction in step with the
       definitional needles there. *)
    if not (has_attr && contains_sub text "litany" ~anchor:5) then None
    else
      match demand_parse () with
      | None -> None
      | Some tree ->
          Some (Suppress.of_structure ~source_length:(Source.length src) tree)
  in
  let kept, unit_suppressed, unit_audits, unit_notes =
    match policy with
    | None -> (kept, [], [], [])
    | Some p ->
        let module D = Suppress.Directive in
        (* The consumption ledger: (directive, rule name, finding) per hidden
           finding, reversed emission order. The audit loop's "was [d] used?"
           and the report's [suppressed] channel are both projections of it;
           identity rides on [D.span], unique per attribute. *)
        let hidden = ref [] in
        let kept =
          List.filter
            (fun (rule, cons, f) ->
              let loc = Finding.loc f in
              let start = loc.Location.loc_start.pos_cnum
              and stop = loc.Location.loc_end.pos_cnum in
              (* An offset-inconsistent finding renders by its line and must
                 match by nothing: its offsets count preprocessed bytes —
                 exactly what the emit contract distrusts — so it is
                 unmatchable like a negative span; a covering directive then
                 audits as unused, visibly, instead of silently claiming a
                 finding it may not cover. *)
              if (not cons) || start < 0 || stop < start then true
              else
                let rname = Rule.name rule in
                (* A source rule resolves to [Text] and a project rule to
                   [Project], never [Runs], so [matches] refuses every
                   directive naming one — their findings are suppressed by
                   config only, encoded once in [rule_status]. *)
                let matches written =
                  match suppress.resolve written with
                  | Known { canonical; status = Runs; _ } ->
                      String.equal canonical rname
                  | Engine_owned | Unknown _ | Known _ -> false
                in
                let fspan = Span.v ~start ~stop in
                match Suppress.covering p ~rule:matches fspan with
                | None -> true
                | Some d ->
                    hidden := (d, rname, f) :: !hidden;
                    false)
            kept
        in
        let consumed d =
          List.exists
            (fun (d', _, _) -> Span.equal (D.span d') (D.span d))
            !hidden
        in
        let audits = ref [] and notes = ref [] in
        let audit_at ?fix name span msg =
          match Source.location src span with
          | None -> () (* a policy span is always in bounds *)
          | Some loc -> audits := (name, Finding.v ?fix ~loc msg) :: !audits
        in
        (* The deletion fix on [unused-allow]: remove the
           stale attribute (widened over adjacent blanks — whole line when it
           owns one). Directive spans come from the pre-PPX parse of the
           editable source, so the coordinates are editable-source bytes even
           in preprocessed units and [Safe] stands; deleting an attribute
           never changes behavior. *)
        let deletion_fix d =
          Fix.v ~applicability:Fix.Safe ~title:"delete the unused allow"
            [ { Fix.span = D.deletion ~source:text d; text = "" } ]
        in
        let audit_name = function
          | D.Allow -> audit_allow
          | D.Expect -> audit_expect
        in
        List.iter
          (fun d ->
            let name = audit_name (D.kind d) in
            let word =
              match D.kind d with D.Allow -> "allow" | D.Expect -> "expect"
            in
            match suppress.resolve (D.rule d) with
            | Engine_owned ->
                audit_at name (D.span d)
                  (Printf.sprintf "%S is engine-owned and cannot be suppressed"
                     (D.rule d))
            | Unknown hint ->
                let hint =
                  match hint with
                  | Some c -> Printf.sprintf " (did you mean %S?)" c
                  | None -> ""
                in
                audit_at name (D.span d)
                  (Printf.sprintf "unknown rule %S%s" (D.rule d) hint)
            | Known { canonical; alias; status } -> (
                if alias then
                  notes :=
                    Printf.sprintf
                      "suppression attribute names %S; the rule is now %S \
                       \xe2\x80\x94 update the attribute"
                      (D.rule d) canonical
                    :: !notes;
                match status with
                | Text ->
                    audit_at name (D.span d)
                      (Printf.sprintf
                         "text rule %S is not attribute-suppressible" canonical)
                | Project ->
                    (* ALT-PROJ-06 minimum: the directive is inert — project
                       findings never answer to attributes in this release —
                       and its audit is withheld (the rule did not run
                       per-unit), but the silence is named, never swallowed. *)
                    notes :=
                      Printf.sprintf
                        "directive names project rule %S; project findings \
                         answer to configuration only in this release"
                        canonical
                      :: !notes
                | Off -> () (* the rule did not run here: audit withheld *)
                | Runs ->
                    if Hashtbl.mem failed canonical || consumed d then ()
                    else
                      let fix =
                        match D.kind d with
                        | D.Allow -> Some (deletion_fix d)
                        | D.Expect -> None
                        (* an unfulfilled expect wants the finding back, not
                           the attribute gone — no fix *)
                      in
                      audit_at ?fix name (D.span d)
                        (Printf.sprintf "%s %S matched no finding" word
                           canonical)))
          (Suppress.directives p);
        List.iter
          (fun m ->
            let name =
              match Suppress.Malformed.kind m with
              | Some D.Expect -> audit_expect
              | Some D.Allow | None -> audit_allow
            in
            audit_at name
              (Suppress.Malformed.span m)
              (Suppress.Malformed.message m))
          (Suppress.malformed p);
        let dedup xs =
          List.rev
            (List.fold_left
               (fun acc x -> if List.mem x acc then acc else x :: acc)
               [] xs)
        in
        let claimed = List.rev !hidden in
        ( kept,
          List.map
            (fun (d, rname, f) -> (D.kind d, rname, D.reason d, f))
            claimed,
          List.rev !audits,
          dedup (List.rev !notes) )
  in
  {
    kept;
    unit_suppressed;
    unit_audits;
    unit_notes;
    unit_dropped = !dropped;
    unit_degraded = !parse_demand_failed;
    unit_failures =
      List.sort compare (Hashtbl.fold (fun r m acc -> (r, m) :: acc) failed []);
  }

(* {1 Per-unit payloads}

   One admitted unit's whole contribution to a report, as data: the
   [Report.contribution] row [run]'s assembly consumes for the unit,
   whichever way it was produced — fresh analysis, a cache hit, or a worker
   shard's wire. Assembly stores only this record, so a replayed unit is
   byte-identical to a recomputed one by construction, which is the entire
   warm-vs-cold and [-j N]-vs-[-j 1] determinism argument.

   The encoding is Marshal behind a version line. Marshal is safe for both
   consumers by their own contracts: a cache key includes the binary digest
   (a different binary never loads another binary's entries), and a worker
   shard is a fork of the very same binary image. A payload that fails to
   decode is a miss, never an error.

   v3: the contribution ledger — the payload is the report's per-unit row,
   promoted unchanged into assembly, with [unit_name] (the ambiguity
   tabulation must work on replay), claim-typed degradations, kind-typed
   suppressions, and project facts as per-fact Marshal frames (bytes at the
   seam). The cache key's binary digest already invalidates across the
   schema change; the version line is the same defense for any other byte
   source. *)

let payload_magic = "litany-unit-payload-v3\n"

let encode_payload (c : Report.contribution) =
  payload_magic ^ Marshal.to_string c []

let decode_payload bytes =
  let m = String.length payload_magic in
  if
    String.length bytes < m
    || not (String.equal (String.sub bytes 0 m) payload_magic)
  then None
  else
    match (Marshal.from_string bytes m : Report.contribution) with
    | c -> Some c
    | exception (Failure _ | Invalid_argument _ | End_of_file) ->
        (* What [Marshal] raises on truncated or malformed input; both
           sources are already framed (digest-verified cache entries, a
           same-image pipe), so this is defense, not a lane. *)
        None

(* Cacheable = replayable in any later run: a rule failure must stay live
   (recomputing keeps the exception and exit 3 honest), and a unit that
   first demanded a failing cmi read must recompute so its degradation note
   tracks the still-broken state instead of a snapshot of it — which also
   keeps the note's position warm/cold-identical, since its origin unit
   never replays. Worker wires carry every payload regardless — same run,
   so replay is exact. *)
let storable (c : Report.contribution) =
  c.failures = []
  && List.for_all
       (function Report.Offsets -> true | Report.Resolution _ -> false)
       c.degradations

module Unit_cache = struct
  type t = {
    load : Roster.Entry.t -> string option;
    store : Roster.Entry.t -> string -> unit;
  }

  (* The driver-side frame check: bytes a [load] returns that fail this
     prefix test can never replay, so a driver counting cache statistics
     should count them a miss before the engine quietly recomputes. *)
  let plausible_payload bytes =
    let m = String.length payload_magic in
    String.length bytes >= m
    && String.equal (String.sub bytes 0 m) payload_magic
end

(* {1 The run} *)

let run ?keep ?unit_cache ?capture ?progress ~rules ~catalog ~roster ~load () =
  (match duplicate_name rules with
  | Some n -> invalid_arg ("Engine.run: duplicate rule name " ^ n)
  | None -> ());
  List.iter
    (fun r ->
      let owned n =
        if engine_owned n then
          invalid_arg ("Engine.run: rule name " ^ n ^ " is engine-owned")
      in
      owned (Rule.name r);
      List.iter owned (Rule.renamed_from r))
    (catalog @ rules);
  (* Per-path report selection: config's outer ring. Selection of
     reports, never of analysis — the unit was analyzed, its facts stand,
     and a deselected finding simply never enters the report (not counted
     dropped: dropped is the emit contract's channel). Audit findings
     answer to it like any other report — (ignore all) on a path silences
     the auditors there too. Applied in the report's derived views, so a
     stored payload is selection-neutral. *)
  let keep =
    match keep with Some f -> f | None -> fun ~path:_ ~rule:_ -> true
  in
  let kinds = index_kinds rules in
  let suppress = suppress_ctx ~catalog ~rules in
  (* The one severity channel: render-time severity derives from the
     emitting rule's group, nothing per-finding. Names are unique in
     [rules] (refused above), so the severity a replayed row derives is the
     severity the direct path derived; a name outside the selected set
     answers [None] and its findings are dropped defensively in the view. *)
  let severity_tbl : (string, Rule.Severity.t) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun r ->
      Hashtbl.replace severity_tbl (Rule.name r)
        (Rule.Severity.of_group (Rule.group r)))
    rules;
  let severity_of name = Hashtbl.find_opt severity_tbl name in
  let rule_by_name = Hashtbl.create 16 in
  List.iter (fun r -> Hashtbl.replace rule_by_name (Rule.name r) r) rules;
  (* The project rules of the selected set, in [rules] order: (name, the two
     phases). [collect] runs per admitted unit in the roster loop below;
     [report] runs once at assembly, gated per rule by [Report.block_of]. *)
  let projects =
    List.filter_map
      (fun r ->
        match Rule.callback r with
        | Rule.Project { collect; report } -> Some (Rule.name r, collect, report)
        | _ -> None)
      rules
  in
  (* [collect] per admitted unit, isolated per rule like any callback: a
     raise fails that rule on that unit — and, because its universal claim
     now has a hole, blocks that rule's [report] ([Collect_failed]). Each
     fact is one Marshal frame, sealed inside [collect] by
     [Rule.project]'s constructor, so an unmarshalable fact — a
     closure, a custom block — is the same deterministic per-rule failure
     on every run, cache on or off, serial or sharded. *)
  let collect_project u =
    let failures = ref [] in
    let facts =
      List.filter_map
        (fun (name, collect, _) ->
          match collect u with
          | [] -> None
          | fs -> Some (name, fs)
          | exception e ->
              failures := (name, Printexc.to_string e) :: !failures;
              None)
        projects
    in
    (facts, List.sort compare !failures)
  in
  let rows = ref [] in
  let failures = ref [] in
  let withheld = ref [] in
  (* Fresh resolver read failures after a unit's analysis are that
     unit's degradation rows — its matching demanded the reads. Keyed so a
     cmi degrades the run once, at the unit that first hit it, whichever
     resolver its scope carried. *)
  let noted_cmi = Hashtbl.create 4 in
  (* The one assembly path: every admitted unit's contribution enters the
     report through this function, whether freshly analyzed or replayed
     from payload bytes — replay is recompute by construction. *)
  let absorb path (c : Report.contribution) =
    rows := (path, Report.Unit c) :: !rows;
    List.iter
      (function
        | Report.Offsets -> ()
        | Report.Resolution { cmi; reason } ->
            Hashtbl.replace noted_cmi (cmi, reason) ())
      c.degradations;
    List.iter
      (fun (rule, message) ->
        failures := { Report.rule; unit_path = path; message } :: !failures)
      c.failures
  in
  (* One entry's whole pass, so the per-entry [progress] tick below fires
     once per entry on every path — replayed, analyzed, or skipped. *)
  let pass entry =
    let path = Roster.Entry.source entry in
    let replayed =
      match unit_cache with
      | None -> None
      | Some c -> (
          match c.Unit_cache.load entry with
          | None -> None
          | Some bytes -> (
              match decode_payload bytes with
              | Some p -> Some (p, bytes)
              | None -> None))
    in
    match replayed with
    | Some (c, bytes) ->
        absorb path c;
        Option.iter (fun cap -> cap entry bytes) capture
    | None -> (
        match load entry with
        | Error sk -> rows := (path, Report.Skip sk) :: !rows
        | Ok u ->
            let c =
              match Unit.generated u with
              | Some _ as generated ->
                  (* The generated-unit gate: the unit admits, but no
                       finding may anchor in a file the user cannot
                       edit. Its facts stay in the universe — project-rule
                       [collect] runs on it — so the fact universe remains
                       complete; the classifying marker is recorded on the
                       row, so the reclassification is named in the report,
                       never an anonymous count. *)
                  let facts, cfailures = collect_project u in
                  {
                    Report.unit_name = Unit.name u;
                    generated;
                    kept = [];
                    audits = [];
                    suppressed = [];
                    notes = [];
                    dropped = 0;
                    degradations = [];
                    failures = cfailures;
                    facts;
                  }
              | None ->
                  let r = analyze ~kinds ~suppress u in
                  let facts, cfailures = collect_project u in
                  {
                    Report.unit_name = Unit.name u;
                    generated = None;
                    kept =
                      List.map (fun (rule, _, f) -> (Rule.name rule, f)) r.kept;
                    audits = r.unit_audits;
                    suppressed = r.unit_suppressed;
                    notes = r.unit_notes;
                    dropped = r.unit_dropped;
                    degradations =
                      (if r.unit_degraded then [ Report.Offsets ] else [])
                      @
                      (* The delta: failures not yet noted by this run.
                           [absorb] notes them right after, so the filter
                           is exactly "first seen at this unit". *)
                      List.filter_map
                        (fun ((cmi, reason) as failure) ->
                          if Hashtbl.mem noted_cmi failure then None
                          else Some (Report.Resolution { cmi; reason }))
                        (Naming.Scope.read_failures (Unit.scope u));
                    failures = List.sort compare (r.unit_failures @ cfailures);
                    facts;
                  }
            in
            absorb path c;
            (* Encode once, on demand: a plain run pays no Marshal of the
                 row itself. *)
            let bytes = lazy (encode_payload c) in
            (match unit_cache with
            | Some uc when storable c ->
                uc.Unit_cache.store entry (Lazy.force bytes)
            | Some _ | None -> ());
            Option.iter (fun cap -> cap entry (Lazy.force bytes)) capture)
  in
  List.iter
    (fun entry ->
      pass entry;
      Option.iter (fun tick -> tick ()) progress)
    (Roster.entries roster);
  (* Kind-gated rules over a kind-less roster are structurally silent on
     every unit; silence must be enumerated, never left to read as a
     clean corpus. One withheld row per
     selected kind-gated rule, in selection order, when no roster entry
     carries a stanza kind — the artifact walk and metadata-less unit
     files. The summary's [roster:] lines and [--explain-withheld] both
     render the channel. *)
  (match Roster.entries roster with
  | [] -> ()
  | entries when List.for_all (fun e -> Roster.Entry.kind e = None) entries ->
      List.iter
        (fun r ->
          if Rule.kind_gated r then
            withheld :=
              ( Rule.name r,
                "kind-gated; no unit in this lane carries a stanza kind" )
              :: !withheld)
        rules
  | _ -> ());
  let rows = List.rev !rows in
  let capable = Roster.project_capable roster in
  let project_names = List.map (fun (name, _, _) -> name) projects in
  (* The report phase: once, in the parent of whatever sharding produced the
     facts, over each rule's deterministic concatenation — roster order of
     units, emission order within a unit, whichever channel the facts
     arrived through. The gate is [Report.block_of], the same derivation
     every consumer page reads: a skip blocks every rule (the universal
     claim), an ambiguous unit name blocks every rule (the engine tabulates
     admitted names itself), a failed [collect] blocks that rule alone (its
     universe has a hole and the failure, exit 3, is already visible).
     Project findings answer to a reduced emit contract: the units are
     dropped by now, so no corroboration and no attribute suppression
     apply; ghost locations drop (counted), [keep] selects by the finding's
     own path in the view, and the fix promise is checked exactly as in
     [analyze]. A raising [report] is a rule failure at ["(workspace)"]. *)
  let project_findings = ref [] in
  let project_dropped = ref 0 in
  List.iter
    (fun (name, _, report) ->
      if Report.block_of ~capable ~rows name = None then begin
        let facts =
          List.concat_map
            (fun (_, row) ->
              match row with
              | Report.Skip _ -> []
              | Report.Unit c ->
                  Option.value (List.assoc_opt name c.facts) ~default:[])
            rows
        in
        let rule = Hashtbl.find rule_by_name name in
        match report facts with
        | fs ->
            if List.exists (breaks_promise rule) fs then
              failures :=
                {
                  Report.rule = name;
                  unit_path = "(workspace)";
                  message = "returned a fix but its meta promises Never";
                }
                :: !failures
            else
              List.iter
                (fun f ->
                  if (Finding.loc f).Location.loc_ghost then
                    incr project_dropped
                  else project_findings := (name, f) :: !project_findings)
                fs
        | exception e ->
            failures :=
              {
                Report.rule = name;
                unit_path = "(workspace)";
                message = Printexc.to_string e;
              }
              :: !failures
      end)
    projects;
  let project_findings = List.rev !project_findings in
  {
    Report.rows;
    project_names;
    capable;
    project_findings;
    project_dropped = !project_dropped;
    withheld_rules = List.rev !withheld;
    failures =
      List.sort
        (fun (a : Report.failure) b ->
          match String.compare a.unit_path b.unit_path with
          | 0 -> String.compare a.rule b.rule
          | c -> c)
        !failures;
    rules_selected = List.length rules;
    keep;
    severity_of;
    view = Report.make_view ~rows ~capable ~project_findings ~keep ~severity_of;
  }
