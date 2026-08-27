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

(* Dune names every stanza's object directory after the stanza:
   [.NAME.objs] for a [(library NAME)], [.NAME.eobjs] for an
   executable-family stanza ([executable]/[executables]/[test]/[tests])
   with NAME the stanza's (first) name. [stanza_of_rel_dir rel_dir]
   recovers the stanza's source directory, its name, and which family owns
   it from an artifact directory beneath it — the directory name is dune's
   own statement of ownership, not a guess; [None] when [rel_dir] descends
   through neither. The [.eobjs] suffix also ends in [.objs], so it is
   tested first. *)
type stanza_family = Library_stanza | Executable_family

let stanza_of_rel_dir rel_dir =
  let rec go acc = function
    | [] -> None
    | seg :: rest ->
        let n = String.length seg in
        if n > 7 && seg.[0] = '.' && Filename.check_suffix seg ".eobjs" then
          Some
            ( String.concat "/" (List.rev acc),
              String.sub seg 1 (n - 7),
              Executable_family )
        else if n > 6 && seg.[0] = '.' && Filename.check_suffix seg ".objs"
        then
          Some
            ( String.concat "/" (List.rev acc),
              String.sub seg 1 (n - 6),
              Library_stanza )
        else go (seg :: acc) rest
  in
  go [] (String.split_on_char '/' rel_dir)

(* A stanza directory inside a dot directory is dune-generated harness
   scaffolding — [.NAME.inline-tests] runners and kin. Their units mirror a
   real stanza's sources under a generated stanza, so admitting them mints
   duplicate-source entries (one walked mentat tree held 21 of them, enough
   to trip the unit-file codec's duplicate-source invariant); excluded from
   the roster wholesale. *)
let generated_stanza_dir stanza_dir =
  List.exists
    (fun seg -> String.length seg > 0 && seg.[0] = '.')
    (String.split_on_char '/' stanza_dir)

(* ["lib__Foo"] names module [Foo] of wrapped library [lib]; the source
   basename is the uncapitalized last [__] component. A base {e ending} in
   ["__"] is the wrapped library's own alias unit ([lib__], minted when the
   library holds a module of its own name): its leaf is the whole base —
   the generated [lib__.ml-gen] is the source the pairing must find. *)
let leaf_of base =
  let len = String.length base in
  let rec last_sep i found =
    if i + 1 >= len then found
    else if base.[i] = '_' && base.[i + 1] = '_' then last_sep (i + 2) (i + 2)
    else last_sep (i + 1) found
  in
  match last_sep 0 0 with
  | 0 -> base
  | at when at = len -> base
  | at -> String.sub base at (len - at)

(* Editable-source index of a source tree: basename -> sorted paths, each
   [mk rel] ([Walk] anchors them under its source root, the dune roster
   keeps them root-relative). Directories starting with ['.'] or ['_']
   never hold editable sources ([_build] copies must not be anchors), so
   they are pruned. *)
let source_index_with ~mk root =
  let tbl = Hashtbl.create 256 in
  walk_tree root
    ~prune:(fun name -> name = "" || name.[0] = '.' || name.[0] = '_')
    ~file:(fun ~rel ~name ->
      if Filename.check_suffix name ".ml" || Filename.check_suffix name ".mli"
      then
        Hashtbl.replace tbl name
          (mk rel :: Option.value (Hashtbl.find_opt tbl name) ~default:[]));
  (* Deterministic buckets: candidates in path order. *)
  Hashtbl.filter_map_inplace
    (fun _ paths -> Some (List.sort String.compare paths))
    tbl;
  tbl

let source_index root = source_index_with ~mk:(fun rel -> root // rel) root

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

(* Bounded retention: the one spawn bounds what it retains in memory. It
   deliberately has no timeout: a legitimate dune build may be arbitrarily
   long, and its output streams to the user who can interrupt it. *)

(* The retained-transcript bound for the forwarded build: classification
   reads only the leading bytes of dune's error output. *)
let forward_capture_limit = 8 * 1024 * 1024

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

(* {1 The unit file} *)

module Unit_file = struct
  type error = { offset : int; reason : string }

  let pp_error ppf e =
    Format.fprintf ppf "unit file: byte %d: %s" e.offset e.reason

  (* {2 Csexp with offsets}

     A unit file is a *sequence* of top-level forms, not one document, and
     every error must carry the byte offset of the offending form or atom,
     so values are position-annotated.
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

   Stanza metadata comes from scanning the [dune] file of each walked
   unit's stanza directory: a [(library ...)] stanza answers visibility — a
   [(public_name ...)] is [Public], its absence in a found stanza
   [Private] — and the executable-family stanza names split [Executable]
   from [Test]. An unscannable file or an unfound stanza stays [Unknown] /
   kind-less — stated, never guessed. This is a lenient human-syntax sexp
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

(* The stanza names of one scanned dune file, per family. An [.eobjs]
   object directory says only "executable family": whether NAME is a
   [(test ...)]/[(tests ...)] or an [(executable ...)]/[(executables ...)]
   stanza can come only from this scan, the same reader that answers
   visibility. An unscannable file or an unfound stanza yields no claim:
   the unit stays metadata-less and project capability degrades with the
   cause named — stated, never guessed. *)
let stanza_field_names field fields =
  List.concat_map
    (function
      | List (Atom head :: names) when String.equal head field ->
          List.filter_map (function Atom n -> Some n | List _ -> None) names
      | _ -> [])
    fields

let test_stanza_names sexps =
  List.concat_map
    (function
      | List (Atom "test" :: fields) -> stanza_field_names "name" fields
      | List (Atom "tests" :: fields) -> stanza_field_names "names" fields
      | _ -> [])
    sexps

let executable_stanza_names sexps =
  List.concat_map
    (function
      | List (Atom "executable" :: fields) -> stanza_field_names "name" fields
      | List (Atom "executables" :: fields) ->
          stanza_field_names "names" fields
      | _ -> [])
    sexps

(* {1 The dune adapter} *)

module Dune = struct
  type error = Dune_missing | Build_failed | No_check_alias of string

  (* Both the build spawn and dune's root resolution pin dune's root to the
     directory litany was pointed at ([--root .] with the child's cwd
     already there): without it, dune root-walks upward and a workspace
     nested under another dune project (a git worktree, a vendored subtree)
     resolves to the outer project — the run then dies on "Don't know about
     directory", silently breaking litany's own --root promise. The build
     is the one dune subprocess left in this adapter, and it composes with
     a live watch: a secondary [dune build] forwards its request to the
     watch server holding the lock instead of fighting it. *)
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

  (* One tolerant scan per stanza directory, memoized — one directory owns
     many walked units. The scan reads the editable dune file: stanza
     directories are context-relative, hence source-tree paths. *)
  type stanza_scan = {
    libraries : (string * Roster.visibility) list;
    executables : string list;
    tests : string list;
  }

  let unscanned = { libraries = []; executables = []; tests = [] }

  let stanza_scan_cache root =
    let memo = Hashtbl.create 16 in
    fun stanza_dir ->
      match Hashtbl.find_opt memo stanza_dir with
      | Some scan -> scan
      | None ->
          let scan =
            match
              In_channel.with_open_bin
                (root // stanza_dir // "dune")
                In_channel.input_all
            with
            | exception Sys_error _ -> unscanned
            | contents -> (
                match parse_dune_file contents with
                | None -> unscanned
                | Some sexps ->
                    {
                      libraries = library_visibilities sexps;
                      executables = executable_stanza_names sexps;
                      tests = test_stanza_names sexps;
                    })
          in
          Hashtbl.add memo stanza_dir scan;
          scan

  (* External dependencies' cmi search dirs. The dune-pkg store
     materializes each locked package under
     [_build/_private/<context>/.pkg/<pkg>/target], so every directory
     beneath a package's [target/lib] holding a [.cmi] is a search dir —
     the same set describe's include_dirs used to enumerate. A workspace
     without a store (opam, vendored) contributes nothing here and the
     name resolver degrades per its own contract: missing means
     match-nothing, stated. *)
  let pkg_store_cmi_dirs ~root ~context =
    let store =
      "_build" // "_private" // Filename.basename context // ".pkg"
    in
    match Sys.readdir (root // store) with
    | exception Sys_error _ -> []
    | pkgs ->
        Array.sort String.compare pkgs;
        let acc = ref [] in
        Array.iter
          (fun pkg ->
            let lib = store // pkg // "target" // "lib" in
            if is_real_dir (root // lib) then
              walk_tree (root // lib)
                ~prune:(fun _ -> false)
                ~file:(fun ~rel ~name ->
                  if Filename.check_suffix name ".cmi" then
                    let dir =
                      match Filename.dirname rel with "." -> "" | d -> d
                    in
                    acc := (lib // dir) :: !acc))
          pkgs;
        dedup (List.rev !acc)

  (* The roster read straight from the build tree: the artifact walk is the
     enumeration, the object-directory name recovers each unit's stanza,
     and the tolerant dune-file scan classifies it. Nothing here asks dune
     anything — after a green [@check] every stanza module's artifact is
     materialized, so walking finds exactly what describe used to report,
     plus the [(test)] stanzas describe always omitted. A roster is an
     enumeration, never a proof: a walk racing a rebuild costs
     witness-gated skips at join time, never findings. *)
  let build_tree_roster ~root ~context =
    let units =
      if is_real_dir (root // context) then
        group_units (walk_artifacts (root // context))
      else []
    in
    let scan = stanza_scan_cache root in
    (* The source index answers layouts the leaf convention cannot — under
       [(include_subdirs qualified)] a unit's source lives deeper than its
       stanza directory — with [pair_source]'s proximity scope deciding, the
       same way the [Walk] adapter pairs. Lazy: a tree whose every unit
       pairs by convention never walks its sources. *)
    let index = lazy (source_index_with ~mk:Fun.id root) in
    let lookup name =
      Option.value (Hashtbl.find_opt (Lazy.force index) name) ~default:[]
    in
    let boundary = project_boundary_probe () in
    let project_boundary dir = boundary (root // dir) in
    let entries =
      List.filter_map
        (fun (u : unit_group) ->
          let stanza = stanza_of_rel_dir u.rel_dir in
          let excluded =
            (* Generated harness stanzas (dot-directory stanza dirs) and
               the per-stanza executable alias module ([dune__exe.ml-gen],
               compilation unit [Dune__exe] for every executable-family
               stanza with two or more modules): both dune-generated, both
               name-colliding by construction. The alias is sound to drop —
               generated (facts-only), exports no values, references only
               its own stanza's modules, each already a root via its kind —
               rather than asking the check for a path-keyed exemption:
               the check guards name-keyed joins that would stay ambiguous
               under readmitted duplicate names. A real duplicate — two
               executables both named [main.ml] — still withholds. Library
               alias modules stay: library names are unique per
               workspace. *)
            (match stanza with
            | Some (stanza_dir, _, _) -> generated_stanza_dir stanza_dir
            | None -> false)
            || String.equal u.base "dune__exe"
          in
          if excluded then None
          else
            let cmt = Option.map (fun rel -> context // rel) u.cmt in
            let cmti = Option.map (fun rel -> context // rel) u.cmti in
            let intf_only = Option.is_none cmt in
            let exists p = Sys.file_exists (root // p) in
            let pair intf_only =
              pair_source ~exists ~project_boundary ~editable_root:""
                ~build_root:context ~lookup ~rel_dir:u.rel_dir ~base:u.base
                ~intf_only
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
            (* Preprocessed modules read a built [<m>.pp.ml]: dune
               materializes it beside the module's build-tree impl. Naming
               it lets such units join Derived instead of skipping stale;
               the witness still decides. *)
            let preprocessed_source =
              if intf_only then None
              else
                let pp =
                  context // clean_rel_dir u.rel_dir
                  // (String.uncapitalize_ascii (leaf_of u.base) ^ ".pp.ml")
                in
                if exists pp then Some pp else None
            in
            let library, visibility, kind =
              match stanza with
              | None -> (None, Roster.Unknown, None)
              | Some (stanza_dir, name, Library_stanza) ->
                  (* The [.objs] directory is dune's own statement that a
                     library named [name] owns these units; the scan adds
                     visibility when it finds the stanza. *)
                  ( Some name,
                    Option.value
                      (List.assoc_opt name (scan stanza_dir).libraries)
                      ~default:Roster.Unknown,
                    Some Roster.Library )
              | Some (stanza_dir, name, Executable_family) ->
                  let claims = scan stanza_dir in
                  if List.mem name claims.tests then
                    (Some name, Roster.Unknown, Some Roster.Test)
                  else if List.mem name claims.executables then
                    (Some name, Roster.Unknown, Some Roster.Executable)
                  else (None, Roster.Unknown, None)
            in
            Some
              (Roster.Entry.v ~source ?cmt ?cmti ?preprocessed_source
                 ?interface_source ?library ~visibility ?kind ()))
        units
    in
    let local_cmi_dirs =
      dedup (List.map (fun (u : unit_group) -> context // u.rel_dir) units)
    in
    Roster.v ~complete:true
      ~cmi_dirs:(local_cmi_dirs @ pkg_store_cmi_dirs ~root ~context)
      entries

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
          | Ok () ->
              Progress.phase progress "reading the build tree";
              Ok (build_tree_roster ~root ~context:"_build/default"))

  let pp_error ppf = function
    | Dune_missing ->
        Format.fprintf ppf
          "dune is not on PATH. Pass --cmt-root DIR to lint artifacts built \
           elsewhere."
    | Build_failed ->
        Format.fprintf ppf
          "dune build @@check failed; its errors are above. Lint presupposes a \
           building project."
    | No_check_alias context ->
        Format.fprintf ppf
          "the %s context is not merlin-enabled, so its @@check alias does not \
           exist. Lint the default context."
          context
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
