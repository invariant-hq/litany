(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Policy is pure (key derivation, entry framing, name classification, age
   decisions); IO is confined to a few best-effort helpers below. No function
   in this module raises: the cache is advisory, so every failure degrades to
   a miss, a dropped write, or a skipped sweep item. No mtimes anywhere —
   entry age lives in explicit stamp files and [now] is always an argument. *)

let blake128_hex bytes = Digest.BLAKE128.to_hex (Digest.BLAKE128.string bytes)

(* {1 Keys} *)

module Key = struct
  type t = string (* raw 16-byte BLAKE128 digest *)

  (* The encoding is the cache format: version-tagged, every component
     length-prefixed (so distinct input tuples yield distinct encodings),
     every optional component presence-tagged, the rule set sorted and
     deduplicated with an explicit count. Any change here must bump the tag —
     a golden test pins one derived hex. v2: the semantic inputs the driver
     used to NUL-pack into five composite slots are named components in their
     own right, framed here rather than at the call site. *)
  let encode ~cmt_digest ~cmti_digest ~source_path ~source_digest
      ~interface_source ~library ~visibility ~kind ~config_fingerprint
      ~build_current ~selected_rules ~binary_digest =
    let b = Buffer.create 192 in
    let field s =
      Buffer.add_string b (string_of_int (String.length s));
      Buffer.add_char b ':';
      Buffer.add_string b s;
      Buffer.add_char b '\n'
    in
    let opt_field = function
      | None -> Buffer.add_string b "-\n"
      | Some s ->
          Buffer.add_string b "+\n";
          field s
    in
    Buffer.add_string b "litany-cache-key-v2\n";
    field cmt_digest;
    opt_field cmti_digest;
    field source_path;
    field source_digest;
    (match interface_source with
    | None -> Buffer.add_string b "-\n"
    | Some (path, digest) ->
        Buffer.add_string b "+\n";
        field path;
        field digest);
    opt_field library;
    field visibility;
    opt_field kind;
    field config_fingerprint;
    field (if build_current then "build-current" else "no-build");
    let rules = List.sort_uniq String.compare selected_rules in
    Buffer.add_string b (string_of_int (List.length rules));
    Buffer.add_char b '\n';
    List.iter field rules;
    field binary_digest;
    Buffer.contents b

  let v ~cmt_digest ~cmti_digest ~source_path ~source_digest ~interface_source
      ~library ~visibility ~kind ~config_fingerprint ~build_current
      ~selected_rules ~binary_digest =
    Digest.BLAKE128.string
      (encode ~cmt_digest ~cmti_digest ~source_path ~source_digest
         ~interface_source ~library ~visibility ~kind ~config_fingerprint
         ~build_current ~selected_rules ~binary_digest)

  let to_hex = Digest.BLAKE128.to_hex
  let equal = String.equal
  let compare = String.compare
  let pp ppf k = Format.pp_print_string ppf (to_hex k)
end

(* {1 Entry framing}

   magic line, key hex, payload BLAKE128 hex, payload length, payload bytes.
   The payload digest makes torn and corrupted files detectable; the key
   line binds the contents to the key they were stored under, so an entry
   whose bytes land under another key's filename (a restore or sync tool
   renaming files) is a miss, never a replay under the wrong key — the
   payload digest alone verifies the bytes, not their address.
   Load rejects anything that does not verify; the sweep ages
   rejected entries out. v3 marks the key-derivation change (key-v2, the
   named-component encoding): every key's bytes changed with it, so v2
   entries are unreachable garbage — the magic bump makes them dead by
   inspection, not merely by address, and the sweep ages them out. *)

let entry_magic = "litany-cache-entry-v3"

let encode_entry key payload =
  Printf.sprintf "%s\n%s\n%s\n%d\n%s" entry_magic (Key.to_hex key)
    (blake128_hex payload) (String.length payload) payload

let parse_entry key bytes =
  let ( let* ) = Option.bind in
  let* e1 = String.index_opt bytes '\n' in
  if not (String.equal (String.sub bytes 0 e1) entry_magic) then None
  else
    let* e2 = String.index_from_opt bytes (e1 + 1) '\n' in
    if
      not
        (String.equal
           (String.sub bytes (e1 + 1) (e2 - e1 - 1))
           (Key.to_hex key))
    then None
    else
      let* e3 = String.index_from_opt bytes (e2 + 1) '\n' in
      let hex = String.sub bytes (e2 + 1) (e3 - e2 - 1) in
      let* e4 = String.index_from_opt bytes (e3 + 1) '\n' in
      let* n = int_of_string_opt (String.sub bytes (e3 + 1) (e4 - e3 - 1)) in
      let start = e4 + 1 in
      if n < 0 || String.length bytes - start <> n then None
      else
        let payload = String.sub bytes start n in
        if String.equal hex (blake128_hex payload) then Some payload else None

(* {1 Stamps} *)

let stamp_bytes now = Printf.sprintf "%.6f\n" now
let parse_stamp bytes = float_of_string_opt (String.trim bytes)
let max_age = 30. *. 24. *. 60. *. 60.

(* {1 Names} *)

let marker_name = "marker"
let is_hex_digit c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')

let is_key_hex name =
  String.length name = 32 && String.for_all is_hex_digit name

(* {1 IO edge — best-effort helpers} *)

let read_file path =
  match In_channel.with_open_bin path In_channel.input_all with
  | bytes -> Some bytes
  | exception Sys_error _ -> None

let remove_file path = try Sys.remove path with Sys_error _ -> ()

let rec mkdir_p path =
  if not (Sys.file_exists path) then begin
    let parent = Filename.dirname path in
    if not (String.equal parent path) then mkdir_p parent;
    try Unix.mkdir path 0o755 with Unix.Unix_error _ -> ()
  end

(* Never follows symlinks: only what the cache itself owns is deleted. *)
let rec rm_rf path =
  match (Unix.lstat path).Unix.st_kind with
  | Unix.S_DIR -> (
      let names = try Sys.readdir path with Sys_error _ -> [||] in
      Array.iter (fun n -> rm_rf (Filename.concat path n)) names;
      try Unix.rmdir path with Unix.Unix_error _ -> ())
  | _ -> ( try Unix.unlink path with Unix.Unix_error _ -> ())
  | exception Unix.Unix_error _ -> ()

(* Atomic publication is [Write.atomic] — the one write-then-rename
   implementation, never a local copy — deliberately without fsync: a torn
   or lost cache entry
   after power loss is re-derivable, and the eviction sweep recognizes
   the shared ".tmp" residue. Best-effort — [false] means the cache was
   simply not updated. *)
let write_atomic ~dir ~name bytes =
  match Write.atomic ~fsync:false ~path:(Filename.concat dir name) bytes with
  | Ok () -> true
  | Error _ -> false

(* {1 Handles} *)

type t = { root : string; workspace : string; digest : string }

let create ~root ~workspace_root =
  let workspace =
    match Unix.realpath workspace_root with
    | path -> path
    | exception Unix.Unix_error _ -> workspace_root
  in
  { root; workspace; digest = blake128_hex workspace }

let dir t = Filename.concat t.root t.digest

let ensure_marker t =
  let marker = Filename.concat (dir t) marker_name in
  if not (Sys.file_exists marker) then
    ignore (write_atomic ~dir:(dir t) ~name:marker_name (t.workspace ^ "\n"))

(* {1 Storing and loading} *)

let store t ~now key payload =
  let dir = dir t in
  mkdir_p dir;
  ensure_marker t;
  let hex = Key.to_hex key in
  if write_atomic ~dir ~name:hex (encode_entry key payload) then
    ignore (write_atomic ~dir ~name:(hex ^ ".stamp") (stamp_bytes now))

let load t key =
  match read_file (Filename.concat (dir t) (Key.to_hex key)) with
  | None -> None
  | Some bytes -> parse_entry key bytes

(* {1 Sweeping} *)

type sweep = { evicted_entries : int; removed_workspaces : int }

let is_dir path = try Sys.is_directory path with Sys_error _ -> false
let readdir path = try Sys.readdir path with Sys_error _ -> [||]

(* Stamp every existing entry in [read] at [now]; entries stored this run
   were already stamped by [store]. *)
let stamp_read t ~now read =
  let dir = dir t in
  List.iter
    (fun key ->
      let hex = Key.to_hex key in
      if Sys.file_exists (Filename.concat dir hex) then
        ignore (write_atomic ~dir ~name:(hex ^ ".stamp") (stamp_bytes now)))
    read

(* Evict entries unread for [max_age]; re-stamp entries whose stamp is
   missing or unreadable (a fresh lease — damage self-heals yet still ages
   out); drop orphaned stamps and leftover temp files. *)
let sweep_entries t ~now =
  let dir = dir t in
  let evicted = ref 0 in
  Array.iter
    (fun name ->
      let path = Filename.concat dir name in
      if is_key_hex name then begin
        let stamp_path = path ^ ".stamp" in
        match Option.bind (read_file stamp_path) parse_stamp with
        | Some stamp ->
            if now -. stamp > max_age then begin
              remove_file path;
              remove_file stamp_path;
              incr evicted
            end
        | None ->
            ignore (write_atomic ~dir ~name:(name ^ ".stamp") (stamp_bytes now))
      end
      else if
        Filename.check_suffix name ".stamp"
        && is_key_hex (Filename.chop_suffix name ".stamp")
      then
        begin if
          not
            (Sys.file_exists
               (Filename.concat dir (Filename.chop_suffix name ".stamp")))
        then remove_file path
        end
      else if Filename.check_suffix name ".tmp" then remove_file path)
    (readdir dir);
  !evicted

(* Remove sibling workspace directories whose marker names a path that no
   longer exists, and marker-less empty ones (crash residue). *)
let sweep_workspaces t =
  let removed = ref 0 in
  Array.iter
    (fun name ->
      if is_key_hex name && not (String.equal name t.digest) then begin
        let wdir = Filename.concat t.root name in
        if is_dir wdir then
          match read_file (Filename.concat wdir marker_name) with
          | Some contents ->
              let recorded = String.trim contents in
              if String.length recorded > 0 && not (Sys.file_exists recorded)
              then begin
                rm_rf wdir;
                incr removed
              end
          | None ->
              if Array.length (readdir wdir) = 0 then begin
                (try Unix.rmdir wdir with Unix.Unix_error _ -> ());
                incr removed
              end
      end)
    (readdir t.root);
  !removed

let sweep t ~now ~read =
  let evicted_entries =
    if is_dir (dir t) then begin
      ensure_marker t;
      stamp_read t ~now read;
      sweep_entries t ~now
    end
    else 0
  in
  { evicted_entries; removed_workspaces = sweep_workspaces t }

(* {1 Locating the cache} *)

let resolve_root ?cache_dir ~env () =
  let nonempty name =
    match env name with Some "" | None -> None | Some value -> Some value
  in
  let absolute = function
    | Some path when not (Filename.is_relative path) -> Some path
    | Some _ | None -> None
  in
  match cache_dir with
  | Some d -> Some d
  | None -> (
      match nonempty "LITANY_CACHE_DIR" with
      | Some d -> Some d
      | None -> (
          match absolute (nonempty "XDG_CACHE_HOME") with
          | Some xdg -> Some (Filename.concat xdg "litany")
          | None -> (
              match absolute (nonempty "HOME") with
              | Some home ->
                  Some
                    (Filename.concat (Filename.concat home ".cache") "litany")
              | None -> None)))
