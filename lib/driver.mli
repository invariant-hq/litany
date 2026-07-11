(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The check driver: the engine pass, the [--fix] convergence loop, the
    admission listing, the report surfaces, and their supporting lanes (the
    result-cache wiring and the process workers).

    This is driver machinery, not SDK vocabulary — reachable as [Driver], never
    re-exported by [open Litany]: [bin/] is thin composition — cmdliner terms,
    flag validation, adapter selection — while the run itself lives here with
    the library. Behavior is governed by [doc/dev/design.md] (Fixes); the exit
    codes are the stable contract of {!section:exit}. *)

(** {1:exit Exit contract and refusals}

    0 clean, 1 findings, 2 could-not-run, 3 internal error. The codes live here
    because they are the driver's results ({!Engine.Report.exit_code} already
    owns 0/1); the cmdliner-facing mapping (eval-code folding, the documented
    exits table) stays in [bin/]. *)

val exit_ok : int
(** Exit 0: the run completed with no findings. *)

val exit_findings : int
(** Exit 1: the run completed with findings. *)

val exit_refusal : int
(** Exit 2: Litany could not run — adapter error or unusable invocation. *)

val exit_internal : int
(** Exit 3: an internal error — a rule failed. *)

val refuse : ('a, Format.formatter, unit, int) format4 -> 'a
(** [refuse fmt ...] prints [litany: <message>] on standard error and is
    {!exit_refusal}. Nothing runs after a refusal is printed; the caller returns
    the code. *)

(** The type for how a run ended: it completed, or it refused mid-flight (a
    post-fix build failure). *)
type stop = Completed | Refused

val exit_of : stop -> bug:bool -> Engine.Report.t -> int
(** [exit_of stop ~bug rep] is the run's exit code under the declared precedence
    law: refusal [2] > internal [3] > findings [1] > clean [0]. A [Refused] stop
    is {!exit_refusal} regardless of [bug] — the refusal's remedy must run
    first, and the bug recurs on the re-run; a [Completed] stop with [bug] (a
    fixer constructed an invalid fix anywhere in the run) is {!exit_internal} —
    a rule that constructs invalid fixes must not hide behind a later clean
    pass; otherwise the code is the report's own ([Engine.Report.exit_code]).
    Every return of {!run_check} passes through this function, so the precedence
    is declared here, never emergent from which return fires first — with one
    refinement on top: the all-skip escalation turns a [Completed] run whose
    code would otherwise be [0] into a refusal, so it refuses silent success
    without ever softening a louder exit. *)

val under_build : string -> bool
(** [under_build path] is [true] iff [path] has a [_build] component — the path
    test behind the driver's build-scoped fix refusal ([--fix] never writes into
    a build tree), which stays at its call site. *)

(** {1:cache Result-cache wiring} *)

(** The result-cache wiring: key derivation over {!Cache}'s five components, the
    {!Engine.Unit_cache} adapter, run statistics, and the end-of-run sweep.

    The cache is advisory and driver-owned. This module computes the digests the
    cache domain refuses to compute itself — cmt, cmti, source, config, and
    binary — and decides which entries are keyable at all: an entry with a
    preprocessed source (the Derived-witness lane digests the pp file, which is
    not a key component) or without a cmt is never cached and simply recomputes.
    The five components are populated as:

    - [cmt_digest]: BLAKE128 of the cmt bytes, with the cmti's digest appended
      when the entry names one — the cmti is a real semantic input:
      interface-demanding rules ([missing-printer],
      [suspicious-unused-module-binding]) and the project rules' fact collection
      read it;
    - [source_digest]: the adapter-supplied source path, NUL, BLAKE128 of the
      source bytes — the path is semantic (findings anchor at it; ownership
      compares its basename) — then the entry's roster metadata triple (library,
      visibility, kind: project facts bake the root policy in and kind-gated
      rules read the same fields, so flipping a library public must miss) and,
      when the entry names a readable interface source, its path and the
      BLAKE128 of its bytes (the interface text lane — fixing an [.mli] must
      miss, not replay its findings);
    - [config_fingerprint]: the raw bytes of the workspace [litany] file (or
      empty), NUL, the run's build-currency verdict — admission consults
      [build_current], so it keys;
    - [selected_rules]: the configured selection's rule names;
    - [binary_digest]: BLAKE128 of the running executable. *)
module Result_cache : sig
  type t
  (** The type for one run's cache context: the workspace handle plus the
      run-constant key components and the hit/miss/store counters. Shared with
      forked workers, whose copies are merged back with {!absorb_counts}. *)

  val setup :
    cache_dir:string option ->
    no_cache:bool ->
    root:string ->
    rules:Rule.t list ->
    t option
  (** [setup ~cache_dir ~no_cache ~root ~rules] is the run's cache context, or
      [None] when the run is uncached: [no_cache] was passed, no cache location
      resolves ({!Cache.resolve_root} over [cache_dir], [LITANY_CACHE_DIR], the
      XDG fallbacks), or the running binary cannot be digested. Reads the
      [litany] file under [root] for the config fingerprint — byte-identical to
      what the config loader ([Cli_config] in [bin/]) parses. *)

  val unit_cache :
    t ->
    build_current:bool ->
    snapshots:(string, Source.t) Hashtbl.t ->
    baselines:(string, string) Hashtbl.t ->
    Engine.Unit_cache.t
  (** [unit_cache t ~build_current ~snapshots ~baselines] is the engine adapter
      for one pass. On a hit the driver's [load] never runs, so the adapter
      fills the driver's per-unit tables itself from the bytes it read to derive
      the key: the render/revalidation snapshot and the fix-baseline digest
      (BLAKE128 — [Apply.file] accepts either digest algorithm). Key derivation
      is memoized per pass, so [store] never re-digests what [load] digested.
      Stored bytes that fail the engine's payload frame check
      ({!Engine.Unit_cache.plausible_payload}) count as a miss, never a hit —
      they cannot replay, and the recompute re-stores the entry. *)

  val absorb_counts :
    t -> hits:int -> misses:int -> stores:int -> Cache.Key.t list -> unit
  (** [absorb_counts t ~hits ~misses ~stores keys] folds a worker's counters and
      hit keys into [t] — the parent's side of the shard wire. *)

  val counts : t -> int * int * int
  (** [counts t] is [(hits, misses, stores)] so far — a worker's side of the
      wire. *)

  val hit_keys : t -> Cache.Key.t list
  (** [hit_keys t] is the keys this run's loads hit — the worker's side of the
      wire; the parent's sweep stamps them. *)

  val finish : t -> stats:bool -> unit
  (** [finish t ~stats] runs the end-of-run sweep — stamping this run's hits,
      evicting entries unread past [Cache.max_age], collecting orphaned
      workspaces — and, when [stats], prints one summary line on standard error
      ([litany: cache: H hits, M misses, S stored, E evicted]). Standard output
      never varies with cache state; the stats line is diagnostic and opt-in. *)
end

(** {1:parallel Process workers} *)

(** The check driver's process workers: shard the roster over [N] forked
    children, wire per-unit payloads back, and replay them through one parent
    assembly pass.

    Mechanism (chosen by benchmark — [doc/dev/design.md] (Result_cache and
    parallelism)): worker processes, never domains — the compiler's parser front
    end ([Lexer]/[Docstrings]) is module-global state and crashes
    deterministically under concurrent parse, which the emit contract's
    corroboration demands on nearly every unit. Fork + pipe: a child is the same
    binary image, so the Marshal wire cannot decode across layouts; results
    cross once per shard.

    Sharding is size-weighted (each entry goes to the least-loaded shard by
    accumulated cmt bytes — a benchmarked refinement over round-robin, whose
    slowest shard was the wall) and order-preserving within a shard. The
    assignment is unobservable: the parent replays per-entry payloads through
    the engine's single assembly pass over the full roster, so the page is
    byte-identical across every [-j] value — the same property, discharged by
    the same code path, as the cache's warm-vs-cold identity.

    A crashed or garbled child loses exactly its shard: the parent reports it on
    standard error, its entries become counted skips, every other shard's
    results land, and the exit law is the report's own. *)
module Parallel : sig
  val default_jobs : unit -> int
  (** [default_jobs ()] is the default worker count:
      [Domain.recommended_domain_count ()] — the runtime's estimate of usable
      cores. *)

  val check :
    progress:Progress.t ->
    jobs:int ->
    cache:Result_cache.t option ->
    rules:Rule.t list ->
    catalog:Rule.t list ->
    keep:(path:string -> rule:string -> bool) option ->
    roster:Roster.t ->
    build_current:bool ->
    (Engine.Report.t * (string, Source.t) Hashtbl.t) option
  (** [check ~progress ~jobs ~cache ~rules ~catalog ~keep ~roster
       ~build_current] runs the sharded lane and is the report plus the
      path→source snapshot table (render excerpts and end-of-run revalidation),
      or [None] when the lane does not apply ([jobs < 2] after clamping to the
      entry count) — the caller then runs the serial lane. Children load and
      store through [cache] exactly as a serial run would; their counters and
      hit keys are folded back into [cache] for the parent's sweep and stats.
      Each child reports its finished units to [progress] over one shared
      non-blocking pipe, which the parent drains while it waits on each shard's
      result. *)
end

(** {1:run The run} *)

val findings_fingerprint : (string * Finding.t) list -> string
(** [findings_fingerprint findings] is a stable digest of the finding multiset —
    (rule name, anchor path, byte span, message) per finding, order-independent,
    duplicates counted. The [--fix] convergence loop fingerprints each pass's
    kept findings and stops honestly when a pass reproduces an earlier pass's
    fingerprint: two passes with equal fingerprints present the same lint state
    to the fix planner, so applying again could only reproduce the repeat — a
    repeat of the immediately preceding pass means the applied fixes resolved
    nothing, a repeat of an earlier one means antagonistic fixes are undoing
    each other. *)

val listing : Roster.t -> build_current:bool -> unit
(** [listing roster ~build_current] is the [--list-units] surface: load every
    entry, print units and skips in (source, artifact) order, then the counted
    summary and the roster's project-capability line. *)

(** The report formats. [Text] is the human page on stdout; the three machine
    formats render the report page only — the fix narration and the admission
    listing speak the text surface, so the composition root refuses them under
    [--fix] and [--list-units] up front. *)
type format = Text | Compiler | Json | Github

type fix = { unsafe : bool; corrections : string option }
(** The type for the fix posture: [Some { unsafe; corrections }] applies fixes
    after each pass, [unsafe] extending application to behavior-changing fixes.
    An unsafe-without-fix run is unrepresentable.

    [corrections] selects the fix sink. [None] writes the sources directly — the
    terminal lanes only: inside dune litany never writes a source, and the
    composition root refuses [--fix] at every in-dune vantage but the
    corrections one. [Some dir] is that lane, the sandboxed dune action (dune
    lang 3.23 sandboxes every user rule): no source is written — each file's
    fixes run the same in-memory pipeline ({!Apply.correct} under the admission
    digest baseline, freshly re-checked against the real source bytes) and the
    fixed bytes land at [dir/<source path>.corrected], [dir] being the sandbox
    mirror of the build context root, so dune pairs each corrected file with the
    source it corrects at action teardown, shows the diff, fails the build, and
    registers promotion — [dune promote] is the writer, and the next build
    re-lints. The run is one pass and the exit contract shifts: at least one
    correction written → exit 0 whatever the report says (dune processes
    corrections only from actions that exit 0, and the diffs already fail the
    build); none written → the normal law. The proposal note always names
    [(corrections produce)]: litany cannot see the invoking stanza, and without
    that field dune discards the corrected files silently. *)

val run_check :
  progress:Progress.t ->
  rebuild:(unit -> (Roster.t, Adapter.Dune.error) result) option ->
  format:format ->
  jobs:int option ->
  cache:Result_cache.t option ->
  Roster.t ->
  build_current:bool ->
  rules:Rule.t list ->
  catalog:Rule.t list ->
  keep:(path:string -> rule:string -> bool) option ->
  fix:fix option ->
  explain_withheld:bool ->
  int
(** [run_check ~progress ~rebuild ~format ~jobs ~cache roster ~build_current
     ~rules ~catalog ~keep ~fix ~explain_withheld] is the run, and its exit code
    under {!exit_of}'s precedence law. The run-spanning invariant: each pass is
    a complete run over a current roster, and a re-run continues converging —
    nothing carries between invocations but the tree itself.

    [progress] is the run's meter ({!Litany.Progress}): the driver counts each
    pass over the roster into it — a [--fix] pass is labelled by its number, a
    rebuild between passes shows as a phase — and clears the line before
    anything is printed. A meter that does not draw makes every call a no-op, so
    the run is byte-identical with and without one.

    [jobs] is the requested worker count ([None] defaults to the machine's core
    estimate); the decision — defaulting and the [--fix] serial clamp — lives
    here, beside the invariant it guards, so a thin bin composing this driver
    can never send a fix run down the sharded lane (an explicit [jobs > 1] under
    [fix] is noted on standard error and ignored).

    [rebuild] is the build capability: how litany re-runs this roster's build,
    when it can (the shell dune adapter lane). A lane converges iff it knows its
    build — [None] (the walk, unit-file, no-build, and in-action lanes) runs
    exactly one pass and says so; the illegal converge-without-build combination
    is unrepresentable.

    Without [fix]: one engine pass (sharded when the worker count exceeds 1),
    end-of-run revalidation (each admitted source re-read at render; a unit
    whose bytes changed since analysis is demoted to a counted
    modified-during-run skip), then the report page in [format] — plus the
    withheld explanation when [explain_withheld]. With [fix]: apply the
    findings' fixes after each pass; with [rebuild] convergence spans builds —
    rebuild, re-join, re-lint, deferred conflict losers picked up on later
    passes, capped at 3 passes. Convergence must observe progress: a pass whose
    finding multiset reproduces an earlier pass's ({!findings_fingerprint})
    stops the loop with the repeat named — no-progress or oscillating fixes —
    and never advises a re-run that cannot converge. A post-fix build failure
    stops the run with the applied-fix list and the exact stderr line scripts
    grep for ([files were modified; git diff shows the applied fixes]) — a
    refusal, so {!exit_of} yields {!exit_refusal} even when a fixer bug was
    latched. A non-empty roster of which nothing was analyzed — every unit
    skipped — renders the page (the skip listing is the diagnosis) and then
    escalates to a refusal — a store that yields zero analyzed units must never
    read as success — instead of reading as quietly green: the all-wrong-magic
    single-generation store refuses naming both compiler versions; every other
    all-skip mix refuses with the skip breakdown and the remedy per kind. The
    escalation claims only a run that would otherwise exit {!exit_ok} — failures
    and findings keep their own, louder exits. An empty roster stays the honest
    empty report, exit 0. *)
