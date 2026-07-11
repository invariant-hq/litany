(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The adapter-supplied enumeration of units.

    A roster is what an adapter hands the core: the list of candidate units —
    each a source path with its artifact paths and optional project metadata
    ({!Entry}) — plus the cmi search path for the resolver and the adapter's
    completeness assertion. It is the value the unit file serializes
    ([Adapter.Unit_file]), and the only channel through which any build system
    reaches the core.

    A roster is an enumeration, never a proof: per-unit freshness witnesses gate
    every join ([Unit.load]), so a stale or wrong roster costs only skips, never
    findings. Trust enters exactly once, as the {!complete} bit: an adapter that
    asserts completeness claims the entry list is the whole unit universe of the
    build context, which is what project rules' universally quantified claims
    stand on. A roster that is complete and carries {!Entry.library} and
    {!Entry.kind} for every entry is {!project_capable}; lanes below that run
    local rules only.

    This module is inert data with no compiler-libs and no IO; adapters
    construct rosters, the driver and engine consume them. *)

(** {1:entries Entries} *)

(** The type for library visibility. *)
type visibility =
  | Public  (** Reachable by consumers outside the workspace. *)
  | Private  (** Internal to the workspace. *)
  | Unknown
      (** Metadata absent or unresolvable — an adapter that cannot answer says
          so, it never guesses. Treated as [Public] wherever root policy
          applies: exports of a library of unknown visibility are dead-code
          roots, never candidates. *)

(** The type for stanza kinds — which kind of build product owns the unit.
    [Test] has a producer: the dune walk lane ([Adapter]) mints [Test] rows from
    test-stanza ownership, so trees with tests keep project capability; the
    kind-gated rules fold it into "not [Library]", which is exactly the gate
    they mean. *)
type kind = Library | Executable | Test

val kind_to_string : kind -> string
(** [kind_to_string k] is ["lib"], ["exe"], or ["test"] — the unit-file codec's
    [kind] field vocabulary ([Adapter.Unit_file]). *)

val kind_of_string : string -> kind option
(** [kind_of_string s] is the codec's inverse: [Some k] iff [s] is
    {!kind_to_string}[ k] for some [k]. *)

(** One candidate unit: paths plus optional project metadata. *)
module Entry : sig
  type t
  (** The type for roster entries. *)

  val v :
    source:string ->
    ?cmt:string ->
    ?cmti:string ->
    ?preprocessed_source:string ->
    ?interface_source:string ->
    ?library:string ->
    ?visibility:visibility ->
    ?kind:kind ->
    unit ->
    t
  (** [v ~source ()] is an entry for the unit whose editable source is [source].
      All paths are adapter-supplied and are used verbatim — never resolved
      against recorded artifact paths.

      - [cmt], [cmti]: the unit's artifacts. Litany 1.0 admits implementation
        units only, so an entry without [cmt] — including one naming no artifact
        at all — loads as [Unit.Skip.Missing_artifact], the skip taxonomy's own
        word for it, never an error; the fields are optional so the unit-file
        grammar and future interface-only support need no new constructor.
      - [preprocessed_source]: the built preprocessed source ([<m>.pp.ml]) for
        units the compiler read from a built pp file — the anchor of the Derived
        witness. Defaults to none, meaning the unit is expected to join Direct.
      - [interface_source]: the unit's paired interface source ([.mli]) — the
        second editable file of a unit whose [source] is an implementation. Text
        rules ([Rule.source]) run over it too; nothing else reads it. Defaults
        to none. An interface-only unit names its [.mli] as [source], never
        here.
      - [library]: the owning library's name. [kind]: the owning stanza's kind.
        Both default to none; project rules need both on every entry.
        [visibility]: the owning library's visibility; defaults to [Unknown]. *)

  val source : t -> string
  (** [source e] is the editable source path — the file the user edits, the one
      findings anchor in. *)

  val cmt : t -> string option
  (** [cmt e] is the path of the unit's [.cmt], if named. *)

  val cmti : t -> string option
  (** [cmti e] is the path of the unit's [.cmti], if named. Its decode is
      demand-gated: nothing reads it unless a selected rule needs interface
      annotations. *)

  val preprocessed_source : t -> string option
  (** [preprocessed_source e] is the built preprocessed source path, if the
      compiler read one. *)

  val interface_source : t -> string option
  (** [interface_source e] is the paired interface source path ([.mli]), if the
      adapter named one. Read once at load ([Unit.load]) for the text lane;
      never witness-checked — text findings anchor in the exact bytes read. *)

  val library : t -> string option
  (** [library e] is the owning library's name, if known. *)

  val visibility : t -> visibility
  (** [visibility e] is the owning library's visibility. [Unknown] is treated as
      [Public] wherever root policy applies. *)

  val kind : t -> kind option
  (** [kind e] is the owning stanza's kind, if known. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf e] formats [e] for debugging. The output is not stable. *)
end

(** {1:rosters Rosters} *)

type t
(** The type for rosters. *)

val v : ?complete:bool -> ?cmi_dirs:string list -> Entry.t list -> t
(** [v entries] is a roster enumerating [entries], in the adapter's order —
    consumers must not depend on that order; the engine's output order is its
    own law.

    - [complete] is the adapter's assertion that [entries] is the whole unit
      universe of the build context. Defaults to [false]; only an adapter that
      constructed the list from the build system's own description (or a unit
      file claiming the same) may pass [true].
    - [cmi_dirs] are the directories the resolver searches for [.cmi] files of
      workspace libraries and installed dependencies, in search order. Defaults
      to [[]]. The driver appends the toolchain's standard library directory;
      adapters never include it. *)

val entries : t -> Entry.t list
(** [entries r] is [r]'s entries, in the order given to {!v}. *)

val complete : t -> bool
(** [complete r] is [true] iff the producing adapter asserted that {!entries} is
    the whole unit universe. *)

val cmi_dirs : t -> string list
(** [cmi_dirs r] is the resolver search path as supplied to {!v} — without the
    toolchain standard library directory, which the driver appends. *)

val project_capable : t -> bool
(** [project_capable r] is [true] iff [complete r] and every entry carries
    [library] and [kind]. Visibility never gates project capability: [Unknown]
    resolves to [Public] under root policy. Project rules run only on
    project-capable rosters; below that the summary reads
    [roster: none (project rules unavailable)]. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf r] formats a summary of [r] — entry count, completeness, metadata
    coverage — for debugging. The output is not stable. *)
