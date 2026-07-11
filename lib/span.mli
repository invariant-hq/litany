(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Half-open byte spans.

    A span is a pair of byte offsets \[[start];[stop][)] into one byte sequence
    — always the editable source of a unit. Spans are the coordinate system
    shared by fix edits ([Fix.edit]), source slicing ([Source.slice]), and
    suppression containment. A span carries no file identity; pairing it with
    the right [Source.t] is the caller's obligation.

    Offsets are 0-based byte counts, never character or column counts. The
    interval is half-open: [start] is the first byte inside the span, [stop] the
    first byte after it. *)

(** {1:spans Spans} *)

type t
(** The type for byte spans. Invariant: [0 <= start t <= stop t]. *)

val v : start:int -> stop:int -> t
(** [v ~start ~stop] is the span \[[start];[stop][)].

    Raises [Invalid_argument] if [start < 0] or [stop < start] — checked in that
    order: a span both negative and inverted reports the negative start. *)

val start : t -> int
(** [start s] is the offset of the first byte of [s]. *)

val stop : t -> int
(** [stop s] is the offset of the first byte after [s]. *)

val length : t -> int
(** [length s] is [stop s - start s]. *)

val is_empty : t -> bool
(** [is_empty s] is [true] iff [length s = 0]. Empty spans denote insertion
    points in fix edits. *)

(** {1:predicates Predicates} *)

val contains : t -> int -> bool
(** [contains s i] is [true] iff [start s <= i < stop s]. An empty span contains
    no offset. *)

val includes : t -> t -> bool
(** [includes s sub] is [true] iff every byte of [sub] lies in [s], i.e.
    [start s <= start sub && stop sub <= stop s]. This is the containment
    relation suppression matching uses; a span includes itself and any empty
    span positioned within its bounds. *)

val overlaps : t -> t -> bool
(** [overlaps s s'] is [true] iff some byte offset is contained in both [s] and
    [s']. Empty spans overlap nothing. Fix application drops whole fixes whose
    edits overlap another fix's edits (see [Fix]). *)

(** {1:converting Converting} *)

val of_location : Location.t -> t
(** [of_location loc] is the span from [loc.loc_start.pos_cnum] to
    [loc.loc_end.pos_cnum]. It does not inspect [loc_ghost]: rejecting ghost
    locations is the engine's emit contract, not this conversion's.

    Raises [Invalid_argument] if either offset is negative or the end precedes
    the start — checked in that order: a location both negative and inverted
    reports the negative offsets. The negative case is the one dummy positions
    hit: [Location.none] and some PPX-synthesized nodes carry [pos_cnum = -1].
    Rules guard by slicing first (see [Unit.splice]). *)

(** {1:fmt Formatting and comparing} *)

val equal : t -> t -> bool
(** [equal s s'] is [true] iff both offsets coincide. *)

val compare : t -> t -> int
(** [compare s s'] orders spans by [start], then by [stop]. This is the order
    fix application sorts edits by. The order is compatible with {!equal}. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf s] formats [s] for debugging, as [\[start;stop)]. The output is not
    stable. *)
