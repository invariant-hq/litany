(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Positioned s-expressions — the configuration surface's neutral payload
    vocabulary.

    The value type for [(rule <name> <options>...)] payloads and the positioned
    error both sides of that seam speak. [Config_file] parses these, keeping
    them opaque — any well-formed s-expression is admitted — and rule option
    schemas ([Rule.Options]) consume them, positions included, so rule-side
    validation reports [file:line:col] exactly like the parser's own refusals.
    Owning the vocabulary here keeps the dependency arrow honest: the config
    parser and the rule SDK are both clients of the payload type, neither the
    other's landlord.

    Positions are 1-based lines and 1-based byte columns into the parsed string,
    the renderer's convention. *)

type t = { desc : desc; line : int; col : int }
(** The type for s-expressions, with the position of their first byte. *)

and desc =
  | Atom of string
  | List of t list
      (** The type for s-expression shapes. A quoted string is an [Atom] like
          any bare word. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf s] formats [s] as s-expression text, for debugging. The output is
    not stable. *)

(** {1:errors Positioned errors} *)

(** Positioned errors: a position into the parsed string and one actionable
    message.

    The one error shape of the configuration surface — [Config_file.Error] and
    [Rule.Options.error] are both this type, so a driver renders every
    config-file refusal with {!Error.to_string} whichever side produced it. *)
module Error : sig
  type t = {
    line : int;  (** 1-based line of the offending text. *)
    col : int;  (** 1-based byte column. *)
    message : string;
        (** The message without position — e.g.
            [unknown rule "styel" (did you mean "style"?)]. *)
  }
  (** The type for positioned errors. *)

  val line : t -> int
  (** [line e] is [e.line]. *)

  val column : t -> int
  (** [column e] is [e.col]. *)

  val message : t -> string
  (** [message e] is [e.message]. *)

  val to_string : ?file:string -> t -> string
  (** [to_string ~file e] is ["file:line:col: message"]. [file] defaults to
      ["litany"], the root configuration file's name; the driver, which read the
      file, may pass its path. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf e] formats {!to_string} with the default [file]. *)
end
