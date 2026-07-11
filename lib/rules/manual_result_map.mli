(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Two-case matches that re-implement [Result.map] or [Result.map_error].

    Reports [match r with Ok x -> Ok E | Error e -> Error e] (and the mirrored
    [Result.map_error] shape, and the [function] forms) — exactly two guard-less
    cases with bare-variable payloads, in either order, constructors identified
    by the global [Stdlib.result] path — when exactly one arm transforms and the
    other rebuilds its payload unchanged. When both arms are identity rebuilds
    the match is the scrutinee itself and says so.

    Guards, deeper payload patterns, wildcard payloads, arms that do not rebuild
    their constructor, both arms transforming, and user variants spelling
    [Ok]/[Error] deliberately do not fire. The fix rewrites the match forms when
    the sources slice cleanly; the [function] forms have no scrutinee to name
    and ship none. *)

val rule : Litany.Rule.t
(** [rule] is [manual-result-map]. *)
