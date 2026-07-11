(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The pure analysis core: findings = f(rules, roster, load).

    {!run} folds the selected rules over the roster's units and produces a
    {!Report}. All IO lives outside: the driver supplies [load], and the engine
    only calls it — exactly once per entry, in an order consumers must not
    observe (parallel sharding may interleave), retaining no unit after
    analyzing it, so memory stays bounded on large workspaces. Given the same
    rules, roster, and [load] graph, the report is identical; parallel sharding
    and caching are implementation details that this contract forbids from being
    observable.

    {b Traversal and dispatch.} Per unit, one traversal per substrate: one
    [Tast_iterator] walk of the typedtree, one walk of the engine's own pre-PPX
    parse for attribute rules, one pass for text rules — over the unit's
    editable source and, when the unit has one, its paired interface source
    ({!Unit.interface_source}): a companion [.mli] is text-linted exactly as an
    interface-only unit's would be. Rules never own traversal. Dispatch is
    kind-indexed — per-node cost is O(rules subscribed to that node's kind), not
    O(all rules). Substrates are demand-gated: a substrate is decoded (see
    {!Unit}) only when a selected rule subscribes to it or the emit contract
    needs it — no source re-parse when no attribute rules are selected and no
    finding needs corroborating, no cmti decode when nothing needs interface
    annotations, and when every selected attribute rule declares its names
    ([Rule.attribute ?names]) no parse of a source that cannot spell one of
    them.

    {b The emit contract.} A finding returned by a callback is kept only if its
    location is (a) non-ghost, (b) inside the unit's own editable source file,
    (c) offset-consistent with that file's line index ({!Source.consistent}) —
    inconsistent findings degrade to line-anchored renderings without carets and
    their fixes to [Display] — and (d) when the unit's pre-PPX parse exists
    ({!Unit.parsetree}), corroborated by a node span in that parse: a finding
    can only anchor at a span that existed in the editable source, so a PPX that
    fabricates or splices locations cannot land a finding, while one that copies
    a whole user span onto generated code can still surface a finding
    {e at that user span} (deduplicated when the copies agree). In units whose
    editable source does not parse, (d) is waived: findings are kept under
    (a)–(c) alone, degrading as under (c), and the summary notes the reduced
    guarantee for that unit ({!Report.degraded}). Kept findings are paired with
    their rule's name and their locations' [pos_fname] rewritten to the unit's
    adapter-supplied path ({!Unit.path}); compiler-recorded paths are compared
    only against the unit's own recorded names for ownership check (b) — by
    basename, since recorded names may not be filesystem paths: a same-basename
    file in another directory is indistinguishable and owned — and never reach
    the total order, a renderer, or the filesystem. Related locations inside the
    linted unit are rewritten identically; one pointing elsewhere keeps its
    recorded name and renders location-only — recorded names may not be
    filesystem paths. Findings are deduplicated by (rule, location, message) —
    within a unit, and again across units over the sorted report, so duplicate
    roster entries for one source path (two artifact copies of one unit) report
    each finding once — and fixes in preprocessed units are downgraded [Safe] →
    [Unsafe]. Dropped findings are counted, never rendered. Text findings from
    the interface lane answer to the interface source instead: ownership (b) is
    its exact adapter-supplied path, consistency (c) is its line index,
    corroboration (d) never applies (the file is read directly, no PPX between),
    the path needs no rewrite, and the preprocessed-unit fix downgrade is
    skipped — the offsets are the interface's own bytes. This is the entire PPX
    story from a rule's point of view.

    {b Suppression and audit.} After the emit contract, findings are filtered
    against the unit's attribute directives ([Suppress]):
    [[\@litany.allow "rule: reason"]] hides matching findings in its scope,
    [[\@litany.expect "rule: reason"]] hides them and requires at least one.
    Matching is byte-span containment against the engine's own pre-PPX parse —
    the same demand-gated parse everything else shares, additionally demanded
    only when the source can spell a directive ([Suppress.spelled]); in a unit
    whose source does not parse, attribute suppression is unavailable and the
    unit is counted degraded. The innermost covering directive wins and each
    hidden finding is retained with its reason ({!Report.suppressed}), never
    rendered by a default view. Text-rule ([Rule.source]) findings are never
    attribute-suppressed — configuration selects their reports.

    Hygiene is engine-owned: the two audit rules [unused-allow] and
    [unfulfilled-expect] report directives that hid nothing, as ordinary warning
    findings anchored at the attribute, in the total order and the exit code. A
    well-formed allow whose rule ran and matched nothing carries a [Safe]
    deletion fix removing the attribute ([Suppress.Directive.deletion]); an
    unfulfilled expect wants the finding back, not the attribute gone, and ships
    none. Audits are gated on the named rule having run on that unit — named in
    [rules], locally dispatched, and not failed there; a directive naming a rule
    that is known (in [run]'s [catalog]) but did not run is silently inert,
    because absence of a finding is only evidence when the rule looked. A
    directive that can never match — unknown rule name (with a did-you-mean
    hint), an engine-owned audit name, a text rule (selected or not), a
    malformed payload — is audited unconditionally: that is a syntactic fact,
    not an absence claim. An offset-inconsistent finding (kept line-anchored
    under (c)) is matched by no directive — the offsets a directive's scope
    would test are the ones the emit contract distrusts — so its covering
    directive audits rather than silently claiming it. Audit findings answer to
    no directive (nothing suppresses the auditors), and no rule may take their
    names. Tombstone aliases ([Rule.meta]'s [renamed_from]) match with a
    per-unit rename note ({!Report.notes}).

    {b Rule failure isolation.} A callback that raises fails that rule on that
    unit only; every other rule and unit completes, and the report's exit code
    becomes 3. A rule whose meta promises [Fix.Never] and whose callback returns
    a fix fails the same way — the promise is checked here per emitted finding.
    The recorded failure message is the exception as printed by
    [Printexc.to_string]; byte-deterministic output therefore requires
    deterministic exception printers in rule code.

    {b Total order.} Report findings are sorted by (path, start byte offset,
    rule name, end byte offset, message) — byte-identical across runs,
    parallelism, and cache states. No consumer may depend on any other order. *)

(** {1:report Reports} *)

(** The result of one run. *)
module Report : sig
  (** The type for per-unit outcomes. Every roster entry has exactly one. *)
  type outcome =
    | Linted  (** Findings and facts; the ordinary case. *)
    | Facts_only
        (** Admitted, but the unit is generated (ocamllex, menhir, [(rule)]
            outputs): no findings in files the user cannot edit, but
            project-rule [collect] runs, so the fact universe stays complete.
            Yielded for units [Unit.generated] classifies — the
            [.ml-gen]/lex-yacc-marker rule, standing in until build systems can
            declare their generated outputs to the adapter. *)
    | Skipped of Unit.Skip.t
        (** Not admitted; the reason enumerated. A skip is also a fact-skip: any
            skipped roster unit blocks project rules. *)

  type failure = {
    rule : string;  (** The failed rule's name. *)
    unit_path : string;  (** The unit it failed on. *)
    message : string;  (** The exception, printed. *)
  }
  (** The type for isolated rule failures. *)

  (** The type for what blocks one project rule's [report]. The first three arms
      block every selected project rule (they are properties of the run);
      [Collect_failed] blocks the one rule whose universe has the hole. *)
  type project_block =
    | Not_capable
        (** The roster was not project-capable ({!Roster.project_capable});
            project rules never applied. *)
    | Incomplete of (string * Unit.Skip.t) list
        (** Some roster units skipped: the blocking (path, reason) pairs, in
            roster order. A project rule's claim is universally quantified, so
            one fact-skip blocks every project [report]. *)
    | Ambiguous of (string * string list) list
        (** Engine-detected: two distinct admitted units share one compilation
            unit name — (name, paths) pairs, names sorted, paths in roster
            order. Cross-module identity is keyed by unit name, so a duplicate
            collapses every name-keyed join; the engine tabulates admitted names
            itself and blocks every project [report] rather than let one report
            over a collapsed identity. *)
    | Collect_failed of string list
        (** This rule's [collect] raised on the named units (roster order): its
            own universe has a hole, so its [report] alone is blocked. The
            failure rows (exit 3) are the loud record; this arm keeps the
            disposition page honest about it. *)

  (** The type for one unit's reduced-guarantee claims. A degradation is not a
      skip; summaries count and itemize them ({!degraded}). *)
  type degradation =
    | Offsets
        (** The editable source does not parse: attribute rules, attribute
            suppression, and corroboration were unavailable, and typed findings'
            offsets may count preprocessed bytes — renderers must not excerpt
            against the editable bytes. *)
    | Resolution of { cmi : string; reason : string }
        (** Canonical-name resolution hit a cmi that exists but cannot be read
            ([Naming.Resolver.read_failures]) — rules mentioning names it
            defines match nothing. The row lands on the unit whose analysis
            first demanded the read, once per cmi; a {e missing} cmi is not a
            degradation. Offsets are unaffected — excerpts stay trustworthy. *)

  type t
  (** The type for run reports. A report stores one contribution row per roster
      entry — the same record the payload channels carry — plus the
      project-phase results; every accessor below is a derivation over that
      ledger, so the human page, the machine trailer, and {!demote} cannot
      disagree about what a unit contributed. *)

  val findings : t -> (string * Finding.t) list
  (** [findings rep] is the kept findings, each paired with its emitting rule's
      name, in the total order (path, start offset, rule name, end offset,
      message) — the order is the report's; [Finding.compare] supplies the
      non-rule keys. *)

  val iter_findings :
    t -> (rule:string -> severity:Rule.Severity.t -> Finding.t -> unit) -> unit
  (** [iter_findings rep f] calls [f] on each finding in {!findings} order with
      its emitting rule's name and its render-time severity, derived from the
      emitting rule's group ([Rule.Severity.of_group]). The allocation-free path
      renderers use: the flattened view is memoized once per report value. *)

  val units : t -> (string * outcome) list
  (** [units rep] is the outcome of every roster entry, keyed by source path, in
      roster order. Summaries derive their unit, skip, and facts-only counts
      from it. *)

  val suppressed : t -> (string * Finding.t * string) list
  (** [suppressed rep] is the findings hidden by [allow]/[expect] directives —
      (rule name, finding, reason) triples in the findings' total order,
      deduplicated like {!findings}. Each passed the emit contract and was then
      claimed by its innermost covering directive; the claiming directive's kind
      is carried on the row, so {!expected} is a filter of this list. Default
      views do not render them (the text renderer counts them in the summary
      line). *)

  val expected : t -> (string * Finding.t * string) list
  (** [expected rep] is the subset of {!suppressed} claimed by [expect]
      directives — same triples, same total order. The one consumer is the rule
      suites' golden helper, which applies these findings' fixes to produce the
      [.fixed] golden (the sole exception to "[--fix] never touches a suppressed
      or expected finding"); default views render nothing from it. *)

  val notes : t -> (string * string) list
  (** [notes rep] is the informational per-unit notes — (unit path, note) pairs
      in roster order, deduplicated per unit: the generated-unit
      reclassification markers, the tombstone rename warnings from suppression
      attributes naming a [Rule.renamed_from] alias, and the inert-directive
      notes from suppression attributes naming a project rule (project findings
      answer to configuration only in this release — the directive matches
      nothing and its audit is withheld, so the note is the enumerated silence).
      A note is neither a finding nor a degradation; summaries list them. *)

  val project_rules : t -> (string * project_block option) list
  (** [project_rules rep] is the per-rule project disposition — every selected
      project rule in selection order, [None] when its [report] ran over the
      complete universe, [Some block] naming exactly what blocked it. Empty iff
      no project rule was selected. The renderers' roster lines and the driver's
      [--explain-withheld] derive from it, and the engine's own report gate is
      the same derivation — the page and the gate cannot disagree. *)

  val withheld_rules : t -> (string * string) list
  (** [withheld_rules rep] is the kind-gated inactivity record — kind-gated
      local rules ([Rule.kind_gated]) in a run whose roster entries carry no
      stanza kind at all, structurally silent on every unit, so the silence is
      enumerated rather than read as cleanliness: (rule name, reason) pairs in
      selection order, the reason
      [kind-gated; no unit in this lane carries a stanza kind]. The summary
      prints one [roster:] line per entry and [--explain-withheld] spells them
      out. A withhold is not a failure: it does not affect {!exit_code}. *)

  val degradations : t -> (string * degradation) list
  (** [degradations rep] is the per-unit degradation claims — (unit path, claim)
      pairs in roster order, {!Resolution} rows deduplicated per cmi at the unit
      that first demanded the read. The claim is typed so consumers key on what
      actually degraded: the text renderer withholds excerpts for {!Offsets}
      units only — a {!Resolution} unit's offsets are fully verified. *)

  val degraded : t -> (string * string) list
  (** [degraded rep] is {!degradations} with each claim rendered as its prose
      note — the summary itemization. *)

  val failures : t -> failure list
  (** [failures rep] is the isolated rule failures, ordered by (unit path, rule
      name). Empty on a healthy run. *)

  val dropped : t -> int
  (** [dropped rep] is the number of findings the emit contract dropped —
      unowned or uncorroborated locations. Shown in the summary; a non-zero
      count is normal under PPX-heavy code. *)

  val rules_selected : t -> int
  (** [rules_selected rep] is the size of the selected rule set the run was
      given — [run]'s [rules], engine-owned audit rules not counted. The
      summary's denominator: a page reading [0 findings] means nothing without
      knowing how many rules looked. *)

  val exit_code : t -> int
  (** [exit_code rep] is the run's stable exit code: [3] if {!failures} is
      non-empty (rule failure dominates findings), else [1] if {!findings} is
      non-empty, else [0]. Exit [2] — refusal — is the driver's: it aborts
      before any report exists. *)

  val demote : path:string -> Unit.Skip.t -> t -> t
  (** [demote ~path skip rep] is [rep] with the unit at [path] demoted to
      [Skipped skip], pointwise on the ledger: the unit's whole contribution —
      findings, suppressed findings, notes, degradations — leaves every derived
      view, its outcome becomes the skip, and, because the project dispositions
      derive from the rows, every project rule moves to {!Incomplete} with the
      demoted unit among the blockers and project findings leave the page — a
      universal claim never outlives the universe it quantified over. The
      driver's end-of-run revalidation hook: admitted sources are re-digested at
      render, and a mismatch — the user edited during the run — demotes the unit
      with [Unit.Skip.Modified_during_run] rather than report findings against
      bytes that no longer exist. Rule {!failures} on [path] stay: they
      happened, and exit 3's dominance must not soften silently. A [path] that
      is no unit's own but anchors findings — an interface source of the text
      lane — loses exactly those findings, no outcome or disposition touched:
      the revalidation loop covers the [.mli] with the same call. A [path] with
      neither unit nor findings is a no-op. *)
end

(** One summary, one derivation. *)
module Summary : sig
  type t = {
    rules_selected : int;
    linted : int;
    facts_only : int;
    units : int;  (** [linted + facts_only]. *)
    findings : int;
    fixable : int;  (** The subset of [findings] carrying a fix. *)
    suppressed : int;
    skipped : int;
    skipped_by_reason : (string * int) list;
        (** ([Unit.Skip.slug], count) in the taxonomy's rank order. *)
    dropped : int;
    degraded : int;
    exit_code : int;
  }
  (** The type for report summaries: every aggregate count a report surface
      prints. *)

  val of_report : Report.t -> t
  (** [of_report rep] is the one aggregation both report surfaces derive from —
      the text renderer prints it and the json trailer serializes it
      field-for-field, so the human page and the machine channel cannot disagree
      on the truth set. *)
end

(** {1:payloads Per-unit result bytes}

    One admitted unit's whole contribution to a report can leave {!run} as
    opaque bytes and re-enter a later (or concurrent) run in place of loading
    and analyzing the unit. The bytes are an engine-owned codec — no other
    module reads them — and both replay channels share it, so warm-vs-cold and
    parallel-vs-serial byte-identity are one property, discharged once: the
    payload is the report's own per-unit contribution row, stored unchanged into
    assembly whichever way it was produced — replay {e is} recompute, and
    project facts inside it are already the per-fact Marshal frames the report
    phase consumes, so every mode hands the same bytes.

    - {b Cache} ({!Unit_cache}): the driver stores payloads under
      content-addressed keys ([Cache]); a replayed unit skips artifact decode
      and analysis entirely. The engine refuses to hand out payloads that must
      stay live — a unit with rule failures (the exception and exit 3 must
      recur, not fossilize) or one whose analysis first demanded a failing cmi
      read (its degradation note must track the still-broken state, and its
      position must stay warm/cold-identical) is analyzed and reported but never
      stored.
    - {b Workers} ([capture] on {!run}): a sharded driver runs one engine per
      worker process and wires every admitted unit's payload back to the parent,
      which replays them through one assembly pass over the full roster. Marshal
      is sound on both channels by their own contracts: cache keys include the
      binary digest, and a worker is a fork of the same binary image.

    A payload that fails to decode is a miss — the engine falls back to [load]
    and analysis — never an error. *)

module Unit_cache : sig
  type t = {
    load : Roster.Entry.t -> string option;
        (** [load entry] is the stored payload bytes for [entry], or [None] to
            compute. The driver owns key derivation and every IO concern; the
            engine only asks. Must be deterministic for the run. *)
    store : Roster.Entry.t -> string -> unit;
        (** [store entry bytes] offers [entry]'s payload for keeping.
            Best-effort: the engine never observes the outcome. Called at most
            once per entry, only for admitted units the engine deems replayable
            (see the section preamble). *)
  }
  (** The type for driver-supplied payload stores. *)

  val plausible_payload : string -> bool
  (** [plausible_payload bytes] is [true] iff [bytes] begins with the engine's
      payload frame magic. A cheap driver-side check: bytes failing it can never
      replay, so a driver keeping cache statistics should count them a miss
      instead of a hit before handing them to the engine (which quietly
      recomputes on any undecodable payload either way). *)
end

(** {1:running Running} *)

val audit_rules : string list
(** [audit_rules] is the engine-owned audit rule names —
    [["unused-allow"; "unfulfilled-expect"]]. No catalog rule or alias may claim
    them ({!run} raises [Invalid_argument]), no directive suppresses their
    findings, and they are not selection vocabulary — drivers use this list to
    refuse [--select]/[--ignore] of an audit name with an honest message instead
    of "unknown". *)

val run :
  ?keep:(path:string -> rule:string -> bool) ->
  ?unit_cache:Unit_cache.t ->
  ?capture:(Roster.Entry.t -> string -> unit) ->
  ?progress:(unit -> unit) ->
  rules:Rule.t list ->
  catalog:Rule.t list ->
  roster:Roster.t ->
  load:(Roster.Entry.t -> (Unit.t, Unit.Skip.t) result) ->
  unit ->
  Report.t
(** [run ~rules ~catalog ~roster ~load ()] analyzes every entry of [roster] with
    [rules] and is the run's {!Report.t}.

    [rules] is the already-selected set — selection, configuration, and per-rule
    options resolve in the driver ([Rule.select]). Duplicate rule names are a
    programmer error: raises [Invalid_argument] before any unit loads, as does a
    rule (or tombstone alias) in [rules] or [catalog] claiming an engine-owned
    audit name ([unused-allow], [unfulfilled-expect]). Checked in that order:
    the duplicate check over [rules] first, then audit-name claims over
    [catalog] then [rules], each rule's name before its aliases — a set with
    both defects reports the duplicate.

    [catalog] is the rule universe suppression validates directive names against
    — the driver passes every rule it knows, selected or not. A directive naming
    a catalog rule outside [rules] is known-but-not-run: silently inert, its
    audit withheld (a tombstone alias still notes the rename — the attribute
    needs updating regardless of selection); text rules are the exception and
    audit from the catalog even unselected, since they can never match under any
    selection. A directive naming a {e project} rule — selected or not — is
    inert with its audit withheld too, but never silently: project findings
    answer to configuration only in this release, and the directive is named in
    a per-unit note ({!Report.notes}) so the withheld audit does not read as a
    working suppression. A name in neither is unknown and audited
    unconditionally with a did-you-mean hint over the catalog's names and
    aliases. The label is required because no default is safe to guess: a
    catalog narrower than what the driver knows mislabels known-rule directives
    as unknown-rule audit findings. A driver whose whole universe is the
    selected set — a rule-test harness, a single-rule invocation — passes
    [~catalog:rules] and says so.

    [keep] is per-path report selection — the config file's [per-path.ignore]
    ring, defaulting to keep-everything. It is selection of {e reports}, never
    of analysis: every unit still loads and runs, its project facts are
    unaffected, and a finding for which [keep ~path ~rule] is [false] — [path]
    the adapter-supplied path of the file the finding is in (the unit's own for
    every lane but the interface text lane, whose findings carry the interface
    source's), [rule] the emitting rule's name, audit rules included — never
    enters the report: not rendered, not counted, not in {!Report.dropped} (that
    is the emit contract's channel). Deselection is silent by design, exactly
    like an unselected rule. [keep] must be pure and deterministic for the run.

    [unit_cache] is the per-unit payload store ({!Unit_cache}). Per entry, the
    engine asks [unit_cache.load] first: decodable bytes replay the unit —
    [load] is never called, no substrate is decoded, and the unit's report
    contribution is byte-identical to a recomputed one, because replayed and
    fresh results enter assembly through the same path. On a miss the unit is
    loaded and analyzed as usual and, when the result is replayable (admitted,
    no rule failures, no first-demanded cmi read failures), offered back through
    [unit_cache.store]. [keep] and the exit law are applied live at assembly on
    both paths, so a stored payload is selection-neutral. Skips are never
    stored: admission stays cheap and its inputs (build currency, file presence)
    stay live.

    [capture] is the sharding channel: it is called exactly once per admitted
    unit — [Linted] and [Facts_only] outcomes, replayed or fresh — with the
    unit's payload bytes, in roster order. A worker process runs [run] over its
    shard's sub-roster with [capture] wiring payloads to the parent; the parent
    then runs [run] over the full roster with a [unit_cache] that serves those
    payloads and a [load] that answers the workers' skips, producing the
    canonical report in one assembly pass. Skipped entries are not captured;
    their outcome travels in the report's {!Report.units}.

    [progress] is called exactly once per roster entry, after that entry's
    outcome is settled — replayed, analyzed, or skipped — in roster order. It is
    the driver's meter tick and nothing more: the engine neither draws nor reads
    a clock, and a run with [progress] produces a report byte-identical to one
    without.

    [load] joins one entry (typically {!Unit.load} partially applied to the
    run's resolver); the engine calls it exactly once per entry, in an
    unspecified order, and treats its answers as the definition of the unit
    universe. It must be deterministic for the duration of the run. A loaded
    unit that [Unit.generated] classifies takes the [Facts_only] outcome: no
    finding-producing rule runs on it and it contributes no findings —
    project-rule [collect] still runs, so the fact universe stays complete; the
    classifying marker ([Unit.generated]'s [why]) is recorded as a per-unit note
    ({!Report.notes}), so the reclassification is named in the report, never an
    anonymous count — the marker scan is lexical and a quoted directive line in
    a hand-written file classifies too.

    {b Project rules.} Per admitted unit — [Linted] and [Facts_only] alike —
    each selected project rule's [collect] runs (fresh path) or replays from the
    unit's payload: facts ride the payload channels exactly like findings, so a
    cache hit or a worker shard contributes to the fact universe without
    re-collecting, and the sharded parent's assembly pass is where [report] runs
    — once per project rule, over that rule's facts concatenated in roster order
    of units and emission order within a unit. Each fact is one Marshal frame,
    sealed inside [collect] by [Rule.project]'s constructor — every payload
    channel and the report phase hand the same bytes, so an unmarshalable fact
    (a closure, a custom block) is the same deterministic per-rule [collect]
    failure on every run, cache on or off, serial or sharded. [report] executes
    per rule only when nothing blocks it ({!Report.project_rules} is the same
    derivation as the gate): the roster must be project-capable
    ({!Roster.project_capable}), no entry's outcome [Skipped] — a project rule's
    claim is universally quantified, so one fact-skip blocks every project
    [report] — and no two admitted units may share a compilation unit name (the
    engine tabulates admitted names and blocks every project [report] on a
    duplicate rather than let one report over a collapsed identity); local rules
    and [collect] are never blocked. A raising [collect] is a rule failure on
    that unit and additionally blocks that rule's own [report] (its universe has
    a hole); a raising [report] is a rule failure at ["(workspace)"]. Project
    findings answer to a reduced emit contract — by [report] time the units are
    dropped, so there is no corroboration and no attribute suppression (a
    directive naming a project rule is inert but never silent — the [catalog]
    paragraph above names it in a per-unit note; config's [keep] ring applies,
    keyed by the finding's own path in the view): ghost locations are dropped
    and counted, the fix promise is checked as everywhere, and the finding's
    location must already name an adapter-supplied path — the rule carries it
    through its facts.

    The trailing [()] keeps optional inputs erasable — [keep], [unit_cache], and
    [capture] today. *)
