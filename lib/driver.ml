(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The check driver — the convergence loop and its supporting lanes: bin/
   is thin composition (cmdliner terms and wiring), the run's machinery
   lives here. Behavior is governed by doc/dev/design.md (Fixes). *)

(* {1 Exit contract}

   The stable exit contract: 0 clean, 1 findings, 2 could-not-run, 3 internal
   error. The codes live here because they are the driver's results
   ([Engine.Report.exit_code] already owns 0/1); the cmdliner-facing
   mapping ([code_of_eval], the documented exits table) stays in bin. *)

let exit_ok = 0
let exit_findings = 1
let exit_refusal = 2
let exit_internal = 3

let refuse fmt =
  Format.kfprintf
    (fun ppf ->
      Format.pp_print_newline ppf ();
      exit_refusal)
    Format.err_formatter ("litany: " ^^ fmt)

(* The exit precedence law's one home: refusal 2 > internal 3 > findings 1 >
   clean 0. A refusal names a run that could not stand — the tree or the
   store is not in a runnable state — and outranks even a fixer bug: the
   refusal's remedy must run first, and the bug recurs on the re-run. Every
   return of [run_check] passes through here, so the precedence is declared,
   never emergent from which return fires first. (The all-skip
   escalation is the one refinement on top: it fires only on a [Completed]
   run whose code would otherwise read clean — it refuses silent success,
   never softens a louder exit.) *)
type stop = Completed | Refused

let exit_of stop ~bug report =
  match stop with
  | Refused -> exit_refusal
  | Completed -> if bug then exit_internal else Engine.Report.exit_code report

(* The [_build]-component path test behind the build-scoped fix refusal:
   [--fix] must never write into a build tree, whoever produced it. The
   policy stays at its call site; only the predicate lives here. *)
let under_build path =
  List.exists (String.equal "_build") (String.split_on_char '/' path)

module Result_cache = struct
  (* Key derivation and the engine adapter for the result cache. Policy note:
   everything here degrades to "recompute" — an unreadable file, an
   unresolvable location, an undigestable binary all mean the entry (or the
   run) is simply uncached. The cache domain's own law (a broken cache never
   breaks a lint run) is upheld by never raising past this module. *)

  type t = {
    cache : Cache.t;
    config_bytes : string;  (** The [litany] file's raw bytes, or empty. *)
    rule_names : string list;
    binary_digest : string;
    mutable hits : int;
    mutable misses : int;
    mutable stores : int;
    mutable hit_keys : Cache.Key.t list;
  }

  let setup ~cache_dir ~no_cache ~root ~rules =
    if no_cache then None
    else
      match Cache.resolve_root ?cache_dir ~env:Sys.getenv_opt () with
      | None -> None
      | Some cache_root -> (
          match Digest.BLAKE128.file Sys.executable_name with
          | exception Sys_error _ -> None
          | binary_digest ->
              (* Mirror [Cli_config.load]'s discovery byte-for-byte: the
               fingerprint must cover exactly the bytes the config lane
               parsed. An unreadable-but-present file already refused the
               run before the cache is set up. *)
              let config_bytes =
                let file = Filename.concat root "litany" in
                if (not (Sys.file_exists file)) || Sys.is_directory file then ""
                else
                  match In_channel.with_open_bin file In_channel.input_all with
                  | bytes -> bytes
                  | exception Sys_error _ -> ""
              in
              let workspace_root =
                if Filename.is_relative root then
                  Filename.concat (Sys.getcwd ()) root
                else root
              in
              Some
                {
                  cache = Cache.create ~root:cache_root ~workspace_root;
                  config_bytes;
                  rule_names = List.map Rule.name rules;
                  binary_digest;
                  hits = 0;
                  misses = 0;
                  stores = 0;
                  hit_keys = [];
                })

  (* [derive t ~build_current entry] is the entry's key, its source bytes, and
   its interface source's (path, bytes) when one is named and readable — or
   [None] when the entry is not keyable: a preprocessed source (the Derived
   lane digests the pp file — not a key component), no cmt (the skip lane),
   or an unreadable file. The bytes double as the hit lane's snapshots: the
   digests in the key pin them to the bytes the stored run analyzed. *)
  let derive t ~build_current entry =
    match Roster.Entry.preprocessed_source entry with
    | Some _ -> None
    | None -> (
        match Roster.Entry.cmt entry with
        | None -> None
        | Some cmt -> (
            (* Wrong-magic pre-filter: an artifact from another compiler
             generation can only skip, so digesting it (or its source)
             would be pure waste — the dominant population in shared build
             stores. Both of this compiler's magics admit — a cmt whose
             module has no mli leads with a cmi block — mirroring the
             loader's own precheck; the load lane re-reads the magic and
             produces the honest counted skip. *)
            let right_magic =
              match
                In_channel.with_open_bin cmt (fun ic ->
                    In_channel.really_input_string ic
                      (String.length Config.cmt_magic_number))
              with
              | Some magic ->
                  String.equal magic Config.cmt_magic_number
                  || String.equal magic Config.cmi_magic_number
              | None -> false
              | exception Sys_error _ -> false
            in
            if not right_magic then None
            else
              let source_path = Roster.Entry.source entry in
              match
                In_channel.with_open_bin source_path In_channel.input_all
              with
              | exception Sys_error _ -> None
              | source_bytes -> (
                  match Digest.BLAKE128.file cmt with
                  | exception Sys_error _ -> None
                  | cmt_digest ->
                      (* An unreadable named cmti is a sentinel, not absence:
                       the interface substrate demand would fail where the
                       absent case never demands, so the two must not share a
                       key. *)
                      let cmti_digest =
                        match Roster.Entry.cmti entry with
                        | None -> None
                        | Some p -> (
                            try Some (Digest.BLAKE128.file p)
                            with Sys_error _ -> Some "cmti-unreadable")
                      in
                      (* The interface text lane's bytes are a key component:
                       fixing an mli must miss, not replay its findings. An
                       unreadable named interface loads as absent, so it
                       keys as absent too — derive and load stay one
                       story. *)
                      let intf =
                        match Roster.Entry.interface_source entry with
                        | None -> None
                        | Some ipath -> (
                            match
                              In_channel.with_open_bin ipath
                                In_channel.input_all
                            with
                            | bytes -> Some (ipath, bytes)
                            | exception Sys_error _ -> None)
                      in
                      (* Roster metadata is a semantic input: project
                       facts bake in the root policy (library, visibility,
                       kind), and kind-gated rules read the same fields —
                       flipping a library public must miss, never replay
                       facts collected under the old policy. *)
                      let key =
                        Cache.Key.v ~cmt_digest ~cmti_digest ~source_path
                          ~source_digest:(Digest.BLAKE128.string source_bytes)
                          ~interface_source:
                            (Option.map
                               (fun (ipath, bytes) ->
                                 (ipath, Digest.BLAKE128.string bytes))
                               intf)
                          ~library:(Roster.Entry.library entry)
                          ~visibility:
                            (match Roster.Entry.visibility entry with
                            | Roster.Public -> "public"
                            | Roster.Private -> "private"
                            | Roster.Unknown -> "unknown")
                          ~kind:
                            (match Roster.Entry.kind entry with
                            | None -> None
                            | Some Roster.Library -> Some "lib"
                            | Some Roster.Executable -> Some "exe"
                            | Some Roster.Test -> Some "test")
                          ~config_fingerprint:t.config_bytes ~build_current
                          ~selected_rules:t.rule_names
                          ~binary_digest:t.binary_digest
                      in
                      Some (key, source_bytes, intf))))

  let unit_cache t ~build_current ~snapshots ~baselines =
    (* Memoized per pass: the engine calls [store] only after [load] on the
     same entry, so the digests are computed once. Entries are inert records
     of strings — structural hashing is exact. *)
    let memo = Hashtbl.create 64 in
    let derive entry =
      match Hashtbl.find_opt memo entry with
      | Some d -> d
      | None ->
          let d = derive t ~build_current entry in
          Hashtbl.replace memo entry d;
          d
    in
    {
      Engine.Unit_cache.load =
        (fun entry ->
          match derive entry with
          | None -> None
          | Some (key, source_bytes, intf) -> (
              match Cache.load t.cache key with
              | None ->
                  t.misses <- t.misses + 1;
                  None
              | Some payload
                when not (Engine.Unit_cache.plausible_payload payload) ->
                  (* A digest-valid frame around bytes that are no engine
                   payload can never replay — the engine quietly recomputes —
                   so the stats line must call it a miss: it misreports
                   exactly the corruption it exists to diagnose otherwise.
                   Not a hit key either; the recompute re-stores the entry
                   (self-heal). *)
                  t.misses <- t.misses + 1;
                  None
              | Some payload ->
                  t.hits <- t.hits + 1;
                  t.hit_keys <- key :: t.hit_keys;
                  (* The driver's [load] never runs on a hit: fill its tables
                   here. The key's source digest pins these bytes to the
                   bytes the stored run analyzed — the interface source's
                   included. *)
                  let path = Roster.Entry.source entry in
                  Hashtbl.replace snapshots path (Source.v ~path source_bytes);
                  Hashtbl.replace baselines path
                    (Digest.BLAKE128.string source_bytes);
                  Option.iter
                    (fun (ipath, bytes) ->
                      Hashtbl.replace snapshots ipath
                        (Source.v ~path:ipath bytes);
                      Hashtbl.replace baselines ipath
                        (Digest.BLAKE128.string bytes))
                    intf;
                  Some payload));
      store =
        (fun entry payload ->
          match derive entry with
          | None -> ()
          | Some (key, _, _) ->
              t.stores <- t.stores + 1;
              Cache.store t.cache ~now:(Unix.gettimeofday ()) key payload);
    }

  let absorb_counts t ~hits ~misses ~stores keys =
    t.hits <- t.hits + hits;
    t.misses <- t.misses + misses;
    t.stores <- t.stores + stores;
    t.hit_keys <- List.rev_append keys t.hit_keys

  let counts t = (t.hits, t.misses, t.stores)
  let hit_keys t = t.hit_keys

  let finish t ~stats =
    let sw = Cache.sweep t.cache ~now:(Unix.gettimeofday ()) ~read:t.hit_keys in
    if stats then
      Format.eprintf
        "litany: cache: %d hits, %d misses, %d stored, %d evicted@." t.hits
        t.misses t.stores sw.Cache.evicted_entries
end

module Parallel = struct
  (* Process workers for [litany check -j N]. The parent forks one child per
   shard; each child runs the real engine over its sub-roster (loading and
   storing through the shared result cache exactly as a serial run would) and
   marshals one wire value back over a pipe; the parent replays every
   per-unit payload through a single engine pass over the full roster. See
   the .mli for the mechanism decision and the determinism argument. *)

  let default_jobs () = Domain.recommended_domain_count ()

  (* {1 The wire}

   One value per shard, Marshal over the pipe — sound because a forked child
   is the same binary image (the cache lane's payloads are additionally keyed
   by binary digest; this lane never crosses binaries at all). Rows align
   with the shard's entries by position. *)

  type wire_row =
    | Skipped of Unit.Skip.t
    | Admitted of {
        payload : string;  (** The engine's per-unit payload bytes. *)
        source : string;
            (** The admitted source snapshot — render excerpts and end-of-run
                revalidation must see the exact bytes the worker analyzed. *)
        intf : (string * string) option;
            (** The interface text lane's (path, bytes) snapshot, when the entry
                names one — same obligations as [source] for findings anchored
                in the [.mli]. *)
      }

  type wire = {
    rows : wire_row list;  (** In the shard's (roster-order) entry order. *)
    cache_hits : int;
    cache_misses : int;
    cache_stores : int;
    cache_hit_keys : Cache.Key.t list;
  }

  (* {1 Sharding}

   Size-weighted, order-preserving: each entry (in roster order) goes to the
   shard with the least accumulated cmt bytes, ties to the lowest index.
   Deterministic — sizes are file contents — and unobservable in the output:
   the parent reassembles per entry, not per shard. Roster order within a
   shard is load-bearing for the cmi-degradation notes: a shard's first
   demander of an unreadable cmi must be its first in roster order, so the
   parent's dedup lands the note where a serial run would. *)

  let split ~shards entries =
    let loads = Array.make shards 0 in
    let buckets = Array.make shards [] in
    let least_loaded () =
      let k = ref 0 in
      Array.iteri (fun i l -> if l < loads.(!k) then k := i) loads;
      !k
    in
    List.iter
      (fun entry ->
        let size =
          match Roster.Entry.cmt entry with
          | None -> 1
          | Some p -> (
              match (Unix.stat p).Unix.st_size with
              | s -> max 1 s
              | exception Unix.Unix_error _ -> 1)
        in
        let k = least_loaded () in
        loads.(k) <- loads.(k) + size;
        buckets.(k) <- entry :: buckets.(k))
      entries;
    Array.to_list (Array.map List.rev buckets)

  (* {1 The child} *)

  (* One shard = one full engine run over a sub-roster with a fresh resolver
   (compiler-libs decode confined per process). The child's own report is
   discarded except for its per-entry outcomes; [capture] keys each payload
   by the entry the engine hands it, so the row builder is a plain map over
   the outcomes with table lookups — no positional invariant. *)
  let run_shard ~progress ~cache ~rules ~catalog ~build_current ~cmi_dirs
      entries =
    let resolver =
      Naming.Resolver.create ~cmi_dirs:(cmi_dirs @ [ Config.standard_library ])
    in
    let roster = Roster.v ~complete:false ~cmi_dirs entries in
    let snapshots = Hashtbl.create 32 in
    let baselines = Hashtbl.create 32 in
    let unit_cache =
      Option.map
        (fun c ->
          Result_cache.unit_cache c ~build_current ~snapshots ~baselines)
        cache
    in
    let load entry =
      match Unit.load ~resolver ~build_current entry with
      | Ok u ->
          Hashtbl.replace snapshots (Unit.path u) (Unit.source u);
          Option.iter
            (fun isrc -> Hashtbl.replace snapshots (Source.path isrc) isrc)
            (Unit.interface_source u);
          Ok u
      | Error _ as e -> e
    in
    let captured : (Roster.Entry.t, string) Hashtbl.t = Hashtbl.create 64 in
    let report =
      Engine.run ?unit_cache ~progress
        ~capture:(fun entry bytes -> Hashtbl.replace captured entry bytes)
        ~rules ~catalog ~roster ~load ()
    in
    (* Missing table rows below are unreachable by the lanes' contracts —
     [capture] fires per admitted entry, both fill paths (fresh [load],
     cache-hit key derivation) populate [snapshots] — so a miss is a bug:
     raise rather than fabricate bytes the parent's revalidation would
     silently demote on. The exception arm of the fork prints it and turns
     it into a visible lost shard. *)
    let rows =
      (* [Report.units] is in roster order — the shard's entry order. *)
      List.map2
        (fun entry (path, outcome) ->
          match outcome with
          | Engine.Report.Skipped sk -> Skipped sk
          | Engine.Report.Linted | Engine.Report.Facts_only ->
              let payload =
                match Hashtbl.find_opt captured entry with
                | Some bytes -> bytes
                | None -> invalid_arg ("worker: no captured payload for " ^ path)
              in
              let source =
                match Hashtbl.find_opt snapshots path with
                | Some s -> Source.contents s
                | None -> invalid_arg ("worker: no source snapshot for " ^ path)
              in
              let intf =
                match Roster.Entry.interface_source entry with
                | None -> None
                | Some ipath ->
                    Option.map
                      (fun s -> (ipath, Source.contents s))
                      (Hashtbl.find_opt snapshots ipath)
              in
              Admitted { payload; source; intf })
        entries
        (Engine.Report.units report)
    in
    let cache_hits, cache_misses, cache_stores =
      match cache with Some c -> Result_cache.counts c | None -> (0, 0, 0)
    in
    {
      rows;
      cache_hits;
      cache_misses;
      cache_stores;
      cache_hit_keys =
        (match cache with Some c -> Result_cache.hit_keys c | None -> []);
    }

  (* {1 Fork, drain, reap} *)

  (* [Unix.waitpid] reports signals in OCaml's own [Sys.sig*] numbering, not
   the OS's — a real SIGKILL is [-7]. Print names ([bench_check.ml] mirrors
   this table); the fallback says whose numbering the constant is. *)
  let signal_name =
    let names =
      [
        (Sys.sigabrt, "SIGABRT");
        (Sys.sigalrm, "SIGALRM");
        (Sys.sigbus, "SIGBUS");
        (Sys.sigchld, "SIGCHLD");
        (Sys.sigcont, "SIGCONT");
        (Sys.sigfpe, "SIGFPE");
        (Sys.sighup, "SIGHUP");
        (Sys.sigill, "SIGILL");
        (Sys.sigint, "SIGINT");
        (Sys.sigkill, "SIGKILL");
        (Sys.sigpipe, "SIGPIPE");
        (Sys.sigquit, "SIGQUIT");
        (Sys.sigsegv, "SIGSEGV");
        (Sys.sigstop, "SIGSTOP");
        (Sys.sigterm, "SIGTERM");
        (Sys.sigtstp, "SIGTSTP");
        (Sys.sigusr1, "SIGUSR1");
        (Sys.sigusr2, "SIGUSR2");
        (Sys.sigxcpu, "SIGXCPU");
        (Sys.sigxfsz, "SIGXFSZ");
      ]
    in
    fun n ->
      match List.assoc_opt n names with
      | Some name -> name
      | None -> Printf.sprintf "signal %d (ocaml numbering)" n

  type child = { pid : int; read_fd : Unix.file_descr }

  let fork_shard ~idx f =
    let read_fd, write_fd = Unix.pipe ~cloexec:false () in
    (* Anything buffered would otherwise flush twice, once per process. *)
    flush stdout;
    flush stderr;
    match Unix.fork () with
    | 0 -> (
        Unix.close read_fd;
        (* Deterministic crash knobs for the cram pins of the lost-shard lane
         (exit and signal arms both); undocumented, test-only. *)
        (match Sys.getenv_opt "LITANY_TEST_LOSE_SHARD" with
        | Some v when v = string_of_int idx -> Unix._exit 66
        | Some v when v = string_of_int idx ^ ":kill" ->
            Unix.kill (Unix.getpid ()) Sys.sigkill
        | Some _ | None -> ());
        (* [_exit]: skip [at_exit], whose channel flushing is the parent's. *)
        match f () with
        | wire ->
            let oc = Unix.out_channel_of_descr write_fd in
            Marshal.to_channel oc (wire : wire) [];
            flush oc;
            close_out oc;
            Unix._exit 0
        | exception e ->
            Printf.eprintf "litany: worker: %s\n%!" (Printexc.to_string e);
            Unix._exit 2)
    | pid ->
        Unix.close write_fd;
        { pid; read_fd }

  (* {1 The workers' progress channel}

   One pipe, shared by every child: a byte per unit finished. The write end
   is non-blocking, so a full pipe drops ticks instead of stalling a worker —
   the meter is advisory and the run is not. The parent drains it while it
   waits on each shard's result, which is what keeps the line moving through
   the long middle of a sharded run. *)

  let tick_byte = Bytes.make 1 '.'

  let tick fd () =
    try ignore (Unix.write fd tick_byte 0 1 : int)
    with Unix.Unix_error _ -> ()

  let absorb_ticks progress fd buf =
    let rec go () =
      match Unix.read fd buf 0 (Bytes.length buf) with
      | 0 -> ()
      | n ->
          Progress.add progress n;
          if n = Bytes.length buf then go ()
      | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> go ()
    in
    go ()

  (* Waits for [child]'s result to start arriving, draining every worker's
   ticks and moving the elapsed clock meanwhile. Purely advisory: the
   timeout only paces redraws, and the read below is the same blocking read
   it always was. *)
  let await ~progress ~ticks child =
    let buf = Bytes.create 4096 in
    let rec go () =
      absorb_ticks progress ticks buf;
      match Unix.select [ ticks; child.read_fd ] [] [] 0.1 with
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> go ()
      | ready, _, _ ->
          if not (List.memq child.read_fd ready) then begin
            Progress.refresh progress;
            go ()
          end
    in
    go ()

  (* Sequential drain is deadlock-free: each child writes once and closes, the
   parent writes nothing, so a child blocked on a full pipe waits its turn. *)
  let drain ~progress ~ticks child =
    await ~progress ~ticks child;
    let ic = Unix.in_channel_of_descr child.read_fd in
    let outcome =
      match (Marshal.from_channel ic : wire) with
      | wire -> Ok wire
      | exception (End_of_file | Failure _) -> Error ()
    in
    close_in ic;
    let _, status = Unix.waitpid [] child.pid in
    match (outcome, status) with
    | Ok wire, Unix.WEXITED 0 -> Ok wire
    | (Ok _ | Error ()), status ->
        Error
          (match status with
          | Unix.WEXITED n -> Printf.sprintf "exited %d" n
          | Unix.WSIGNALED n -> Printf.sprintf "killed by %s" (signal_name n)
          | Unix.WSTOPPED n -> Printf.sprintf "stopped by %s" (signal_name n))

  (* {1 The parent pass} *)

  let check ~progress ~jobs ~cache ~rules ~catalog ~keep ~roster ~build_current
      =
    let entries = Roster.entries roster in
    let jobs = min jobs (List.length entries) in
    if jobs < 2 then None
    else begin
      let shards = split ~shards:jobs entries in
      let cmi_dirs = Roster.cmi_dirs roster in
      let ticks, tick_w = Unix.pipe ~cloexec:true () in
      Unix.set_nonblock ticks;
      Unix.set_nonblock tick_w;
      let children =
        List.mapi
          (fun idx shard ->
            fork_shard ~idx (fun () ->
                run_shard ~progress:(tick tick_w) ~cache ~rules ~catalog
                  ~build_current ~cmi_dirs shard))
          shards
      in
      let outcomes = List.map (drain ~progress ~ticks) children in
      Unix.close tick_w;
      Unix.close ticks;
      (* One result per entry — payload bytes ([Left]) or a skip ([Right]).
       "Every entry has exactly one row" is a property of this one table:
       every arm below (a wire row, a lost shard) writes it, so the
       defensive arms of the two engine callbacks are visibly unreachable.
       [snapshots] stays separate: keyed by path, the renderer's interface. *)
      let results : (Roster.Entry.t, (string, Unit.Skip.t) Either.t) Hashtbl.t =
        Hashtbl.create 256
      in
      let snapshots : (string, Source.t) Hashtbl.t = Hashtbl.create 256 in
      let lose shard describe =
        (* One lost shard: reported, counted as skips, run continues. *)
        Format.eprintf
          "litany: worker lost (%s); %d unit%s of its shard skipped@." describe
          (List.length shard)
          (if List.length shard = 1 then "" else "s");
        List.iter
          (fun entry ->
            Hashtbl.replace results entry
              (Either.Right
                 (Unit.Skip.Unreadable ("worker lost (" ^ describe ^ ")"))))
          shard
      in
      List.iter2
        (fun shard outcome ->
          match outcome with
          | Error describe -> lose shard describe
          | Ok wire when List.length wire.rows <> List.length shard ->
              lose shard "garbled result"
          | Ok wire ->
              Option.iter
                (fun c ->
                  Result_cache.absorb_counts c ~hits:wire.cache_hits
                    ~misses:wire.cache_misses ~stores:wire.cache_stores
                    wire.cache_hit_keys)
                cache;
              List.iter2
                (fun entry row ->
                  match row with
                  | Skipped sk ->
                      Hashtbl.replace results entry (Either.Right sk)
                  | Admitted { payload; source; intf } ->
                      Hashtbl.replace results entry (Either.Left payload);
                      let path = Roster.Entry.source entry in
                      Hashtbl.replace snapshots path (Source.v ~path source);
                      Option.iter
                        (fun (ipath, bytes) ->
                          Hashtbl.replace snapshots ipath
                            (Source.v ~path:ipath bytes))
                        intf)
                shard wire.rows)
        shards outcomes;
      (* One assembly pass over the full roster: payloads replay through the
       engine's unit cache, skips answer through [load], and the parent
       touches no resolver, artifact, or source file. Everything downstream —
       total order, dedup, project status, exit law — is the ordinary run. *)
      let unit_cache =
        {
          Engine.Unit_cache.load =
            (fun entry ->
              match Hashtbl.find_opt results entry with
              | Some (Either.Left payload) -> Some payload
              | Some (Either.Right _) | None -> None);
          store = (fun _ _ -> ());
        }
      in
      let load entry =
        Error
          (match Hashtbl.find_opt results entry with
          | Some (Either.Right sk) -> sk
          | Some (Either.Left _) | None ->
              (* Unreachable: the engine consults [load] only below a [None]
               from the cache, and every entry has exactly one row. *)
              Unit.Skip.Unreadable "worker result missing")
      in
      let report =
        Engine.run ?keep ~unit_cache ~rules ~catalog ~roster ~load ()
      in
      Some (report, snapshots)
    end
end

let resolver_of roster =
  Naming.Resolver.create
    ~cmi_dirs:(Roster.cmi_dirs roster @ [ Config.standard_library ])

(* The by-reason grouping key: [Unit.Skip]'s machine slug, sorted by
   its declaration-order rank — the same key the renderer's summary uses. *)
let skip_rank_slug sk = (Unit.Skip.rank sk, Unit.Skip.slug sk)

(* The admission listing, behind [--list-units]: load every entry, print units and
   skips in (source, artifact) order, then the counted summary. *)
let listing roster ~build_current =
  let resolver = resolver_of roster in
  let entries =
    (* The listing's order is its own law: by source path, then artifact. *)
    List.sort
      (fun e e' ->
        match
          String.compare (Roster.Entry.source e) (Roster.Entry.source e')
        with
        | 0 ->
            Option.compare String.compare (Roster.Entry.cmt e)
              (Roster.Entry.cmt e')
        | c -> c)
      (Roster.entries roster)
  in
  let skips = Hashtbl.create 8 in
  let admitted = ref 0 in
  List.iter
    (fun entry ->
      match Unit.load ~resolver ~build_current entry with
      | Ok u ->
          incr admitted;
          Printf.printf "unit %s (%s%s)\n" (Unit.path u)
            (match Unit.Witness.kind (Unit.witness u) with
            | Direct -> "direct"
            | Derived -> "derived")
            (* A unit the generated classifier reclassifies to
               facts-only is named here, not just counted — the marker is
               lexical and spoofable, so its consequence must be
               traceable. *)
            (match Unit.generated u with
            | Some why -> ", generated: " ^ why
            | None -> "")
      | Error sk ->
          let key = skip_rank_slug sk in
          Hashtbl.replace skips key
            (1 + Option.value (Hashtbl.find_opt skips key) ~default:0);
          Printf.printf "skip %s (%s)\n"
            (Roster.Entry.source entry)
            (Unit.Skip.message sk))
    entries;
  let total = List.length entries in
  let skipped = total - !admitted in
  let by_reason =
    List.map
      (fun ((_, slug), n) -> Printf.sprintf "%s %d" slug n)
      (List.sort compare (Hashtbl.fold (fun k n acc -> (k, n) :: acc) skips []))
  in
  Printf.printf "summary: %d entries, %d admitted, %d skipped%s\n" total
    !admitted skipped
    (if by_reason = [] then ""
     else Printf.sprintf " (%s)" (String.concat ", " by_reason));
  if Roster.project_capable roster then print_string "roster: complete\n"
  else print_string "roster: none (project rules unavailable)\n"

(* {1 Fix application} *)

(* [build_scoped path] is [true] for paths [--fix] must never write: anything
   under a [_build] tree, and dune-generated [.ml-gen] modules. Findings can
   anchor there when a walk root covers the build tree (a generated unit's
   only source is its build copy); fixing them mutates dune's cache at best
   and corrupts it at worst. The refusal prints — silence is
   enumerated. *)
let build_scoped path = under_build path || Filename.check_suffix path ".ml-gen"
let word n s = if n = 1 then s else s ^ "s"
let fixes n = if n = 1 then "fix" else "fixes"

(* {2 The corrections sink}

   The sandboxed-action fix lane (dune lang 3.23): fixes are never written
   to the sources — the Law-8 pipeline runs in memory ([Apply.correct]
   under the same digest baseline as the disk mode) and the fixed bytes
   land at [<sandbox mirror>/<source path>.corrected], where dune pairs
   each with the file it corrects at action teardown, prints the diff
   anchored at the source, fails the build, and registers promotion —
   [dune promote] is the one writer of the tree. The sink speaks
   [Apply.outcome] so the pass narration below is shared verbatim with the
   disk mode. *)

let rec mkdir_p dir =
  if not (Sys.file_exists dir) then begin
    let parent = Filename.dirname dir in
    if not (String.equal parent dir) then mkdir_p parent;
    try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

(* [propose_file] is [Apply.file] with the write redirected: same plan,
   same freshly-read digest re-check against the admission baseline, same
   in-memory correct (reparse-verify included) — then the fixed bytes go
   to [dest] (parents created) instead of over [path]. A plain write, not
   [Write.atomic]: [dest] is inside this action's private sandbox, read
   once by dune at teardown, never a published file. *)
let propose_file ?unsafe ~path ~baseline ~dest cands =
  let write_dest bytes =
    match
      mkdir_p (Filename.dirname dest);
      Out_channel.with_open_bin dest (fun oc ->
          Out_channel.output_string oc bytes)
    with
    | () -> Ok ()
    | exception Sys_error msg -> Error msg
    | exception Unix.Unix_error (err, _, arg) ->
        Error (Printf.sprintf "%s: %s" arg (Unix.error_message err))
  in
  let p = Apply.plan ?unsafe cands in
  let outcome =
    match Apply.selected p with
    | [] -> Apply.Nothing_to_apply
    | _ -> (
        match In_channel.with_open_bin path In_channel.input_all with
        | exception Sys_error msg -> Apply.Io_error msg
        | bytes -> (
            if not (Digest0.matches ~recorded:baseline bytes) then Apply.Stale
            else
              match Apply.correct ?unsafe bytes cands with
              | Error `Unverifiable -> Apply.Unverifiable
              | Error (`Fixer_bug _) -> Apply.Fixer_bug
              | Ok fixed -> (
                  match write_dest fixed with
                  | Ok () -> Apply.Applied
                  | Error msg -> Apply.Io_error msg)))
  in
  (p, outcome)

type pass_result = {
  applied : int;  (** Fixes written this pass. *)
  unsafe_applied : int;  (** The [Unsafe] subset of [applied]. *)
  files : string list;  (** Paths written this pass. *)
  bug : bool;  (** A fixer bug surfaced (exit 3). *)
  log : (string * string * string) list;
      (** (path, rule, title) per applied fix — the stop contract's list. *)
}

type totals = {
  run_applied : int;
  run_log : (string * string * string) list;
  run_bug : bool;
}
(** Run-spanning totals, threaded through the convergence recursion — the
    summary's applied count, the stop contract's cumulative list, and the exit-3
    latch. *)

(* One [--fix] pass over the report's kept findings — suppressed and expected
   findings never reach here ([Report.findings] excludes them by
   construction). Per file: fixes applied under the admission-time digest
   baseline (the never-write-unverified-bytes discipline lives in
   [Apply]), conflict losers deferred
   deterministically. The deferral wording is tense-neutral — whether a
   later pass or a re-run picks the losers up is the loop's business, and
   the loop already narrates it (the cap line, the one-pass lane's converge
   message) — so the pass needs no knowledge of its position in the run.

   [into] selects the sink: [None] writes the sources ([Apply.file], the
   terminal and unsandboxed-action lanes); [Some dir] proposes dune
   corrections instead ([propose_file] into the sandbox mirror [dir]) and
   the narration says "proposed" where the disk mode says "applied" — the
   fixes are applied into the corrected bytes, but the tree is dune's to
   write. Everything else — grouping, the build-tree refusal, the stale
   and fixer-bug lines, the counters — is one code path. *)
let apply_pass ~unsafe ~into report ~baselines =
  let applied_word =
    match into with None -> "applied" | Some _ -> "proposed"
  in
  let by_path : (string, Apply.candidate list) Hashtbl.t = Hashtbl.create 8 in
  List.iter
    (fun (rule, f) ->
      match Finding.fix f with
      | None -> ()
      | Some fix ->
          let path = (Finding.loc f).Location.loc_start.pos_fname in
          Hashtbl.replace by_path path
            ({ Apply.rule; fix }
            :: Option.value (Hashtbl.find_opt by_path path) ~default:[]))
    (Engine.Report.findings report);
  let paths =
    List.sort String.compare (Hashtbl.fold (fun p _ acc -> p :: acc) by_path [])
  in
  (* Fold with the record as the accumulator, no refs;
     [files] and [log] accumulate reversed and are put back in
     path/application order once at the end, so the total cost stays
     linear in applied fixes (a tail-append per fix is O(F²) — noise
     at store scale, a wall at bulk-monorepo scale). *)
  let acc =
    List.fold_left
      (fun acc path ->
        let cands = List.rev (Hashtbl.find by_path path) in
        if build_scoped path then begin
          Printf.printf "fix %s: refused — build-tree path (%s)\n" path
            (match into with
            | None -> "litany never writes into _build"
            | Some _ -> "a correction must pair with a source file");
          acc
        end
        else
          match Hashtbl.find_opt baselines path with
          | None -> acc (* findings only anchor in loaded units *)
          | Some baseline -> (
              let plan, outcome =
                match into with
                | None -> Apply.file ~unsafe ~path ~baseline cands
                | Some dir ->
                    (* The corrected file mirrors the source's
                       context-relative path — the context mirrors the
                       source root, so the finding's root-relative anchor
                       is exactly the path dune pairs the correction
                       by. *)
                    propose_file ~unsafe ~path ~baseline
                      ~dest:(Filename.concat dir (path ^ ".corrected"))
                      cands
              in
              let counted n word' =
                if n = 0 then [] else [ Printf.sprintf "%d %s" n word' ]
              in
              match outcome with
              | Apply.Applied | Apply.Nothing_to_apply ->
                  let selected = Apply.selected plan in
                  let conflicting = Apply.conflicting plan in
                  let deferral = "deferred (conflicts with an applied fix)" in
                  let segments =
                    String.concat ", "
                      (Printf.sprintf "%d %s" (List.length selected)
                         applied_word
                      :: (counted (List.length conflicting) deferral
                         @ counted
                             (List.length (Apply.excluded plan))
                             "excluded (unsafe or display-only)"))
                  in
                  Printf.printf "fix %s: %s\n" path segments;
                  let written = outcome = Apply.Applied in
                  let unsafe_n =
                    List.length
                      (List.filter
                         (fun (c : Apply.candidate) ->
                           Fix.applicability c.fix = Fix.Unsafe)
                         selected)
                  in
                  {
                    applied = acc.applied + List.length selected;
                    unsafe_applied = acc.unsafe_applied + unsafe_n;
                    files = (if written then path :: acc.files else acc.files);
                    bug = acc.bug;
                    log =
                      List.fold_left
                        (fun log (c : Apply.candidate) ->
                          (path, c.rule, Fix.title c.fix) :: log)
                        acc.log selected;
                  }
              | Apply.Stale ->
                  Printf.printf
                    "fix %s: not %s — the file changed since analysis; re-run\n"
                    path applied_word;
                  acc
              | Apply.Fixer_bug ->
                  Printf.printf
                    "fix %s: fixer bug — a rule constructed an invalid fix \
                     (the result does not parse, changes nothing, or an edit \
                     was out of bounds); file left unchanged\n"
                    path;
                  { acc with bug = true }
              | Apply.Unverifiable ->
                  Printf.printf
                    "fix %s: not %s — the source does not parse, so the result \
                     cannot be verified\n"
                    path applied_word;
                  acc
              | Apply.Io_error msg ->
                  Printf.printf "fix %s: error — %s\n" path msg;
                  acc))
      { applied = 0; unsafe_applied = 0; files = []; bug = false; log = [] }
      paths
  in
  { acc with files = List.rev acc.files; log = List.rev acc.log }

(* {1 The run} *)

(* One engine pass: load each entry once, retaining each admitted unit's
   source snapshot — excerpts must render exactly the bytes the run analyzed
   (the renderer's [source_of_path] obligation), the witness digest is the
   write baseline under [--fix], and the snapshot is what end-of-run
   revalidation compares against. [jobs > 1] takes the sharded lane
   (Parallel: forked workers, one parent assembly pass — the page is
   byte-identical across worker counts); the sharded lane never runs under
   [--fix], so its empty baselines table is never consulted. Either lane
   loads and stores through the result cache when one is set up. *)
let run_engine ~progress ~label ~jobs ~cache roster ~build_current ~rules
    ~catalog ~keep =
  let total = List.length (Roster.entries roster) in
  Progress.jobs progress (max 1 (min jobs total));
  Progress.counting progress ~label ~total;
  match
    if jobs > 1 then
      Parallel.check ~progress ~jobs ~cache ~rules ~catalog ~keep ~roster
        ~build_current
    else None
  with
  | Some (report, snapshots) ->
      Progress.clear progress;
      (report, snapshots, Hashtbl.create 1)
  | None ->
      let resolver = resolver_of roster in
      let snapshots = Hashtbl.create 32 in
      let baselines = Hashtbl.create 32 in
      let unit_cache =
        Option.map
          (fun c ->
            Result_cache.unit_cache c ~build_current ~snapshots ~baselines)
          cache
      in
      let load entry =
        match Unit.load ~resolver ~build_current entry with
        | Ok u ->
            Hashtbl.replace snapshots (Unit.path u) (Unit.source u);
            Hashtbl.replace baselines (Unit.path u)
              (Unit.Witness.source_digest (Unit.witness u));
            (* The interface text lane's file joins both tables under its
               own path: excerpts must render the bytes the run analyzed,
               [--fix] needs a write baseline for mli fixes, and end-of-run
               revalidation re-reads it like any analyzed source. *)
            Option.iter
              (fun isrc ->
                let ipath = Source.path isrc in
                Hashtbl.replace snapshots ipath isrc;
                Hashtbl.replace baselines ipath
                  (Digest.BLAKE128.string (Source.contents isrc)))
              (Unit.interface_source u);
            Ok u
        | Error _ as e -> e
      in
      let report =
        Engine.run ?keep ?unit_cache
          ~progress:(fun () -> Progress.tick progress)
          ~rules ~catalog ~roster ~load ()
      in
      Progress.clear progress;
      (report, snapshots, baselines)

(* End-of-run revalidation: re-read each admitted
   source at render and demote any unit whose bytes changed since analysis —
   findings against bytes that no longer exist become a counted skip, never a
   report. [written] excludes the files this run's own final fix pass wrote:
   litany's writes are digest-guarded at the write, not evidence of outside
   interference. *)
let revalidate report snapshots ~written =
  (* [written] as a set: the exclusion test runs once per admitted unit
     ([List.mem] would be O(admitted × written)). *)
  let written_set = Hashtbl.create 16 in
  List.iter (fun p -> Hashtbl.replace written_set p ()) written;
  Hashtbl.fold
    (fun path snapshot rep ->
      if Hashtbl.mem written_set path then rep
      else
        let unchanged =
          match In_channel.with_open_bin path In_channel.input_all with
          | bytes -> String.equal bytes (Source.contents snapshot)
          | exception Sys_error _ -> false
        in
        if unchanged then rep
        else Engine.Report.demote ~path Unit.Skip.Modified_during_run rep)
    snapshots report

(* The convergence cap: a measured dial, not a contract. Three
   build-spanning passes settle every fixture and corpus measured so far;
   leftovers are reported, never looped silently. *)
let max_passes = 3

(* The convergence loop's progress witness: a digest of the
   pass's kept-finding multiset — (rule, anchor path, byte span, message)
   per finding, order-independent, duplicates counted. Two passes with
   equal fingerprints present the same lint state to the fix planner, so
   applying again can only reproduce the repeat: a repeat of the
   immediately preceding pass means the applied fixes resolved nothing; a
   repeat of an earlier pass means antagonistic fixes are undoing each
   other. Either way the loop must stop honestly instead of burning the
   cap and advising a re-run that can never converge. *)
let findings_fingerprint findings =
  let entry (rule, f) =
    let loc = Finding.loc f in
    Printf.sprintf "%s\x00%s\x00%d\x00%d\x00%s" rule
      loc.Location.loc_start.Lexing.pos_fname
      loc.Location.loc_start.Lexing.pos_cnum
      loc.Location.loc_end.Lexing.pos_cnum (Finding.message f)
  in
  Digest.BLAKE128.string
    (String.concat "\x01" (List.sort String.compare (List.map entry findings)))

(* The specced stop contract (doc/dev/design.md, Fixes): a post-fix
   build failure stops the run — build error first (it already streamed),
   then the applied-fix list, then the exact stderr line scripts may grep
   for; the tree is deliberately left modified. The exit is the caller's,
   through [exit_of Refused] — the precedence law's home. *)
let stop_after_build_failure err ~log =
  Format.eprintf "litany: %a@." Adapter.Dune.pp_error err;
  List.iter
    (fun (path, rule, title) ->
      Format.eprintf "applied fix: %s [%s]: %s@." path rule title)
    log;
  Format.eprintf "files were modified; git diff shows the applied fixes@."

(* The report formats. [Text] is the human page on stdout; the three
   machine formats render the report page only — the fix narration and the
   admission listing speak the text surface, so [--fix] and [--list-units]
   refuse them up front. *)
type format = Text | Compiler | Json | Github

let render_page report snapshots ~format ~fixes ~notes_detail =
  match format with
  | Text ->
      (* Color follows the terminal: ANSI on a tty unless NO_COLOR or a dumb
         TERM says otherwise; plain bytes into a pipe. *)
      let color =
        Unix.isatty Unix.stdout
        && Sys.getenv_opt "NO_COLOR" = None
        && Sys.getenv_opt "TERM" <> Some "dumb"
      in
      Render.text ~color ~fixes ~notes_detail
        ~source_of_path:(Hashtbl.find_opt snapshots)
        Format.std_formatter report;
      Format.pp_print_flush Format.std_formatter ()
  | Compiler ->
      (* The renderer's driver obligations: stderr with stdout completely
         silent (dune gates on [stdout ^ stderr] starting with [File ]);
         exit 1 on findings is the report's own code. *)
      Render.compiler Format.err_formatter report;
      Format.pp_print_flush Format.err_formatter ()
  | Json ->
      Render.json Format.std_formatter report;
      Format.pp_print_flush Format.std_formatter ()
  | Github ->
      Render.github Format.std_formatter report;
      Format.pp_print_flush Format.std_formatter ()

(* [--explain-withheld]: after the page, name what blocked which project
   rule — the report's per-rule disposition algebra spelled out rule-major,
   blockers in roster order. The flag also answers when nothing was
   withheld, so scripts need not parse the summary first; a rule whose
   [collect] failed gets its own withheld line and never rides the "ran
   over the complete universe" list — that list names exactly the rules
   whose report ran. *)
let explain_withheld_page report ~roster =
  (* Kind-gated local rules inactive in this lane ride their own withheld
     channel — silence is enumerated, never absorbed; spell them out before the
     project-rule dispositions. *)
  let kind_withheld = Engine.Report.withheld_rules report in
  List.iter
    (fun (rule, reason) -> Printf.printf "withheld %s: %s\n" rule reason)
    kind_withheld;
  match Engine.Report.project_rules report with
  | [] ->
      if kind_withheld = [] then
        print_string "withheld: no project rules selected; nothing withheld\n"
  | dispositions -> (
      let blocked =
        List.filter_map
          (fun (rule, block) -> Option.map (fun b -> (rule, b)) block)
          dispositions
      in
      let ran =
        List.filter_map
          (fun (rule, block) -> if block = None then Some rule else None)
          dispositions
      in
      match blocked with
      | (_, Engine.Report.Not_capable) :: _ ->
          (* Name the cause, not just the judgment: which capability the
             roster lacks, and — the common field case, a (test) stanza the
             dune adapter cannot describe — exactly which entries lack
             metadata. Not-capable blocks every rule identically, so the
             diagnosis prints once. *)
          let missing =
            List.filter
              (fun e ->
                Roster.Entry.library e = None || Roster.Entry.kind e = None)
              (Roster.entries roster)
          in
          let causes =
            (if Roster.complete roster then []
             else [ "the adapter did not assert the roster complete" ])
            @
            match missing with
            | [] -> []
            | _ ->
                let n = List.length missing in
                let named, elided =
                  if n <= 5 then (missing, "")
                  else
                    ( List.filteri (fun i _ -> i < 5) missing,
                      Printf.sprintf " (and %d more)" (n - 5) )
                in
                [
                  Printf.sprintf
                    "%d %s lack library/kind metadata: %s%s (dune (test) \
                     stanzas are not described to the adapter)"
                    n
                    (if n = 1 then "entry" else "entries")
                    (String.concat ", " (List.map Roster.Entry.source named))
                    elided;
                ]
          in
          Printf.printf
            "withheld: project rules unavailable — the roster is not \
             project-capable%s\n"
            (match causes with
            | [] -> ""
            | causes -> ": " ^ String.concat "; " causes)
      | _ -> (
          List.iter
            (fun (rule, block) ->
              match block with
              | Engine.Report.Not_capable -> ()
              | Engine.Report.Incomplete blocking ->
                  List.iter
                    (fun (path, sk) ->
                      Printf.printf "withheld %s: blocked by %s (%s)\n" rule
                        path (Unit.Skip.message sk))
                    blocking
              | Engine.Report.Ambiguous dups ->
                  List.iter
                    (fun (name, paths) ->
                      Printf.printf
                        "withheld %s: duplicate compilation unit name %s: %s — \
                         cross-module identity is keyed by unit name\n"
                        rule name (String.concat ", " paths))
                    dups
              | Engine.Report.Collect_failed paths ->
                  List.iter
                    (fun path ->
                      Printf.printf
                        "withheld %s: collect failed on %s (see the rule \
                         failure)\n"
                        rule path)
                    paths)
            blocked;
          match ran with
          | [] -> ()
          | ran ->
              if blocked = [] then
                Printf.printf
                  "withheld: nothing — %s ran over the complete universe\n"
                  (String.concat ", " ran)
              else
                Printf.printf
                  "withheld: nothing else — %s ran over the complete universe\n"
                  (String.concat ", " ran)))

(* The all-skip escalation gate, the policy the unit contract places
   above the loader (Unit.Skip's headnote) — the wrong-compiler
   ("cmt magic mismatch") refusal, generalized to every all-skip cause: a
   non-empty roster of which nothing was analyzed — zero
   linted, zero facts-only, every unit skipped, whatever the mix of skip
   kinds — is a refusal, never an all-skipped success. A run that skipped
   everything analyzed nothing, and "ran fine, reported nothing" must not
   read as quietly green at the one byte CI reads — silence must stay
   distinguishable from cleanliness. The page
   still renders first — the skip listing is the diagnosis — then the
   refusal is the verdict. Any analyzed unit in the mix keeps the
   per-unit skip behavior: mixed stores are the common case (one
   measured real store was 67% foreign) and stay counted skips. An empty
   roster analyzed nothing
   because there was nothing; it stays the honest empty report.
   [--list-units] never escalates: the listing is the diagnosis surface
   for exactly this state.

   The gate speaks two messages. The specialized arm
   ([wholesale_mismatch]): every unit a wrong-magic skip under one same
   foreign compiler generation — a workspace wholesale-built by another
   compiler — refuses naming both versions and the one remedy.
   Generation, not magic bytes: one compiler writes two magics — a cmt
   whose module has no mli leads with its embedded cmi block's magic —
   so a single foreign store surfaces both, and raw-magic equality read
   a wholesale 5.5 store (176 [Caml1999I037] beside 488 [Caml1999T037]
   in one large application store) as mixed. The equality is
   [Unit.Skip.same_generation], the refusal-side counterpart of
   admission accepting both of this compiler's magics. The general arm
   catches every other all-skip roster — all-stale, all-unreadable, a
   second foreign generation, any mixture — with the skip breakdown and
   the remedy per kind. *)
let all_skipped report =
  match Engine.Report.units report with
  | [] -> None
  | units ->
      let skips =
        List.filter_map
          (fun (_, outcome) ->
            match (outcome : Engine.Report.outcome) with
            | Skipped sk -> Some sk
            | Linted | Facts_only -> None)
          units
      in
      if List.compare_lengths skips units = 0 then Some skips else None

(* One remedy per skip kind, for the general arm's refusal line. *)
let skip_remedy = function
  | Unit.Skip.Stale | Unit.Skip.Modified_during_run -> "rebuild, then re-run"
  | Unit.Skip.Wrong_magic _ ->
      "install litany in the switch that built these artifacts"
  | Unit.Skip.Missing_source -> "restore the missing sources"
  | Unit.Skip.Missing_artifact -> "build the project, then re-run"
  | Unit.Skip.Unreadable _ -> "rebuild to regenerate the artifacts"
  | Unit.Skip.Derived_needs_build ->
      "re-run with the build step so derived sources carry its evidence"
  | Unit.Skip.Partial_or_packed ->
      "point litany at the unpacked implementation units"

(* The skip kinds present, in slug rank order, each with its count and
   remedy: "stale 2 (rebuild, then re-run); unreadable 1 (...)". *)
let skip_breakdown skips =
  let tally = Hashtbl.create 8 in
  List.iter
    (fun sk ->
      let rank = Unit.Skip.rank sk in
      match Hashtbl.find_opt tally rank with
      | Some (n, first) -> Hashtbl.replace tally rank (n + 1, first)
      | None -> Hashtbl.add tally rank (1, sk))
    skips;
  Hashtbl.fold (fun rank group acc -> (rank, group) :: acc) tally []
  |> List.sort (fun (rank, _) (rank', _) -> Int.compare rank rank')
  |> List.map (fun (_, (n, sk)) ->
      Printf.sprintf "%s %d (%s)" (Unit.Skip.slug sk) n (skip_remedy sk))
  |> String.concat "; "

let wholesale_mismatch report =
  match Engine.Report.units report with
  | (_, Engine.Report.Skipped (Unit.Skip.Wrong_magic first)) :: rest
    when List.for_all
           (fun (_, outcome) ->
             match outcome with
             | Engine.Report.Skipped (Unit.Skip.Wrong_magic { found; _ }) ->
                 Unit.Skip.same_generation found first.found
             | Linted | Facts_only | Skipped _ -> false)
           rest ->
      Some (Unit.Skip.Wrong_magic first)
  | _ -> None

(* One mode surface, the illegal combinations unrepresentable: [fix] is an
   option record — no [--unsafe] without [--fix]; [rebuild] is the build
   capability — a lane converges iff it knows how to re-run its build, so
   the walk, no-build, and in-action lanes (rebuild = None) run exactly
   one pass by type, never by a flag recomputed elsewhere. The
   worker-count decision (default and the [--fix] serial clamp) lives here
   too, beside the invariant it guards: any thin bin composing this driver
   gets the clamp, so [--fix -j N] can never silently take the sharded
   lane, whose empty baselines table would apply nothing.

   Without [fix]: one pass, revalidate, render. With [fix]: apply after
   each pass; when [rebuild] is given convergence spans builds — rebuild,
   re-join, re-lint, deferred conflict losers picked up on later passes,
   capped at [max_passes] — while the one-pass lanes say so. Each pass is a
   complete run; a re-run continues converging. The oscillation and
   no-progress machinery observes repeats across passes of one run; a
   one-pass lane has none.

   [corrections] is the in-dune fix lane, and the only one (litany never
   writes a source from inside dune — the composition root refuses [--fix]
   at every other in-dune vantage): [Some dir] proposes fixes as dune
   corrections into the sandbox mirror [dir] instead of writing any
   source — dune diffs each corrected file against the source it corrects,
   fails the build, and registers promotion, so the single-writer
   principle in-dune is dune's own promotion flow; after [dune promote]
   the next build re-lints and the loop converges. The exit contract
   shifts with the sink: corrections were written → exit 0, whatever the
   report says — dune processes corrections only from actions that exit 0
   (a nonzero exit silently drops them), and the diffs themselves fail
   the build, so findings still gate; no corrections written → the normal
   law. Litany cannot see whether the invoking stanza carries
   (corrections produce) — without the field dune discards the corrected
   files silently, a green build with fixes dropped — so the proposal
   note always names the field. *)
type fix = { unsafe : bool; corrections : string option }

let run_check ~progress ~rebuild ~format ~jobs ~cache roster ~build_current
    ~rules ~catalog ~keep ~fix ~explain_withheld =
  let jobs =
    match (fix, jobs) with
    | Some _, given ->
        (* [--fix] stays single-process this release: the write lane and
           build-spanning convergence are serial by design
           (doc/dev/design.md, Result_cache and parallelism). An explicit worker
           count is noted and ignored, never a silent no-op. *)
        (match given with
        | Some n when n > 1 ->
            Format.eprintf
              "litany: --fix runs single-process this release; ignoring -j %d@."
              n
        | Some _ | None -> ());
        1
    | None, Some n -> n
    | None, None -> Parallel.default_jobs ()
  in
  (* The run-spanning state is one record threaded through the recursion,
     no refs. [run_log] grows
     by one [@] per pass — at most [max_passes] appends of final per-pass
     lists, linear overall. *)
  let totals = { run_applied = 0; run_log = []; run_bug = false } in
  (* Exit is the state of the tree left behind — the final pass's report,
     after revalidation — under [exit_of]'s declared precedence: a refusal
     outranks a fixer bug, a fixer bug anywhere in the run outranks a later
     clean pass. *)
  let finish report snapshots ~written ~roster totals =
    let report = revalidate report snapshots ~written in
    render_page report snapshots ~format
      ~fixes:
        (match fix with
        | Some { corrections = Some _; _ } -> `Proposed totals.run_applied
        | Some _ -> `Applied totals.run_applied
        | None -> `Hint)
      ~notes_detail:explain_withheld;
    if explain_withheld then explain_withheld_page report ~roster;
    (* [exit_of] first; the all-skip escalation claims only the byte that would
       otherwise read clean (it refuses silent success, never softens a
       louder exit). *)
    let code = exit_of Completed ~bug:totals.run_bug report in
    if code <> exit_ok then code
    else
      match all_skipped report with
      | None -> exit_ok
      | Some skips -> (
          (* The page above is the diagnosis; the refusal is the verdict
             — the specialized message when the whole store is
             one foreign generation, the breakdown-plus-remedies
             otherwise. *)
          match wholesale_mismatch report with
          | Some sk ->
              refuse "artifacts were %s — install litany in this switch"
                (Unit.Skip.message sk)
          | None ->
              refuse "nothing was analyzed — every unit was skipped: %s"
                (skip_breakdown skips))
  in
  let pass_line n result ~clean ~proposed =
    if result.applied > 0 then
      let files = List.length result.files in
      let detail =
        Printf.sprintf "%d %s%s" files (word files "file")
          (if result.unsafe_applied > 0 then
             Printf.sprintf ", %d unsafe" result.unsafe_applied
           else "")
      in
      if n = 1 then
        Printf.printf "pass 1: %d %s %s (%s)\n" result.applied
          (fixes result.applied)
          (if proposed then "proposed" else "applied")
          detail
      else
        Printf.printf "pass %d (rebuild + re-lint): %d %s applied (%s)\n" n
          result.applied (fixes result.applied) detail
    else if n > 1 then
      if clean then Printf.printf "pass %d (rebuild + re-lint): clean\n" n
      else Printf.printf "pass %d (rebuild + re-lint): findings remain\n" n
  in
  let rec pass n roster ~build_current totals ~fps =
    let report, snapshots, baselines =
      run_engine ~progress
        ~label:(if n = 1 then "" else Printf.sprintf "pass %d" n)
        ~jobs ~cache roster ~build_current ~rules ~catalog ~keep
    in
    match fix with
    | None -> finish report snapshots ~written:[] ~roster totals
    | Some { unsafe; corrections } -> (
        let fp = findings_fingerprint (Engine.Report.findings report) in
        match List.find_opt (fun (_, fp') -> String.equal fp' fp) fps with
        | Some (m, _) ->
            (* CS-FIX--01: this pass reproduced pass [m]'s finding multiset
               exactly — the loop made no progress, and applying again could
               only replay the same fixes onto the same lint state. Stop
               before writing anything further, and say why honestly: the
               cap message's "re-run to continue converging" would be false
               forever here. The page below is the evidence; the emitting
               rules' fixes are the bug. *)
            Printf.printf
              "pass %d (rebuild + re-lint): findings identical to pass %d — \
               %s; stopping (re-running --fix cannot converge; this is a bug \
               in the emitting rules' fixes)\n"
              n m
              (if m = n - 1 then "the applied fixes resolved nothing"
               else "antagonistic fixes are undoing each other");
            flush stdout;
            finish report snapshots ~written:[] ~roster totals
        | None -> (
            let result =
              apply_pass ~unsafe ~into:corrections report ~baselines
            in
            let totals =
              {
                run_applied = totals.run_applied + result.applied;
                run_log = totals.run_log @ result.log;
                run_bug = totals.run_bug || result.bug;
              }
            in
            pass_line n result
              ~clean:(Engine.Report.exit_code report = 0)
              ~proposed:(corrections <> None);
            (* The pass lines are stdout, the rebuild streams on stderr:
               flush at the boundary so a captured transcript interleaves
               determinately. *)
            flush stdout;
            if result.applied = 0 then
              finish report snapshots ~written:[] ~roster totals
            else
              match (corrections, rebuild) with
              | Some _, _ ->
                  (* The corrections one-pass note: no source was written —
                     the tree is dune's to change, through the diffs this
                     rule's corrected files become at teardown. The
                     (corrections produce) clause is named every time:
                     litany cannot see the invoking stanza, and without the
                     field dune discards the corrected files silently — a
                     green build with the fixes dropped must never pass
                     without this line having said so. *)
                  let files = List.length result.files in
                  Printf.printf
                    "%d %s proposed — dune shows each as a diff and fails the \
                     build; dune promote applies and the next build re-lints \
                     (without (corrections produce) in the rule, dune discards \
                     corrections silently)\n"
                    files (word files "correction");
                  (* Sources untouched, so nothing rides the [written]
                     exclusion; the exit must be 0 whatever the report says
                     — dune processes corrections only from actions that
                     exit 0, so any other byte here would silently drop the
                     fixes, while the diffs themselves already fail the
                     build. The page and its code still render first: the
                     transcript is the evidence either way. *)
                  let (_ : int) =
                    finish report snapshots ~written:[] ~roster totals
                  in
                  exit_ok
              | None, None ->
                  (* The one-pass direct-write lanes ([--units],
                     [--cmt-root], [--no-build]): this run cannot re-run
                     the roster's build, so convergence is the caller's
                     loop and the note says so. *)
                  Printf.printf
                    "%d %s applied — artifacts are now stale; rebuild and \
                     re-run to converge\n"
                    result.applied (fixes result.applied);
                  finish report snapshots ~written:result.files ~roster totals
              | None, Some rebuild -> (
                  if n >= max_passes then begin
                    Printf.printf
                      "pass cap (%d) reached — re-run litany check --fix to \
                       continue converging\n"
                      max_passes;
                    finish report snapshots ~written:result.files ~roster totals
                  end
                  else
                    match
                      Progress.phase progress "rebuilding";
                      Fun.protect
                        ~finally:(fun () -> Progress.clear progress)
                        rebuild
                    with
                    | Error err ->
                        stop_after_build_failure err ~log:totals.run_log;
                        exit_of Refused ~bug:totals.run_bug report
                    | Ok roster' ->
                        pass (n + 1) roster' ~build_current:true totals
                          ~fps:((n, fp) :: fps))))
  in
  pass 1 roster ~build_current totals ~fps:[]
