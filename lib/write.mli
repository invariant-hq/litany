(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Atomic file publication.

    The one implementation of write-then-rename — the fix applier and the cache
    must call it, never a local copy: the bytes go to a fresh temp file beside
    the target and are renamed over it, so a reader — or a crash — sees the old
    complete file or the new one, never a torn one.

    The two callers' crash models differ in one dial, [fsync]: the fix applier
    flushes to disk before the rename (a power loss must not leave the journaled
    name pointing at unwritten blocks — the user's source file is
    unrecoverable), while the cache deliberately skips the flush (a torn cache
    entry after power loss is re-derivable, and eviction sweeps residue). The
    divergence is intended; this module keeps it one explicit argument instead
    of two implementations. *)

val atomic :
  ?fsync:bool -> ?mode:int -> path:string -> string -> (unit, string) result
(** [atomic ~path bytes] writes [bytes] to a fresh temp file in [path]'s
    directory and renames it over [path] — atomic on POSIX. [path] is used as
    given: callers that must write {e through} symlinks resolve them first
    ([Unix.realpath]) and pass the target.

    - [fsync] (default [true]) flushes the temp file's data to disk before the
      rename.
    - [mode] (default [0o644]) is the created file's permission bits, set before
      the rename; callers preserving a target's permissions stat it and pass
      them.

    Temp names are [".litany.<pid>.<n>.tmp"] — pid plus an atomic counter,
    unique across processes and domains alike (no shared PRNG), created with
    [O_EXCL]; the [".tmp"] suffix is what the cache's eviction sweep recognizes
    as residue. Any failure removes the temp file and leaves [path]'s bytes
    alone; the error is the system message. *)
