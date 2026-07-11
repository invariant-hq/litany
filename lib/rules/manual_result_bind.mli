(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Two-case matches that re-implement [Result.bind].

    Reports [match r with Ok x -> E | Error e -> Error e] (and the [function]
    form, in either case order) — exactly two guard-less cases, constructors
    identified by the global [Stdlib.result] path — when [E] is not an [Ok _]
    construction (manual-result-map's territory, exact partition) and the
    [Error] case rebuilds its own payload at an equal type (a coerced rebuild
    widens where [Result.bind] would not typecheck and is refused).

    The alias spelling [Error _ as e -> e] is a recorded false negative until a
    pattern-alias view lands. Guards, exception arms, deeper payload patterns,
    transformed or dropped errors, and user variants spelling [Ok]/[Error]
    deliberately do not fire. The self-definition gate exempts one definition
    site: a value binding named [bind] whose eventual function body is the
    match, inside a module binding named [Result] or at the root of a unit
    itself named [Result] — stdppx's own [Result.bind] must not be told to use
    [Result.bind]. Every other definition, [( let* )] included, keeps firing. No
    fix: the rewrite restructures the [Ok] arm into a lambda. *)

val rule : Litany.Rule.t
(** [rule] is [manual-result-bind]. *)
