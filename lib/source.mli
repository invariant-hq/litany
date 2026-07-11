(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Editable source text of one unit.

    A source is the byte content of one editable source file, paired with its
    path and a line index built on first use. It is the substrate text rules
    receive ([Rule.source]), the coordinate authority for the engine's
    offset-consistency check ({!consistent}), and what fix edits and excerpt
    rendering slice ({!slice}).

    Bytes, not text: contents are raw bytes with no encoding assumption, and all
    offsets are 0-based byte offsets ({!Span}). Lines are 1-based, split on LF;
    a final line without a trailing LF counts as a line. A source never re-reads
    its file — it is a snapshot of the bytes the loader joined against, the same
    bytes the unit's freshness witness digested. *)

(** {1:sources Sources} *)

type t
(** The type for sources. *)

val v : path:string -> string -> t
(** [v ~path contents] is the source whose bytes are [contents], read from
    [path]. [path] is as adapter-supplied — workspace-relative for units the
    user edits — and is never re-resolved. *)

(** {1:queries Queries} *)

val path : t -> string
(** [path s] is the path [s] was read from, verbatim as supplied to {!v}. *)

val contents : t -> string
(** [contents s] is [s]'s raw bytes — the snapshot itself, not a copy. *)

val length : t -> int
(** [length s] is the number of bytes of [s]. *)

(** {1:slicing Slicing and lines} *)

val slice : t -> Span.t -> string option
(** [slice s sp] is the bytes of [s] under [sp], or [None] when [sp] does not
    lie within [[0;length s]]. Out-of-bounds spans are an expected input —
    locations under textual preprocessors count bytes of the preprocessed file —
    so absence is an answer, not an error. *)

val lines : t -> int
(** [lines s] is the number of lines of [s]. [0] iff [s] is empty. *)

val line : t -> int -> Span.t option
(** [line s n] is the span of line [n] (1-based) excluding its trailing LF, or
    [None] when [n] is not in [[1;lines s]]. *)

val position : t -> int -> Lexing.position option
(** [position s off] is the fully populated position of byte offset [off] in
    [s]: [pos_fname = path s], [pos_cnum = off], and [pos_lnum]/[pos_bol] from
    the line index. [None] when [off] is not in [[0;length s]]. *)

val location : t -> Span.t -> Location.t option
(** [location s sp] is the non-ghost location whose two positions are fully
    populated from the line index as by {!position}, or [None] when [sp] does
    not lie within [[0;length s]]. The inverse of [Span.of_location] and the
    anchor text rules build their findings with. *)

(** {1:consistency Offset consistency} *)

val consistent : t -> Lexing.position -> bool
(** [consistent s pos] is [true] iff [pos] agrees with [s]'s actual line index:
    [pos_lnum] is in [[1;lines s]], [pos_bol] is the byte offset at which that
    line starts, and [pos_cnum] is in [[pos_bol;stop]] where [stop] is the
    line's end offset including its LF.

    This is condition (c) of the emit contract: textual preprocessors emit [#]
    line directives that rewrite names and line numbers while [pos_cnum] keeps
    counting preprocessed-file bytes, so an inconsistent position means the
    offsets cannot be trusted — such findings degrade to line-anchored
    renderings and their fixes to [Display]. *)
