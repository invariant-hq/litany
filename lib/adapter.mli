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
    format ([dune describe], the merlin protocol). A file is one
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

    Two subprocesses per check pass: [dune build --root . @check] (skipped by
    [--no-build]; [@check] materializes cmt/cmti without linking), then
    [dune describe workspace --format csexp --lang 0.1 --with-deps --root .]
    once — both with the linted root as working directory and dune's root pinned
    there, so a workspace nested under another dune project never root-walks to
    the outer one. Both spawns are bounded: the forwarded build retains at most
    8 MiB of transcript for failure classification (beyond it, classification
    degrades to the generic refusal — the user saw the stream either way), the
    describe reply is capped at 256 MiB and the whole describe spawn at 600
    seconds; a violated bound terminates the child — TERM, a two-second drain
    grace, then KILL, always reaped — and refuses with the reason. Child stderr
    goes through a temp file, never a second pipe, so no two-pipe-deadlock
    exists to manage. The kill is of the direct pid only, not the process group:
    a timed-out describe's own descendants are dune's to reap — a brief survival
    is the accepted risk. The build spawn deliberately has no timeout: a
    legitimate build may be arbitrarily long, streams to the user, and answers
    to Ctrl-C. The roster is the union of the describe reply and an artifact
    walk of the context's build directory for artifacts belonging to no
    described module — [(test)] stanzas do not appear in describe even though
    [@check] builds them; walked-only units join under the ordinary witness and
    are counted. A walked unit whose artifact directory belongs to a
    [(test ...)]/[(tests ...)] stanza of the scanned [dune] files carries that
    stanza's ownership ([Roster.Test], the stanza name as library), so a tree
    with tests stays project-capable; other walked-only units carry no ownership
    metadata. Dune's generated per-stanza executable alias module
    ([dune__exe.ml-gen], compilation unit [Dune__exe] for every stanza) is
    excluded from the roster — described or walked — because its name collides
    by construction across stanzas and it carries nothing the project rules need
    (no exports; references only its own stanza's modules, which are roots
    themselves). Library visibility comes from a tolerant s-expression scan of
    the workspace's [dune] files for [(public_name ...)], validated against the
    roster by library name; when the scan cannot answer, the entry carries
    [Roster.Unknown] — unknown is stated, never guessed private. *)
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
    | Lock_held of int option
        (** Another dune instance holds the project lock — a watch server, a
            parallel one-shot build, or a wedged dune — so [dune describe]
            cannot run beside it; the payload is the holder's pid when dune's
            own error named one. The refusal is journey (b)'s (design doc §1):
            lint through the server (the in-build [@lint] rule, with [@lint]
            among the server's aliases) or capture a roster once and lint beside
            it ([litany check --no-build --units FILE]). *)
    | No_check_alias of string
        (** The named context is not merlin-enabled, so [@check] does not exist
            there. Remedy: lint the default context. *)
    | Describe_failed of string
        (** [dune describe] failed or its reply did not decode; the string is
            the detail. *)

  val roster :
    ?progress:Progress.t ->
    ?build:bool ->
    root:string ->
    unit ->
    (Roster.t, error) result
  (** [roster ~root ()] is the roster of the dune workspace at [root] —
      complete, with ownership metadata and cmi search path filled from the
      describe reply. [build] (defaults to [true]) runs [dune build @check]
      first; [false] is [--no-build], where stale artifacts surface as skips.
      Spawns dune; build output streams through to the user before this function
      returns.

      [progress] names each of the three stretches this function spends its time
      in — the build, the describe, the workspace read — on the caller's meter,
      and keeps its clock moving while dune runs; dune's own output takes the
      line back whenever it prints. Defaults to a meter that draws nothing. *)

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
