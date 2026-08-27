(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Adapters: how build systems reach the core.

    An adapter produces one value — a {!Roster.t} — and nothing of it crosses
    into the core: a finding's validity never depends on who produced the
    artifact, because per-unit witnesses gate every join. The built-in adapters
    are {!Dune} (the zero-config default), {!Walk} (the bare artifact walk,
    adapter of last resort), and {!Unit_file} — the codec of the one interface
    any other build system targets. [litany unit] inside the build is the
    degenerate one-unit case: its argv is the roster, assembled by the driver
    without this module.

    Adapters are the IO shore of the input side: {!Dune} spawns processes and
    {!Walk} reads directories, while {!Unit_file} is a pure codec and the driver
    does its reading and writing. Each adapter is also responsible for the
    resolver's cmi search path ({!Roster.cmi_dirs}): dune supplies library
    directories from its own description, the walk supplies the directories it
    walked, and a unit file may carry a [cmi-dirs] form. *)

(** {1:unit_file The unit file} *)

(** The unit-file codec: the serialization of a roster.

    Canonical s-expressions (csexp) — atoms are length-prefixed raw bytes, so
    any filename round-trips losslessly, and csexp is the ecosystem's machine
    format (the merlin protocol, a build system's own reports). A file is one
    [(litany-units 1)] version header, an optional [(complete false)] form, an
    optional [(cmi-dirs <dir>...)] form, then one form per unit:

    {v
    (unit (source lib/foo.ml) (cmt _build/default/lib/.foo.objs/byte/foo.cmt)
          (cmti ...) (pp-source ...) (intf-source lib/foo.mli) (library foo)
          (public true) (kind lib))
    v}

    Only [source] and one of [cmt]/[cmti] are required in a [unit] form; unknown
    fields are errors — the schema is closed. [(complete false)] is the honest
    partial producer's form — a changed-files-only file must carry it; absent,
    the file claims the producer's whole universe. A complete file that supplies
    [library], [public], and [kind] for every unit decodes as a project-capable
    roster: project rules work outside dune. A [unit] form without [public]
    decodes with [Unknown] visibility. *)
module Unit_file : sig
  type error = {
    offset : int;  (** Byte offset of the offending form or atom. *)
    reason : string;  (** What was expected there. *)
  }
  (** The type for decode errors — malformed csexp, a missing or unknown field,
      a version this Litany does not read. *)

  val decode : string -> (Roster.t, error) result
  (** [decode bytes] is the roster [bytes] serializes, or the first error.
      Completeness ({!Roster.complete}) defaults to [true] — a unit file claims
      to enumerate the producer's whole universe unless it carries
      [(complete false)]; stale entries surface as skips at join time, never as
      findings. *)

  val encode : Roster.t -> string
  (** [encode r] is [r] as unit-file bytes, decodable by {!decode} to an equal
      roster — including the completeness bit: an incomplete [r] is written with
      [(complete false)]. The bytes are canonical: field order fixed, one form
      per line, byte-identical across runs for equal rosters.
      [litany units --save] writes it; [--dump] pretty-prints the human sexp
      form instead.

      Raises [Invalid_argument] if two entries of [r] share a source path — such
      a roster has no serialization {!decode} accepts. *)

  val pp_error : Format.formatter -> error -> unit
  (** [pp_error ppf e] formats [e] with its byte offset for the refusal message.
  *)
end

(** {1:dune The dune adapter} *)

(** The built-in default: zero config under dune.

    One subprocess per check pass: [dune build --root . @check] (skipped by
    [--no-build]; [@check] materializes cmt/cmti without linking), with the
    linted root as working directory and dune's root pinned there, so a
    workspace nested under another dune project never root-walks to the
    outer one. The spawn is bounded in memory — at most 8 MiB of transcript
    is retained for failure classification (beyond it, classification
    degrades to the generic refusal — the user saw the stream either way) —
    and deliberately unbounded in time: a legitimate build may be
    arbitrarily long, streams to the user, and answers to Ctrl-C. Beside a
    running watch server the build {e forwards}: a secondary dune hands the
    request to the lock holder instead of fighting it, so a check pass
    composes with a live [dune build --watch].

    Everything else is read from the build tree dune already materialized —
    no [dune describe], no lock, no second subprocess. The artifact walk of
    the default context is the enumeration; each unit's stanza is recovered
    from its object directory's name ([.NAME.objs] a library, [.NAME.eobjs]
    an executable-family stanza — dune's own naming, not a guess); a
    tolerant s-expression scan of the stanza directory's [dune] file
    classifies it (library visibility from [(public_name ...)], [Test]
    against [Executable] from the stanza names) — when the scan cannot
    answer, the entry carries [Roster.Unknown] or no kind: unknown is
    stated, never guessed. External dependencies' cmi search dirs come from
    the dune-pkg store beneath [_build/_private]; a workspace without a
    store contributes none and name resolution degrades per the resolver's
    contract. After a green [@check] the walk finds exactly what describe
    used to report, plus the [(test)] stanzas describe always omitted; under
    [--no-build] on a dirty tree a never-built module is silently absent —
    the default (forwarded, near-instant beside a watch) build closes that
    gap. A stale walk costs witness-gated skips, never findings.

    Two dune-generated shapes are excluded from the roster wholesale: units
    whose stanza directory sits inside a dot directory ([.NAME.inline-tests]
    runner harnesses — admitting them mints duplicate-source entries), and
    the per-stanza executable alias module ([dune__exe.ml-gen], compilation
    unit [Dune__exe] for every executable-family stanza) whose name collides
    by construction and which carries nothing the project rules need.
    Library alias modules stay: library names are unique per workspace. *)
module Dune : sig
  (** The type for dune-adapter refusals. Each maps to exit 2 with the
      documented remedy; nothing runs after one. *)
  type error =
    | Dune_missing
        (** No dune on PATH. Remedy: [--units] or [--cmt-root] for artifacts
            built elsewhere. *)
    | Build_failed
        (** [dune build @check] failed; its errors already streamed through.
            Lint presupposes a building project. *)
    | No_check_alias of string
        (** The named context is not merlin-enabled, so [@check] does not exist
            there. Remedy: lint the default context. *)

  val roster :
    ?progress:Progress.t ->
    ?build:bool ->
    root:string ->
    unit ->
    (Roster.t, error) result
  (** [roster ~root ()] is the roster of the dune workspace at [root] —
      complete, with ownership metadata from the build tree's own layout and
      the cmi search path from the walked object directories plus the
      dune-pkg store. [build] (defaults to [true]) runs [dune build @check]
      first; [false] is [--no-build], where stale artifacts surface as
      skips and never-built modules are absent. Only the build spawns dune;
      its output streams through to the user before this function returns.
      The roster read itself takes no lock and asks dune nothing, so it
      runs beside a live watch server.

      [progress] names each of the two stretches this function spends its
      time in — the build, the build-tree read — on the caller's meter, and
      keeps its clock moving while dune runs; dune's own output takes the
      line back whenever it prints. Defaults to a meter that draws
      nothing. *)

  val pp_error : Format.formatter -> error -> unit
  (** [pp_error ppf e] formats [e]'s refusal message with its remedy. *)
end

(** {1:walk The artifact walk} *)

(** The adapter of last resort: [litany check --cmt-root DIR].

    Pairs artifacts with sources by the Direct witness alone. No ownership
    metadata and no completeness assertion: local rules only, and the summary
    says [roster: none (project rules unavailable)]. *)
module Walk : sig
  (** The type for walk refusals. *)
  type error =
    | Root_missing of string
        (** The named directory does not exist or cannot be read. *)

  val roster : cmt_root:string -> source_root:string -> (Roster.t, error) result
  (** [roster ~cmt_root ~source_root] walks [cmt_root] for [.cmt]/[.cmti] files,
      pairs each with its candidate editable source under [source_root] by unit
      name, and is the resulting incomplete roster with [cmi_dirs] set to the
      walked directories. Pairing prefers the mirrored path (the artifact's
      directory under [source_root]); the by-basename fallback is
      proximity-scoped — only candidates sharing the longest leading path prefix
      with the artifact's directory qualify, and never outside the artifact's
      scope: its innermost enclosing directory strictly below [source_root]
      holding a project marker ([dune-project], [.git], or a [*.opam] file) when
      its ancestry has one, its {e top-level subtree} of the walked root
      otherwise — so an artifact in one project cannot steal a same-named source
      from an unrelated one (multi-project stores hold several copies of the
      same unit names), including projects nested under a shared parent segment
      ([duniverse/*], [vendor/*]) when they carry markers; a marker-less layout
      is scoped by top-level subtree only, which is a weaker guarantee than
      "package". An artifact whose scope offers no candidate gets no source and
      skips missing-source at join time. Dangling symlinks are skipped silently
      — normal in artifact directories; a candidate whose pairing is wrong costs
      a skip at join time, never a finding. *)

  val pp_error : Format.formatter -> error -> unit
  (** [pp_error ppf e] formats [e]'s refusal message with its remedy. *)
end
