(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Shared cmdliner vocabulary for the [litany] commands: the exit-code
    contract, the refusal formatter, and the arguments more than one command
    takes. *)

val exit_ok : int
(** Exit 0: the run completed with no findings. *)

val exit_findings : int
(** Exit 1: the run completed with findings. *)

val exit_refusal : int
(** Exit 2: Litany could not run — adapter error or unusable invocation. *)

val exit_internal : int
(** Exit 3: an internal error — a rule failed. *)

val exits : Cmdliner.Cmd.Exit.info list
(** The exit-code documentation, declared on every command. *)

val code_of_eval : int -> int
(** [code_of_eval c] maps [Cmdliner.Cmd.eval']'s result onto the contract above:
    cmdliner's reserved 124 (unusable invocation) becomes {!exit_refusal} and
    125 (unexpected exception) becomes {!exit_internal}; every other code is a
    command's own and passes through. *)

val refuse : ('a, Format.formatter, unit, int) format4 -> 'a
(** [refuse fmt ...] prints [litany: <message>] on standard error and is
    {!exit_refusal}. Nothing runs after a refusal is printed; the caller returns
    the code. *)

val root : string Cmdliner.Term.t
(** [--root DIR]: run against the workspace rooted at [DIR] (default: the
    current directory). *)

val inside_dune : unit -> bool
(** [inside_dune ()] is [true] iff [INSIDE_DUNE] is set — dune's own declared
    contract for "this process runs as a dune action" and the single-writer
    model's ownership signal (doc/dev/design.md, Fixes). Any value counts as
    set; the value is never parsed. *)

val fix_word : Litany.Rule.t -> string
(** [fix_word r] is the fix promise as the table word: [never], [sometimes], or
    [always]. *)

val catalog : Litany.Rule.t list
(** [catalog] is {!Litany_rules.all} — the built-in catalog, spelled once for
    the whole CLI. A custom binary's full-CLI copy extends the catalog here and
    nowhere else. *)

val find_rule :
  string -> [ `Exact of Litany.Rule.t | `Renamed of Litany.Rule.t ] option
(** [find_rule name] resolves [name] over the built-in catalog: an exact rule
    name, a tombstone alias ([`Renamed] — callers print the rename warning in
    their own voice), or [None]. The one name-or-alias lookup behind [explain]
    and the config driver; {!Litany.Rule.select} performs the same resolution
    for selection tokens. *)
