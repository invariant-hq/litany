(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* {1 Path and filesystem helpers}

   All artifact walking below is tolerant by design: dangling symlinks and
   unreadable entries are normal in artifact directories (one real
   [_build/install] held 212 dangling symlinks); a wrong pairing costs a skip
   at join time, never a finding. *)

let ( // ) a b =
  if b = "" then a else if a = "" || a = "." then b else Filename.concat a b

let is_real_dir path =
  match Sys.is_directory path with
  | is_dir -> is_dir
  | exception Sys_error _ -> false (* dangling symlink or unreadable *)

let is_artifact name =
  Filename.check_suffix name ".cmt" || Filename.check_suffix name ".cmti"

(* Directory-walk skeleton shared by [walk_artifacts] and [source_index].
   [Unix.stat] follows symlinks — a stat failure drops the entry (dangling
   symlink, unreadable) — and the visited [(st_dev, st_ino)] set makes
   symlink cycles terminate: a directory is descended into at most once.
   Depth-first with per-directory sorted names — deterministic for a given
   tree. *)
let walk_tree root ~prune ~file =
  let visited = Hashtbl.create 16 in
  let rec go rel_dir =
    match Sys.readdir (root // rel_dir) with
    | exception Sys_error _ -> ()
    | names ->
        Array.sort String.compare names;
        Array.iter
          (fun name ->
            if not (prune name) then
              let rel = rel_dir // name in
              match Unix.stat (root // rel) with
              | exception Unix.Unix_error _ -> ()
              | { Unix.st_kind = Unix.S_DIR; st_dev; st_ino; _ } ->
                  if not (Hashtbl.mem visited (st_dev, st_ino)) then begin
                    Hashtbl.add visited (st_dev, st_ino) ();
                    go rel
                  end
              | _ -> file ~rel ~name)
          names
  in
  go ""

(* [walk_artifacts dir] is the relative paths of every [.cmt]/[.cmti] under
   [dir]. *)
let walk_artifacts dir =
  let acc = ref [] in
  walk_tree dir
    ~prune:(fun _ -> false)
    ~file:(fun ~rel ~name -> if is_artifact name then acc := rel :: !acc);
  List.rev !acc

type unit_group = {
  rel_dir : string;
  base : string;  (** Artifact basename without extension. *)
  mutable cmt : string option;  (** Relative path within the walked root. *)
  mutable cmti : string option;
}

(* Artifacts grouped into candidate units by (directory, basename), in
   first-seen (deterministic) order. *)
let group_units rels =
  let tbl = Hashtbl.create 64 and order = ref [] in
  List.iter
    (fun rel ->
      let rel_dir = match Filename.dirname rel with "." -> "" | d -> d in
      let base = Filename.remove_extension (Filename.basename rel) in
      let key = rel_dir // base in
      let group =
        match Hashtbl.find_opt tbl key with
        | Some g -> g
        | None ->
            let g = { rel_dir; base; cmt = None; cmti = None } in
            Hashtbl.add tbl key g;
            order := g :: !order;
            g
      in
      if Filename.check_suffix rel ".cmt" then group.cmt <- Some rel
      else group.cmti <- Some rel)
    rels;
  List.rev !order

let strip_trailing drop rel_dir =
  let rec drop_leading = function
    | seg :: rest when drop seg -> drop_leading rest
    | segs -> segs
  in
  match
    List.rev (drop_leading (List.rev (String.split_on_char '/' rel_dir)))
  with
  | [] | [ "" ] -> ""
  | segs -> String.concat "/" segs

let mode_seg seg = String.equal seg "byte" || String.equal seg "native"

(* Dune object directories are [.lib.objs/byte] tails under the stanza
   directory; dropping dot-prefixed and mode segments recovers the source
   directory the artifacts belong to. *)
let clean_rel_dir =
  strip_trailing (fun seg ->
      mode_seg seg || (String.length seg > 0 && seg.[0] = '.'))

(* Keeps the object directory itself: generated namespace sources
   ([dune__exe.ml-gen]) live there, one level above [byte]. *)
let objs_rel_dir = strip_trailing mode_seg

(* [.NAME.eobjs] is the object directory of an executable-family stanza
   ([executable]/[executables]/[test]/[tests]) — NAME is the stanza's (first)
   name. [eobjs_stanza rel_dir] recovers the stanza's source directory and
   that name from an artifact directory beneath it; [None] when [rel_dir]
   descends through no such directory (library [.objs] trees). *)
let eobjs_stanza rel_dir =
  let rec go acc = function
    | [] -> None
    | seg :: rest ->
        let n = String.length seg in
        if n > 7 && seg.[0] = '.' && Filename.check_suffix seg ".eobjs" then
          Some (String.concat "/" (List.rev acc), String.sub seg 1 (n - 7))
        else go (seg :: acc) rest
  in
  go [] (String.split_on_char '/' rel_dir)

(* ["lib__Foo"] names module [Foo] of wrapped library [lib]; the source
   basename is the uncapitalized last [__] component. *)
let leaf_of base =
  let len = String.length base in
  let rec last_sep i found =
    if i + 1 >= len then found
    else if base.[i] = '_' && base.[i + 1] = '_' then last_sep (i + 2) (i + 2)
    else last_sep (i + 1) found
  in
  match last_sep 0 0 with 0 -> base | at -> String.sub base at (len - at)

(* Editable-source index of a source tree: basename -> sorted relative
   paths. Directories starting with ['.'] or ['_'] never hold editable
   sources ([_build] copies must not be anchors), so they are pruned. *)
let source_index root =
  let tbl = Hashtbl.create 256 in
  walk_tree root
    ~prune:(fun name -> name = "" || name.[0] = '.' || name.[0] = '_')
    ~file:(fun ~rel ~name ->
      if Filename.check_suffix name ".ml" || Filename.check_suffix name ".mli"
      then
        Hashtbl.replace tbl name
          ((root // rel) :: Option.value (Hashtbl.find_opt tbl name) ~default:[]));
  (* Deterministic buckets: candidates in path order. *)
  Hashtbl.filter_map_inplace
    (fun _ paths -> Some (List.sort String.compare paths))
    tbl;
  tbl

(* [segments p] is [p]'s path components, empty and [.] segments dropped, so
   textual prefix comparison works on relative and absolute paths alike. *)
let segments p =
  List.filter (fun s -> s <> "" && s <> ".") (String.split_on_char '/' p)

let rec shared_prefix n a b =
  match (a, b) with
  | x :: a', y :: b' when String.equal x y -> shared_prefix (n + 1) a' b'
  | _ -> n

(* The pairing heuristic, shared by [Walk] and the dune union walk. The
   editable candidate always wins over build-tree copies — a [_build] copy is
   never the anchor except for generated units whose only source is in
   [_build] ([.ml-gen] alias modules and kin). [lookup] is the caller's
   basename index of the source tree (empty for the union walk). A wrong
   pick costs a skip.

   The basename fallback is proximity-scoped, never global. Over a
   store holding several unrelated trees (a [.pkg] dependency store, two
   compiler versions side by side), a global first-in-sorted-order pick
   pairs a cmt in package A with a same-basename source in package B — the
   digest witness then refuses the join as a stale skip (20% of a real
   store's units), or, worse, accepts a byte-identical copy and reports
   findings under the other package's path. The fallback therefore keeps
   only the candidates whose directory shares the longest leading-segment
   prefix with the artifact's own directory, and demands at least one
   shared segment below the walked root — an artifact never pairs outside
   the top-level subtree it lives in. No candidate in the artifact's
   subtree means no source: an honest missing-source skip. Artifacts at
   the walk root itself have no subtree to scope by; every candidate is
   equally near and the sorted-first pick stands.

   The one-segment floor is a package boundary only for flat store
   layouts (packages at the root's immediate children). A walk root whose
   projects share a parent segment — [duniverse/*], [packages/*],
   [vendor/*] — satisfies the floor via the shared parent alone, and the
   fallback regresses to a cross-package pick one level down: an artifact
   in [duniverse/x] with no in-package candidate scores root+1 against a
   same-basename source in [duniverse/y]. The floor cannot simply be
   raised — a legitimate in-package pair ([pkga/objs/bar.cmt] ↔
   [pkga/src/bar.ml]) shares only root+1 — so the scope uses boundary
   knowledge where it exists: when the artifact's own ancestry, strictly
   below the walked root, holds a project marker ([dune-project], [.git],
   a [*.opam] file — [project_boundary]), the deepest marked directory is
   the boundary and a candidate must share every segment down to it.
   Without a marker the one-segment floor stands, so the guarantee is:
   the artifact's innermost marked project when its tree declares one,
   its top-level subtree of the walked root otherwise. *)
let pair_source ~exists ~project_boundary ~editable_root ~build_root ~lookup
    ~rel_dir ~base ~intf_only =
  let clean = clean_rel_dir rel_dir in
  let leaf = String.uncapitalize_ascii (leaf_of base) in
  let ext = if intf_only then ".mli" else ".ml" in
  let editable = editable_root // clean // (leaf ^ ext) in
  if exists editable then editable
  else
    let nearest =
      let artifact_dir = segments (editable_root // clean) in
      let root_len = List.length (segments editable_root) in
      let score p =
        shared_prefix 0 artifact_dir (segments (Filename.dirname p))
      in
      let floor =
        let rec deepest_marked dir =
          if List.length (segments dir) <= root_len then None
          else if project_boundary dir then Some (List.length (segments dir))
          else deepest_marked (Filename.dirname dir)
        in
        match
          if clean = "" then None else deepest_marked (editable_root // clean)
        with
        | Some marked -> marked
        | None -> root_len + 1
      in
      let best =
        List.fold_left
          (fun best p ->
            let s = score p in
            match best with
            | Some (s', _) when s' >= s -> best
            | _ -> Some (s, p))
          None
          (lookup (leaf ^ ext))
      in
      match best with
      | Some (s, p) when s >= floor || clean = "" -> Some p
      | Some _ | None -> None
    in
    match nearest with
    | Some p -> p
    | None ->
        let gen_candidates =
          if intf_only then []
          else
            [
              build_root // clean // (leaf ^ ".ml-gen");
              build_root // objs_rel_dir rel_dir // (base ^ ".ml-gen");
            ]
        in
        let candidates =
          (build_root // clean // (leaf ^ ext)) :: gen_candidates
        in
        Option.value (List.find_opt exists candidates) ~default:editable

(* A directory is a project boundary when it holds a project marker —
   [dune-project], [.git] (file or directory: worktrees), or a [*.opam]
   file. Memoized per directory: the walk asks along every artifact's
   ancestry. An unreadable directory is no boundary. *)
let project_boundary_probe () =
  let memo = Hashtbl.create 64 in
  fun dir ->
    match Hashtbl.find_opt memo dir with
    | Some b -> b
    | None ->
        let b =
          Sys.file_exists (dir // "dune-project")
          || Sys.file_exists (dir // ".git")
          ||
          match Sys.readdir dir with
          | exception Sys_error _ -> false
          | names ->
              Array.exists (fun n -> Filename.check_suffix n ".opam") names
        in
        Hashtbl.add memo dir b;
        b

let dedup xs =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun x ->
      if Hashtbl.mem seen x then false
      else (
        Hashtbl.add seen x ();
        true))
    xs

(* Allocation-free: [s] can be a whole captured build transcript. *)
let contains_substring ~sub s =
  let n = String.length sub and len = String.length s in
  n = 0
  ||
  let rec matches_at i j =
    j = n || (Char.equal s.[i + j] sub.[j] && matches_at i (j + 1))
  in
  let rec at i = i + n <= len && (matches_at i 0 || at (i + 1)) in
  at 0

(* {1 Subprocesses}

   The IO shore proper: only [Dune] spawns. The child runs with [root] as
   cwd (inherited across [create_process] by a chdir bracket — the process
   is single-threaded at adapter time). *)

let with_cwd dir f =
  let old = Sys.getcwd () in
  Sys.chdir dir;
  Fun.protect ~finally:(fun () -> Sys.chdir old) f

let path_has prog =
  match Sys.getenv_opt "PATH" with
  | None -> false
  | Some path ->
      List.exists
        (fun dir ->
          dir <> ""
          &&
          let candidate = Filename.concat dir prog in
          Sys.file_exists candidate && not (is_real_dir candidate))
        (String.split_on_char ':' path)

(* Bounded execution: both spawns bound what they retain in memory, and
   the silent spawn is additionally bounded in time. The build spawn
   deliberately has no timeout: a legitimate dune build may be arbitrarily
   long, and its output streams to the user who can interrupt it. *)

(* The retained-transcript bound for the forwarded build (classification
   reads only the leading bytes of dune's error output) and the reply bound
   for describe (a reply beyond this is a runaway, not a workspace). *)
let forward_capture_limit = 8 * 1024 * 1024
let describe_reply_limit = 256 * 1024 * 1024
let describe_timeout_seconds = 600.

(* Terminate a child that violated a bound: TERM, a short drain grace,
   then KILL; always reaped. *)
let terminate pid =
  (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
  let deadline = Unix.gettimeofday () +. 2.0 in
  let rec reap () =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
        if Unix.gettimeofday () > deadline then begin
          (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
          ignore (Unix.waitpid [] pid)
        end
        else begin
          ignore (Unix.select [] [] [] 0.05);
          reap ()
        end
    | _ -> ()
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> reap ()
  in
  reap ()

(* Runs [argv] with stdout and stderr merged into one stream that is both
   forwarded to our stderr as it arrives and captured — the build's output
   must stream through to the user, and the refusal classification needs to
   read it. Forwarding is unbounded; the retained copy stops growing at
   [forward_capture_limit] (classification degrades to the generic refusal,
   never to unbounded memory). *)
let run_forwarding ~progress ~root argv =
  let r, w = Unix.pipe ~cloexec:true () in
  let pid =
    with_cwd root (fun () -> Unix.create_process argv.(0) argv Unix.stdin w w)
  in
  Unix.close w;
  let buf = Buffer.create 1024 in
  let chunk = Bytes.create 8192 in
  (* The child's own output owns stderr while it flows: the meter's line is
     erased before a chunk is forwarded and redrawn on the next quiet poll, so
     a build that prints and a build that sits silent both read correctly. The
     poll timeout only paces the clock — the read below is the same read. *)
  let rec drain () =
    match Unix.select [ r ] [] [] 0.1 with
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> drain ()
    | [], _, _ ->
        Progress.refresh progress;
        drain ()
    | _ -> (
        match Unix.read r chunk 0 (Bytes.length chunk) with
        | 0 -> ()
        | n ->
            if Buffer.length buf < forward_capture_limit then
              Buffer.add_subbytes buf chunk 0 n;
            Progress.clear progress;
            output stderr chunk 0 n;
            flush stderr;
            drain ()
        | exception Unix.Unix_error (Unix.EINTR, _, _) -> drain ())
  in
  drain ();
  Unix.close r;
  let _, status = Unix.waitpid [] pid in
  (status, Buffer.contents buf)

(* Runs [argv] capturing stdout (the payload) and stderr (the diagnostic)
   separately; stderr goes through a temp file so reading one pipe to EOF
   cannot deadlock against the other filling up. Bounded both ways: the
   payload may not exceed [describe_reply_limit] and the whole spawn may
   not exceed [describe_timeout_seconds] — a violation terminates the
   child and returns [Error reason] (the caller's refusal detail); a
   silent litany-owned query has no business running unbounded. *)
let run_capturing ~progress ~root argv =
  let err_file = Filename.temp_file "litany-dune" ".stderr" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove err_file with Sys_error _ -> ())
    (fun () ->
      let err_fd =
        Unix.openfile err_file [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600
      in
      let r, w = Unix.pipe ~cloexec:true () in
      let pid =
        with_cwd root (fun () ->
            Unix.create_process argv.(0) argv Unix.stdin w err_fd)
      in
      Unix.close w;
      Unix.close err_fd;
      let deadline = Unix.gettimeofday () +. describe_timeout_seconds in
      let buf = Buffer.create 65536 in
      let chunk = Bytes.create 65536 in
      let violation reason =
        Unix.close r;
        terminate pid;
        Error reason
      in
      let rec drain () =
        let remaining = deadline -. Unix.gettimeofday () in
        if remaining <= 0. then
          violation
            (Printf.sprintf "no reply within %.0f seconds"
               describe_timeout_seconds)
        else
          (* Polled in short steps so the meter's clock keeps moving; the
             deadline is still the deadline — a poll that times out early
             just redraws and waits again. *)
          match Unix.select [ r ] [] [] (Float.min remaining 0.1) with
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> drain ()
          | [], _, _ when remaining > 0.1 ->
              Progress.refresh progress;
              drain ()
          | [], _, _ ->
              violation
                (Printf.sprintf "no reply within %.0f seconds"
                   describe_timeout_seconds)
          | _ -> (
              match Unix.read r chunk 0 (Bytes.length chunk) with
              | 0 ->
                  Unix.close r;
                  let _, status = Unix.waitpid [] pid in
                  Ok status
              | n ->
                  if Buffer.length buf + n > describe_reply_limit then
                    violation
                      (Printf.sprintf "reply exceeds %d MiB"
                         (describe_reply_limit / (1024 * 1024)))
                  else begin
                    Buffer.add_subbytes buf chunk 0 n;
                    drain ()
                  end
              | exception Unix.Unix_error (Unix.EINTR, _, _) -> drain ())
      in
      match drain () with
      | Error reason -> Error reason
      | Ok status ->
          let err =
            match In_channel.with_open_bin err_file In_channel.input_all with
            | s -> s
            | exception Sys_error _ -> ""
          in
          Ok (status, Buffer.contents buf, err))

let first_line s =
  match String.index_opt s '\n' with None -> s | Some i -> String.sub s 0 i

(* {1 The unit file} *)

module Unit_file = struct
  type error = { offset : int; reason : string }

  let pp_error ppf e =
    Format.fprintf ppf "unit file: byte %d: %s" e.offset e.reason

  (* {2 Csexp with offsets}

     A separate parser from [Dune_describe]'s: a unit file is a *sequence* of
     top-level forms, not one document, and every error must carry the byte
     offset of the offending form or atom, so values are position-annotated.
     Whitespace is tolerated between top-level forms only (encode ends each
     form with a newline, one greppable line per unit); inside a form the
     grammar is strict csexp. *)

  type sexp = Atom of int * string | List of int * sexp list

  let offset_of = function Atom (o, _) | List (o, _) -> o

  exception Err of int * string

  let err at fmt = Format.kasprintf (fun s -> raise_notrace (Err (at, s))) fmt
  let is_ws = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false

  let parse_forms bytes =
    let len = String.length bytes in
    let rec value i =
      if i >= len then err i "unexpected end of input"
      else if bytes.[i] = '(' then items (i + 1) i []
      else if bytes.[i] = ')' then err i "unmatched ')'"
      else atom i
    and items i start acc =
      if i >= len then err start "unclosed list"
      else if bytes.[i] = ')' then (List (start, List.rev acc), i + 1)
      else
        let v, i = value i in
        items i start (v :: acc)
    and atom i =
      let j = ref i in
      while !j < len && '0' <= bytes.[!j] && bytes.[!j] <= '9' do
        incr j
      done;
      if !j = i then err i "expected a length prefix"
      else if !j >= len || bytes.[!j] <> ':' then err !j "expected ':'"
      else
        match int_of_string_opt (String.sub bytes i (!j - i)) with
        | None -> err i "unreadable length prefix"
        | Some n ->
            let start = !j + 1 in
            if start + n > len then err start "atom extends past end of input"
            else (Atom (i, String.sub bytes start n), start + n)
    in
    let rec forms i acc =
      if i >= len then List.rev acc
      else if is_ws bytes.[i] then forms (i + 1) acc
      else
        let v, i = value i in
        forms i (v :: acc)
    in
    forms 0 []

  (* {2 Decode} *)

  let check_header = function
    | [] -> err 0 "empty file: expected a (litany-units 1) header"
    | List (_, [ Atom (_, "litany-units"); Atom (vo, v) ]) :: rest ->
        if String.equal v "1" then rest
        else err vo "unsupported version %s: this Litany reads version 1" v
    | form :: _ -> err (offset_of form) "expected a (litany-units 1) header"

  (* A [(key value)] field where both halves are atoms; anything else in a
     unit form is malformed. *)
  let unit_field = function
    | List (o, [ Atom (_, key); Atom (vo, value) ]) -> (o, key, vo, value)
    | form ->
        err (offset_of form)
          "expected a two-atom (field value) pair in unit form"

  let decode_unit ~offset ~seen_sources fields =
    let found = Hashtbl.create 7 in
    let store key vo value =
      if Hashtbl.mem found key then err vo "duplicate %S field in unit form" key
      else Hashtbl.replace found key value
    in
    List.iter
      (fun field ->
        let o, key, vo, value = unit_field field in
        match key with
        | "source" | "cmt" | "cmti" | "pp-source" | "intf-source" | "library" ->
            store key o value
        | "public" -> (
            match value with
            | "true" | "false" -> store key o value
            | _ -> err vo "expected true or false for public")
        | "kind" ->
            if Roster.kind_of_string value <> None then store key o value
            else err vo "expected lib, exe, or test for kind"
        | _ -> err o "unknown field %S in unit form" key)
      fields;
    let get key = Hashtbl.find_opt found key in
    let source =
      match get "source" with
      | Some s -> s
      | None -> err offset "unit form missing its source field"
    in
    let cmt = get "cmt" and cmti = get "cmti" in
    if cmt = None && cmti = None then
      err offset "unit form for %S names neither cmt nor cmti" source;
    if Hashtbl.mem seen_sources source then
      err offset "duplicate unit for source %S" source;
    Hashtbl.replace seen_sources source ();
    let visibility =
      match get "public" with
      | Some "true" -> Roster.Public
      | Some "false" -> Roster.Private
      | _ -> Roster.Unknown
    in
    let kind = Option.bind (get "kind") Roster.kind_of_string in
    Roster.Entry.v ~source ?cmt ?cmti ?preprocessed_source:(get "pp-source")
      ?interface_source:(get "intf-source") ?library:(get "library") ~visibility
      ?kind ()

  let decode bytes =
    match
      let forms = check_header (parse_forms bytes) in
      let complete = ref true and seen_complete = ref false in
      let cmi_dirs = ref [] and seen_cmi_dirs = ref false in
      let seen_sources = Hashtbl.create 16 in
      let entries = ref [] in
      let preamble_only what o =
        if !entries <> [] then err o "(%s ...) must precede unit forms" what
      in
      List.iter
        (fun form ->
          match form with
          | Atom (o, _) -> err o "expected a form (a list), not an atom"
          | List (o, Atom (_, "complete") :: payload) -> (
              preamble_only "complete" o;
              if !seen_complete then err o "duplicate (complete ...) form";
              seen_complete := true;
              match payload with
              | [ Atom (_, "true") ] -> complete := true
              | [ Atom (_, "false") ] -> complete := false
              | _ -> err o "expected (complete true) or (complete false)")
          | List (o, Atom (_, "cmi-dirs") :: payload) ->
              preamble_only "cmi-dirs" o;
              if !seen_cmi_dirs then err o "duplicate (cmi-dirs ...) form";
              seen_cmi_dirs := true;
              cmi_dirs :=
                List.map
                  (function
                    | Atom (_, dir) -> dir
                    | List (io, _) -> err io "cmi-dirs entries must be atoms")
                  payload
          | List (o, Atom (_, "unit") :: fields) ->
              entries := decode_unit ~offset:o ~seen_sources fields :: !entries
          | List (o, Atom (_, "litany-units") :: _) ->
              err o "duplicate (litany-units ...) header"
          | List (o, Atom (_, key) :: _) ->
              err o
                "unknown form %S: expected (unit ...), (complete ...), or \
                 (cmi-dirs ...)"
                key
          | List (o, _) -> err o "form must begin with a keyword atom")
        forms;
      Roster.v ~complete:!complete ~cmi_dirs:!cmi_dirs (List.rev !entries)
    with
    | roster -> Ok roster
    | exception Err (offset, reason) -> Error { offset; reason }

  (* {2 Encode}

     Canonical bytes: fields in the documented order, [(complete false)] only
     when incomplete, [(cmi-dirs ...)] only when non-empty, one newline after
     each top-level form. [decode (encode r) = r] and encode is a fixpoint of
     the codec: [encode (decode bytes)] of a canonical file is those bytes. *)

  let add_atom b s =
    Buffer.add_string b (string_of_int (String.length s));
    Buffer.add_char b ':';
    Buffer.add_string b s

  let add_field b key value =
    Buffer.add_char b '(';
    add_atom b key;
    add_atom b value;
    Buffer.add_char b ')'

  let encode r =
    let b = Buffer.create 1024 in
    Buffer.add_string b "(12:litany-units1:1)\n";
    if not (Roster.complete r) then Buffer.add_string b "(8:complete5:false)\n";
    (match Roster.cmi_dirs r with
    | [] -> ()
    | dirs ->
        Buffer.add_char b '(';
        add_atom b "cmi-dirs";
        List.iter (add_atom b) dirs;
        Buffer.add_string b ")\n");
    let seen = Hashtbl.create 16 in
    List.iter
      (fun e ->
        let module E = Roster.Entry in
        let source = E.source e in
        if Hashtbl.mem seen source then
          invalid_arg
            (Printf.sprintf "Adapter.Unit_file.encode: duplicate source %S"
               source);
        Hashtbl.replace seen source ();
        Buffer.add_char b '(';
        add_atom b "unit";
        add_field b "source" source;
        Option.iter (add_field b "cmt") (E.cmt e);
        Option.iter (add_field b "cmti") (E.cmti e);
        Option.iter (add_field b "pp-source") (E.preprocessed_source e);
        Option.iter (add_field b "intf-source") (E.interface_source e);
        Option.iter (add_field b "library") (E.library e);
        (match E.visibility e with
        | Roster.Public -> add_field b "public" "true"
        | Roster.Private -> add_field b "public" "false"
        | Roster.Unknown -> ());
        Option.iter
          (fun k -> add_field b "kind" (Roster.kind_to_string k))
          (E.kind e);
        Buffer.add_string b ")\n")
      (Roster.entries r);
    Buffer.contents b
end

(* {1 Tolerant dune-file scan}

   Visibility comes from scanning the [dune] file of each described local
   library's source directory for its [(library ...)] stanza: a
   [(public_name ...)] answers [Public], its absence in a found stanza
   answers [Private], and an unscannable file or an unfound stanza stays
   [Unknown] — stated, never guessed. This is a lenient human-syntax sexp
   reader: bare atoms, quoted strings, [;] comments; anything it cannot read
   makes the whole file unscannable.

   This reader stays separate from the strict positioned reader in
   [litany_config] on purpose — their failure contracts are inverses. This
   one scans files litany does not own and must degrade to Unknown on
   anything unexpected; the config reader parses litany's own file and must
   refuse loudly with a position. Folding one into the other would flip a
   failure contract. *)

type dune_sexp = Atom of string | List of dune_sexp list

exception Unscannable

let parse_dune_file contents =
  let len = String.length contents in
  let rec skip_ws i =
    if i >= len then i
    else
      match contents.[i] with
      | ' ' | '\t' | '\n' | '\r' -> skip_ws (i + 1)
      | ';' ->
          let rec eol i =
            if i >= len || contents.[i] = '\n' then i else eol (i + 1)
          in
          skip_ws (eol i)
      | _ -> i
  in
  let rec value i =
    if i >= len then raise_notrace Unscannable
    else
      match contents.[i] with
      | '(' -> values (i + 1) []
      | '"' ->
          let buf = Buffer.create 16 in
          let rec quoted i =
            if i >= len then raise_notrace Unscannable
            else
              match contents.[i] with
              | '"' -> (Atom (Buffer.contents buf), i + 1)
              | '\\' when i + 1 < len ->
                  Buffer.add_char buf contents.[i + 1];
                  quoted (i + 2)
              | c ->
                  Buffer.add_char buf c;
                  quoted (i + 1)
          in
          quoted (i + 1)
      | ')' -> raise_notrace Unscannable
      | _ ->
          let stop = ref i in
          let bare c =
            match c with
            | ' ' | '\t' | '\n' | '\r' | '(' | ')' | '"' | ';' -> false
            | _ -> true
          in
          while !stop < len && bare contents.[!stop] do
            incr stop
          done;
          (Atom (String.sub contents i (!stop - i)), !stop)
  and values i acc =
    let i = skip_ws i in
    if i >= len then raise_notrace Unscannable
    else if contents.[i] = ')' then (List (List.rev acc), i + 1)
    else
      let v, i = value i in
      values i (v :: acc)
  in
  let rec top i acc =
    let i = skip_ws i in
    if i >= len then List.rev acc
    else
      let v, i = value i in
      top i (v :: acc)
  in
  match top 0 [] with sexps -> Some sexps | exception Unscannable -> None

let library_visibilities sexps =
  List.filter_map
    (function
      | List (Atom "library" :: fields) ->
          let name =
            List.find_map
              (function List [ Atom "name"; Atom n ] -> Some n | _ -> None)
              fields
          in
          let public =
            List.exists
              (function List (Atom "public_name" :: _) -> true | _ -> false)
              fields
          in
          Option.map
            (fun n -> (n, if public then Roster.Public else Roster.Private))
            name
      | _ -> None)
    sexps

(* The [(test ...)]/[(tests ...)] stanza names of one scanned dune
   file. [dune describe workspace] omits test stanzas entirely even though
   [@check] builds them, so their units reach the roster only through the
   union walk — and a stanza kind can come only from this scan, the same
   reader that answers visibility. A test's object directory is
   [.NAME.eobjs] with NAME the stanza's (first) name, so matching that name
   against the scanned test names identifies the owning stanza exactly. An
   unscannable file or an unfound stanza yields no claim: the unit stays
   metadata-less and project capability degrades with the cause named —
   stated, never guessed. *)
let test_stanza_names sexps =
  List.concat_map
    (function
      | List (Atom "test" :: fields) ->
          List.filter_map
            (function List [ Atom "name"; Atom n ] -> Some n | _ -> None)
            fields
      | List (Atom "tests" :: fields) ->
          List.concat_map
            (function
              | List (Atom "names" :: names) ->
                  List.filter_map
                    (function Atom n -> Some n | List _ -> None)
                    names
              | _ -> [])
            fields
      | _ -> [])
    sexps

(* {1 The dune adapter} *)

module Dune = struct
  type error =
    | Dune_missing
    | Build_failed
    | Lock_held of int option
    | No_check_alias of string
    | Describe_failed of string

  (* Dune's lock error names the holder — "A running dune (pid: N)
     instance has locked the build directory" (stdune [global_lock.ml]) —
     and the refusal carries the pid along (UX-06). [None] when the lock
     file predates dune's pid stamping or the wording changes; the
     message then omits it. *)
  let lock_holder_pid err =
    let marker = "pid: " in
    let mlen = String.length marker in
    let n = String.length err in
    let is_digit c = c >= '0' && c <= '9' in
    let rec digits_from start stop =
      if stop < n && is_digit err.[stop] then digits_from start (stop + 1)
      else if stop > start then
        int_of_string_opt (String.sub err start (stop - start))
      else None
    in
    let rec find i =
      if i + mlen > n then None
      else if String.equal (String.sub err i mlen) marker then
        digits_from (i + mlen) (i + mlen)
      else find (i + 1)
    in
    find 0

  (* Both spawns pin dune's root to the directory litany was pointed at
     ([--root .] with the child's cwd already there): without it, dune
     root-walks upward and a workspace nested under another dune project (a
     git worktree, a vendored subtree) resolves to the outer project — the
     run then dies on "Don't know about directory", silently breaking
     litany's own --root promise. *)
  let build_check ~progress ~root =
    let status, out =
      run_forwarding ~progress ~root
        [| "dune"; "build"; "--root"; "."; "@check" |]
    in
    match status with
    | Unix.WEXITED 0 -> Ok ()
    | _ ->
        if
          contains_substring ~sub:"Alias \"check\"" out
          && contains_substring ~sub:"not defined" out
        then Error (No_check_alias "default")
        else Error Build_failed

  let describe ~progress ~root =
    let argv =
      [|
        "dune";
        "describe";
        "workspace";
        "--format";
        "csexp";
        "--lang";
        "0.1";
        "--root";
        ".";
      |]
    in
    match run_capturing ~progress ~root argv with
    | Error reason -> Error (Describe_failed ("dune describe: " ^ reason))
    | Ok (status, out, err) -> (
        match status with
        | Unix.WEXITED 0 -> Ok out
        | _ ->
            let lowered = String.lowercase_ascii err in
            if
              contains_substring ~sub:"lock" lowered
              || contains_substring ~sub:"already running" lowered
            then Error (Lock_held (lock_holder_pid err))
            else Error (Describe_failed (first_line err)))

  let strip_context ~context path =
    if String.equal path context then
      (* A stanza at the workspace root: describe's source_dir is the bare
         context, and the stripped path is the root itself — without this
         arm visibility_map would look for a dune file inside _build and
         silently leave root-level libraries Unknown. *)
      "."
    else
      let prefix = context ^ "/" in
      if String.starts_with ~prefix path then
        String.sub path (String.length prefix)
          (String.length path - String.length prefix)
      else path

  let visibility_map ~root ~context (desc : Dune_describe.t) =
    let tbl = Hashtbl.create 16 in
    List.iter
      (function
        | Dune_describe.Library
            { name; local = true; source_dir = Some source_dir; _ } -> (
            let dune_file =
              root // strip_context ~context source_dir // "dune"
            in
            match In_channel.with_open_bin dune_file In_channel.input_all with
            | exception Sys_error _ -> ()
            | contents -> (
                match parse_dune_file contents with
                | None -> ()
                | Some sexps -> (
                    match List.assoc_opt name (library_visibilities sexps) with
                    | Some vis -> Hashtbl.replace tbl name vis
                    | None -> ())))
        | _ -> ())
      desc.stanzas;
    fun name -> Option.value (Hashtbl.find_opt tbl name) ~default:Roster.Unknown

  (* A stanza claims its modules' artifacts by unit-group key — the artifact
     path minus its extension — so claiming a module's cmt claims its cmti
     and vice versa (describe reports [(cmti ())] for executables' modules
     even though [@check] materializes the cmti). Claims stick even when no
     entry results: the union walk must not resurrect a described module. *)
  let claim_key path = Filename.remove_extension path

  let claim_module ~claimed (m : Dune_describe.module_) =
    Option.iter (fun p -> Hashtbl.replace claimed (claim_key p) ()) m.cmt;
    Option.iter (fun p -> Hashtbl.replace claimed (claim_key p) ()) m.cmti

  (* Describe reports build-tree paths ([_build/default/bin/main.ml]); the
     editable source is the same path with the context stripped, when it
     exists in the source tree — otherwise the unit is generated and the
     build copy is its only source. *)
  let entry_of_module ~root ~context ~claimed ~library ~visibility ~kind
      (m : Dune_describe.module_) =
    claim_module ~claimed m;
    match (m.cmt, m.cmti) with
    | None, None -> None
    | cmt, cmti -> (
        let editable build_path =
          let rel = strip_context ~context build_path in
          if (not (String.equal rel build_path)) && Sys.file_exists (root // rel)
          then rel
          else build_path
        in
        (* Preprocessed modules read a built [<m>.pp.ml]: describe does not
           name it, but dune materializes it next to the module's build-tree
           impl. Naming it makes such units join Derived instead of skipping
           stale; the witness still decides. *)
        let preprocessed_source =
          Option.bind m.impl (fun impl ->
              let pp = Filename.remove_extension impl ^ ".pp.ml" in
              if Sys.file_exists (root // pp) then Some pp else None)
        in
        let build_source =
          match (m.impl, m.intf) with
          | Some p, _ | None, Some p -> Some p
          | None, None -> None
        in
        (* The paired interface source rides the entry for the text lane:
           only when the unit's own source is the implementation — an
           interface-only module's mli is already its [source]. *)
        let interface_source =
          match (m.impl, m.intf) with
          | Some _, Some intf -> Some (editable intf)
          | _ -> None
        in
        match Option.map editable build_source with
        | None -> None
        | Some source ->
            Some
              (Roster.Entry.v ~source ?cmt ?cmti ?preprocessed_source
                 ?interface_source ?library ~visibility ?kind ()))

  let describe_entries ~root ~context ~claimed ~visibility_of
      (desc : Dune_describe.t) =
    List.concat_map
      (function
        | Dune_describe.Library { local = false; _ } -> []
        | Dune_describe.Library { name; modules; _ } ->
            List.filter_map
              (entry_of_module ~root ~context ~claimed ~library:(Some name)
                 ~visibility:(visibility_of name) ~kind:(Some Roster.Library))
              modules
        | Dune_describe.Executables { names; modules; _ } ->
            let library =
              match names with [] -> None | first :: _ -> Some first
            in
            List.filter_map
              (fun (m : Dune_describe.module_) ->
                (* Every executables stanza with two or more
                   modules gets a generated alias module ([dune__exe.ml-gen],
                   compilation unit [Dune__exe]), so any workspace with two
                   such stanzas holds duplicate unit names by construction —
                   permanently tripping the duplicate-identity
                   withhold in the project rules. The roster excludes the
                   alias — artifacts claimed, no entry — rather than asking
                   the check for a path-keyed exemption: the check guards
                   name-keyed joins that would stay ambiguous under readmitted
                   duplicate names (qualifying identity by owner path is the
                   intended post-1.0 fix). Sound to
                   drop: the alias is generated (facts-only), exports no
                   values, and references only its own stanza's modules, each
                   already a root via [kind Executable]. A real duplicate —
                   two executables both named [main.ml] — still withholds.
                   Library alias modules stay: library names are unique per
                   workspace, so they cannot collide. *)
                let generated_alias =
                  match m.impl with
                  | Some impl -> Filename.check_suffix impl ".ml-gen"
                  | None -> false
                in
                if generated_alias then begin
                  claim_module ~claimed m;
                  None
                end
                else
                  entry_of_module ~root ~context ~claimed ~library
                    ~visibility:Roster.Unknown ~kind:(Some Roster.Executable) m)
              modules)
      desc.stanzas

  (* [(test)] stanzas do not appear in describe even though [@check] builds
     them: the context walk picks up their artifacts (and any other
     described-by-no-one unit). A walked unit whose artifact
     directory is the object directory of a scanned [(test ...)]/[(tests
     ...)] stanza carries that stanza's ownership — [kind Test], the stanza
     name as [library] — from the same tolerant dune-file scan that answers
     visibility; without it, every tree with tests lacked kind metadata and
     project rules were unavailable workspace-wide. Any other walked-only
     entry still carries no ownership metadata — the walk cannot know a
     stanza kind without a stanza to read it from. *)
  let union_walk_entries ~root ~context ~claimed =
    if not (is_real_dir (root // context)) then []
    else
      let units = group_units (walk_artifacts (root // context)) in
      (* Memoized per stanza directory: the scan reads the editable dune
         file ([rel_dir] is context-relative, so stanza directories are
         source-tree paths), and one directory owns many walked units. *)
      let test_names = Hashtbl.create 8 in
      let test_stanza_owner ~stanza_dir ~name =
        let names =
          match Hashtbl.find_opt test_names stanza_dir with
          | Some names -> names
          | None ->
              let names =
                match
                  In_channel.with_open_bin
                    (root // stanza_dir // "dune")
                    In_channel.input_all
                with
                | exception Sys_error _ -> []
                | contents -> (
                    match parse_dune_file contents with
                    | None -> []
                    | Some sexps -> test_stanza_names sexps)
              in
              Hashtbl.add test_names stanza_dir names;
              names
        in
        List.mem name names
      in
      List.filter_map
        (fun (u : unit_group) ->
          let cmt = Option.map (fun rel -> context // rel) u.cmt in
          let cmti = Option.map (fun rel -> context // rel) u.cmti in
          let is_claimed = function
            | Some p -> Hashtbl.mem claimed (claim_key p)
            | None -> false
          in
          if is_claimed cmt || is_claimed cmti then None
          else if String.equal u.base "dune__exe" then
            (* Walk lane: a multi-module [(test)] stanza gets the
               same generated [Dune__exe] alias as a described executable —
               undescribed, so it arrives here — and two such tests (or a
               test beside a described stanza) collide on the name exactly
               as above. Same judgment: excluded from the roster, never a
               path-keyed exemption in the duplicate check. *)
            None
          else
            let intf_only = Option.is_none cmt in
            let exists p = Sys.file_exists (root // p) in
            let pair intf_only =
              pair_source
                ~exists
                  (* No candidates ([lookup] is empty), so the fallback
                   scope never applies here. *)
                ~project_boundary:(fun _ -> false)
                ~editable_root:"" ~build_root:context
                ~lookup:(fun _ -> [])
                ~rel_dir:u.rel_dir ~base:u.base ~intf_only
            in
            let source = pair intf_only in
            (* The text lane's second file: a paired unit's editable mli,
               named only when it exists — [pair_source]'s default is a
               path that may not. *)
            let interface_source =
              if intf_only then None
              else
                let mli = pair true in
                if exists mli then Some mli else None
            in
            let library, kind =
              match eobjs_stanza u.rel_dir with
              | Some (stanza_dir, name) when test_stanza_owner ~stanza_dir ~name
                ->
                  (Some name, Some Roster.Test)
              | Some _ | None -> (None, None)
            in
            Some
              (Roster.Entry.v ~source ?cmt ?cmti ?interface_source ?library
                 ?kind ()))
        units

  let roster ?(progress = Progress.v ~enabled:false ~jobs:1) ?(build = true)
      ~root () =
    if not (path_has "dune") then Error Dune_missing
    else
      Fun.protect
        ~finally:(fun () -> Progress.clear progress)
        (fun () ->
          match
            if build then begin
              Progress.phase progress "building";
              build_check ~progress ~root
            end
            else Ok ()
          with
          | Error _ as e -> e
          | Ok () -> (
              Progress.phase progress "describing the workspace";
              match describe ~progress ~root with
              | Error _ as e -> e
              | Ok reply -> (
                  Progress.phase progress "reading the workspace";
                  match Dune_describe.decode reply with
                  | Error detail -> Error (Describe_failed detail)
                  | Ok desc ->
                      let context =
                        Option.value desc.build_context
                          ~default:"_build/default"
                      in
                      let visibility_of = visibility_map ~root ~context desc in
                      let claimed = Hashtbl.create 64 in
                      let described =
                        describe_entries ~root ~context ~claimed ~visibility_of
                          desc
                      in
                      let walked = union_walk_entries ~root ~context ~claimed in
                      let cmi_dirs =
                        dedup
                          (List.concat_map
                             (function
                               | Dune_describe.Library { include_dirs; _ }
                               | Dune_describe.Executables { include_dirs; _ }
                                 ->
                                   include_dirs)
                             desc.stanzas)
                      in
                      Ok
                        (Roster.v ~complete:true ~cmi_dirs (described @ walked))
                  )))

  let pp_error ppf = function
    | Dune_missing ->
        Format.fprintf ppf
          "dune is not on PATH. Pass --cmt-root DIR to lint artifacts built \
           elsewhere."
    | Build_failed ->
        Format.fprintf ppf
          "dune build @@check failed; its errors are above. Lint presupposes a \
           building project."
    | Lock_held pid ->
        (* Journey (b)'s refusal, verbatim (design doc §1, UX-06): the
           holder's pid when dune named one, then the two structured
           remedies — the in-build lane first (the server itself runs
           litany check when @lint is among its aliases), the units
           capture-then-lint spelling second, ending with the command
           that then works beside the server. *)
        Format.fprintf ppf
          "cannot query dune: another dune instance holds the project lock%s\n\
          \  If that is your watch server, lint through it instead: add the\n\
          \  @@lint rule (one stanza; see the build-integration manual) and\n\
          \  put @@lint among the server's aliases — the server then runs\n\
          \  litany check itself.\n\
          \  Or capture a roster once while the server is stopped:\n\
          \    litany units --save litany.units\n\
          \  then, with the server running:\n\
          \    litany check --no-build --units litany.units [--fix]"
          (match pid with
          | Some p -> Printf.sprintf "\n(dune reports: pid %d)." p
          | None -> ".")
    | No_check_alias context ->
        Format.fprintf ppf
          "the %s context is not merlin-enabled, so its @@check alias does not \
           exist. Lint the default context."
          context
    | Describe_failed detail ->
        Format.fprintf ppf "dune describe failed: %s" detail
end

(* {1 The artifact walk} *)

module Walk = struct
  type error = Root_missing of string

  let roster ~cmt_root ~source_root =
    if not (is_real_dir cmt_root) then Error (Root_missing cmt_root)
    else if not (is_real_dir source_root) then Error (Root_missing source_root)
    else
      let units = group_units (walk_artifacts cmt_root) in
      let index = lazy (source_index source_root) in
      let lookup name =
        Option.value (Hashtbl.find_opt (Lazy.force index) name) ~default:[]
      in
      let project_boundary = project_boundary_probe () in
      let entries =
        List.map
          (fun (u : unit_group) ->
            let intf_only = Option.is_none u.cmt in
            let pair intf_only =
              pair_source ~exists:Sys.file_exists ~project_boundary
                ~editable_root:source_root ~build_root:cmt_root ~lookup
                ~rel_dir:u.rel_dir ~base:u.base ~intf_only
            in
            let source = pair intf_only in
            (* The paired mli for the text lane, named only when it exists
               — [pair_source]'s default is a path that may not. *)
            let interface_source =
              if intf_only then None
              else
                let mli = pair true in
                if Sys.file_exists mli then Some mli else None
            in
            Roster.Entry.v ~source
              ?cmt:(Option.map (fun rel -> cmt_root // rel) u.cmt)
              ?cmti:(Option.map (fun rel -> cmt_root // rel) u.cmti)
              ?interface_source ())
          units
      in
      let cmi_dirs =
        dedup (List.map (fun (u : unit_group) -> cmt_root // u.rel_dir) units)
      in
      Ok (Roster.v ~complete:false ~cmi_dirs entries)

  let pp_error ppf (Root_missing dir) =
    Format.fprintf ppf
      "%s does not exist or cannot be read. Pass --cmt-root a directory \
       holding .cmt artifacts."
      dir
end
