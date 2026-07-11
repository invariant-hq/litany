(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Content-addressed per-unit result cache.

    Litany caches per-unit results (findings + facts + skip status) on disk so a
    warm run skips the work whose inputs have not changed. This domain is pure
    policy over caller-supplied bytes with a thin IO edge: it derives
    {{!Key}keys} from digests the caller already holds, stores and loads opaque
    payloads under them, and runs the {{!sweep}read-stamp + eviction sweep} when
    — and only when — the driver asks. It computes nothing about cmts, configs,
    or rules itself, and it never does implicit background work.

    {b The cache is advisory.} Every semantic input is part of the key, so a
    stale hit is structurally impossible and a miss only costs recomputation.
    Accordingly, no function here raises: an IO failure degrades to a miss
    ({!load}), a dropped write ({!store}), or a partial sweep ({!sweep}) — a
    broken cache must never break a lint run. A successful {!load} returns
    exactly the bytes {!store} was given, so a warm result is byte-identical to
    a cold one by construction.

    {b No mtimes anywhere.} Entry age is tracked by explicit last-read stamps
    stored as file contents; the current time is always an argument. This makes
    eviction deterministic and testable without touching the filesystem clock.

    {b Layout.} A cache root (see {!resolve_root}) holds one directory per
    workspace, named by the workspace digest — the BLAKE128 hex of the workspace
    root's realpath. Each workspace directory stores that realpath in a [marker]
    file (so an orphaned directory can be recognized after its workspace is
    deleted) and one framed entry file per key, named by the key's hex, with a
    sibling [<hex>.stamp] last-read stamp. All writes are atomic: a unique temp
    file in the same directory, renamed into place.

    {b Concurrent writers.} There are no locks. Writers racing on the same key
    end with last-writer-wins, which is sound because equal keys imply equal
    semantic content; readers always see a complete entry — the old one or the
    new one, never a torn one. Racing sweeps at worst delete an in-flight temp
    file, degrading that writer's {!store} to a no-op.

    [--no-cache] is the driver's concern: it simply never constructs a
    {{!t}handle}. *)

(** {1:keys Keys} *)

(** Cache keys.

    A key names one unit's result under one exact configuration of every
    semantic input. The components — {!v}'s labeled arguments, and nothing else
    — determine it; the argument list {e is} the inventory of what the cache
    keys on. *)
module Key : sig
  type t
  (** The type for cache keys — a BLAKE128 digest over {!v}'s components. *)

  val v :
    cmt_digest:string ->
    cmti_digest:string option ->
    source_path:string ->
    source_digest:string ->
    interface_source:(string * string) option ->
    library:string option ->
    visibility:string ->
    kind:string option ->
    config_fingerprint:string ->
    build_current:bool ->
    selected_rules:string list ->
    binary_digest:string ->
    t
  (** [v] is the key for that combination of inputs. Each input is opaque bytes
      supplied by the caller — this module frames and digests them, it never
      inspects or recomputes them:

      - [cmt_digest] — digest of the unit's cmt artifact;
      - [cmti_digest] — digest of the companion cmti; [None] when the entry
        names none (an unreadable cmti is the caller's sentinel, not [None] —
        absent and unreadable must not collide);
      - [source_path] — the unit's editable source path (findings anchor by
        path, so the same bytes at another path are another result);
      - [source_digest] — digest of the unit's editable source bytes;
      - [interface_source] — the paired interface's (path, digest of its bytes),
        or [None] when the entry names none or it is unreadable (unreadable
        loads as absent, so it keys as absent — derive and load stay one story);
      - [library] — the owning library's name, if known;
      - [visibility] — the owning library's visibility, as the caller spells it;
      - [kind] — the owning stanza's kind, if known, as the caller spells it;
      - [config_fingerprint] — fingerprint of the resolved configuration;
      - [build_current] — whether the run held a current-build guarantee;
      - [selected_rules] — the names of the selected rules, as a {e set}: order
        and duplicates do not affect the key;
      - [binary_digest] — digest of the running Litany executable itself.

      [binary_digest] is the one salt: any recompile invalidates every entry. It
      is also what makes [Marshal] a safe payload format — a different binary
      (different type layout, different compiler) can never load another
      binary's entries, because its keys differ.

      The derivation is deterministic and version-tagged; components are
      length-prefixed and optional components presence-tagged — all by this
      function, never by caller-side packing — so distinct input tuples yield
      distinct encodings. A key's hex is pinned by a golden test — changing the
      derivation is a deliberate cache-format change, never an accident. *)

  val to_hex : t -> string
  (** [to_hex k] is [k] as 32 lowercase hex characters — also [k]'s entry
      filename in the workspace directory. *)

  val equal : t -> t -> bool
  (** [equal k k'] is [true] iff [k] and [k'] are the same key. *)

  val compare : t -> t -> int
  (** [compare] is a total order on keys, consistent with {!equal}. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf k] prints [k]'s hex on [ppf]. *)
end

(** {1:handles Handles} *)

type t
(** The type for cache handles — one workspace's cache directory under one cache
    root. A handle performs no IO until {!store} or {!sweep}; a workspace
    directory (and its [marker] file) is created on first write. *)

val create : root:string -> workspace_root:string -> t
(** [create ~root ~workspace_root] is the handle for [workspace_root]'s cache
    under the cache root [root]. [workspace_root] is resolved to its realpath
    (the workspace digest is the BLAKE128 of that realpath, so every spelling of
    the same directory shares one cache); if resolution fails — the path does
    not exist — the path is used as given. Pass an absolute [workspace_root].
    Never raises. *)

val dir : t -> string
(** [dir t] is [t]'s workspace cache directory: [root] / workspace-digest. The
    directory may not exist yet — see {!t}. *)

(** {1:rw Storing and loading} *)

val store : t -> now:float -> Key.t -> string -> unit
(** [store t ~now key payload] atomically records [payload] — opaque bytes; the
    engine serializes, this module never looks inside — under [key], and stamps
    the entry as read at [now] (seconds since the epoch), so a fresh entry
    starts its 30-day lease at its write. The entry is framed with the key and a
    payload digest, so {!load} can reject torn or corrupted files {e and}
    contents that were stored under a different key — entry files renamed or
    swapped by an external tool are misses, never replays under the wrong key.

    Best-effort: on any IO failure the cache is simply not updated. Concurrent
    stores under the same key end last-writer-wins (see the module preamble:
    equal keys imply equal semantic content). *)

val load : t -> Key.t -> string option
(** [load t key] is [Some payload] — exactly the bytes the winning {!store}
    recorded, byte-identical — iff a well-formed entry for [key] exists whose
    frame names [key] itself, and [None] otherwise. A missing, truncated,
    corrupted, or wrong-key entry is a miss, never an error; such entries are
    left for {!sweep} to age out.

    [load] writes nothing — workers can load in parallel with no write
    contention. Read stamps are updated by the driver's end-of-run {!sweep}, not
    here. *)

(** {1:sweeping Read stamps and eviction} *)

val max_age : float
(** [max_age] is the eviction horizon in seconds: 30 days. An entry whose
    last-read stamp is older than [now -. max_age] is deleted by {!sweep}. *)

type sweep = { evicted_entries : int; removed_workspaces : int }
(** The type for sweep results: how many entries {!max_age} evicted from this
    workspace, and how many defunct workspace directories were removed from the
    root. *)

val sweep : t -> now:float -> read:Key.t list -> sweep
(** [sweep t ~now ~read] is the explicit end-of-run maintenance pass — the only
    place stamps are refreshed and space is reclaimed; nothing here ever happens
    implicitly. In order:

    - stamps every existing entry in [read] as read at [now] — pass the keys
      whose payloads this run loaded ({!store} already stamped this run's
      writes);
    - deletes entries of [t]'s workspace unread for longer than {!max_age}, with
      their stamps; an entry whose stamp is missing or unreadable is re-stamped
      at [now] instead (a fresh lease, so damage self-heals and still ages out);
      orphaned stamps and leftover temp files are deleted;
    - removes sibling workspace directories under the root whose [marker] names
      a path that no longer exists, and marker-less empty ones (crash residue).

    [litany cache clean] is [sweep t ~now ~read:[]] — same pass, forced,
    stamping nothing. Best-effort: anything that cannot be examined or deleted
    is skipped, never raised on. Never raises. *)

(** {1:location Locating the cache} *)

val resolve_root :
  ?cache_dir:string -> env:(string -> string option) -> unit -> string option
(** [resolve_root ?cache_dir ~env ()] is the cache root the driver should use,
    or [None] when no location is determinable (the driver then runs uncached).
    Pure — [env] is the only window on the environment. Precedence:

    + [cache_dir] — the [--cache-dir] flag — used as given;
    + [env "LITANY_CACHE_DIR"] (nonempty) — used as given;
    + [env "XDG_CACHE_HOME"] (nonempty and absolute, per the XDG spec) —
      [$XDG_CACHE_HOME/litany];
    + [env "HOME"] (nonempty and absolute) — [$HOME/.cache/litany];
    + otherwise [None]. *)
