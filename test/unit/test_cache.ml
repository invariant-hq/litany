(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Cache = Litany.Cache
module Key = Litany.Cache.Key

(* {1 Fixtures} *)

let day = 86_400.
let t0 = 1_000_000_000.

let key ?(cmt = "cmt-digest") ?cmti ?(path = "lib/unit.ml")
    ?(source = "source-digest") ?intf ?lib ?(vis = "public") ?kind
    ?(config = "config-fp") ?(build = false) ?(rules = [ "a-rule"; "b-rule" ])
    ?(binary = "binary-digest") () =
  Key.v ~cmt_digest:cmt ~cmti_digest:cmti ~source_path:path
    ~source_digest:source ~interface_source:intf ~library:lib ~visibility:vis
    ~kind ~config_fingerprint:config ~build_current:build ~selected_rules:rules
    ~binary_digest:binary

let rec rm_rf path =
  match (Unix.lstat path).Unix.st_kind with
  | Unix.S_DIR ->
      Array.iter (fun n -> rm_rf (Filename.concat path n)) (Sys.readdir path);
      Unix.rmdir path
  | _ -> Unix.unlink path
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

(* A fresh cache root and a fresh workspace directory, both deleted after
   [k]; [k] receives the handle plus both paths. *)
let with_cache k =
  let root = Filename.temp_dir "litany-cache-root" "" in
  let ws = Filename.temp_dir "litany-cache-ws" "" in
  Fun.protect
    ~finally:(fun () ->
      rm_rf root;
      rm_rf ws)
    (fun () -> k (Cache.create ~root ~workspace_root:ws) ~root ~ws)

let read_file path = In_channel.with_open_bin path In_channel.input_all

let write_file path bytes =
  Out_channel.with_open_bin path (fun oc -> Out_channel.output_string oc bytes)

let entry_path t k = Filename.concat (Cache.dir t) (Key.to_hex k)

let is_hex32 s =
  String.length s = 32
  && String.for_all
       (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
       s

let gen_rule_name = Gen.string_of ~size:(Gen.int_range 0 12) Gen.char
let gen_payload = Gen.string_of ~size:(Gen.int_range 0 300) Gen.char

(* {1 Keys} *)

let keys =
  group "keys"
    [
      test "derivation is pinned — this hex must never change" (fun () ->
          (* Golden: the derivation is the on-disk cache format. If this test
             breaks, the key encoding changed; that is a deliberate
             cache-format change and must bump the version tag, not slip
             through. Pinned for key-v2, the named-component encoding. *)
          equal string "519436a743cf51d4d25c8cae3c6c5fd1"
            (Key.to_hex
               (Key.v ~cmt_digest:"0123456789abcdef0123456789abcdef"
                  ~cmti_digest:(Some "00112233445566778899aabbccddeeff")
                  ~source_path:"lib/unit.ml"
                  ~source_digest:"fedcba9876543210fedcba9876543210"
                  ~interface_source:
                    (Some ("lib/unit.mli", "ffeeddccbbaa99887766554433221100"))
                  ~library:(Some "litany") ~visibility:"public"
                  ~kind:(Some "lib") ~config_fingerprint:"config-v1"
                  ~build_current:true ~selected_rules:[ "b-rule"; "a-rule" ]
                  ~binary_digest:"binary-digest-000")));
      test "to_hex is 32 lowercase hex characters" (fun () ->
          is_true (is_hex32 (Key.to_hex (key ()))));
      prop "rule order and duplicates never change the key"
        Gen.(list ~size:(int_range 0 8) gen_rule_name)
        (fun rules ->
          equal string
            (Key.to_hex (key ~rules ()))
            (Key.to_hex (key ~rules:(List.rev (rules @ rules)) ())));
      test "each component changes the key" (fun () ->
          let hexes =
            List.map Key.to_hex
              [
                key ();
                key ~cmt:"other" ();
                key ~cmti:"other" ();
                key ~path:"other" ();
                key ~source:"other" ();
                key ~intf:("lib/unit.mli", "intf-digest") ();
                key ~lib:"other" ();
                key ~vis:"private" ();
                key ~kind:"lib" ();
                key ~config:"other" ();
                key ~build:true ();
                key ~rules:[ "a-rule" ] ();
                key ~binary:"other" ();
              ]
          in
          equal int 13 (List.length (List.sort_uniq String.compare hexes)));
      test "component boundaries cannot be confused" (fun () ->
          (* Length-prefixing at work: shifting bytes across a field boundary,
             or splitting one rule name into two, must change the key. *)
          is_false
            (Key.equal (key ~cmt:"ab" ~cmti:"" ()) (key ~cmt:"a" ~cmti:"b" ()));
          is_false
            (Key.equal (key ~rules:[ "ab" ] ()) (key ~rules:[ "a"; "b" ] ())));
      test "absent and empty optional components cannot be confused" (fun () ->
          (* Presence-tagging at work: [None] and [Some ""] are different
             semantic states (no cmti named vs a named one digesting empty)
             and must never share a key. *)
          is_false (Key.equal (key ()) (key ~cmti:"" ()));
          is_false (Key.equal (key ()) (key ~lib:"" ()));
          is_false (Key.equal (key ()) (key ~kind:"" ()));
          is_false (Key.equal (key ()) (key ~intf:("", "") ()));
          is_false
            (Key.equal (key ~intf:("ab", "") ()) (key ~intf:("a", "b") ())));
      prop "equal agrees with compare"
        Gen.(pair gen_rule_name gen_rule_name)
        (fun (a, b) ->
          let k = key ~cmt:a () and k' = key ~cmt:b () in
          equal bool (Key.equal k k') (Key.compare k k' = 0);
          equal int 0 (Key.compare k k));
      test "pp prints the hex" (fun () ->
          let k = key () in
          equal string (Key.to_hex k) (Format.asprintf "%a" Key.pp k));
    ]

(* {1 Storing and loading} *)

let storing =
  group "store-load"
    [
      prop ~count:25 "round-trips any payload byte-identically"
        ~examples:[ ""; "\n"; "\000\255tail" ] gen_payload (fun payload ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) payload;
              equal (option string) (Some payload) (Cache.load t (key ()))));
      test "a missing entry is a miss" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              equal (option string) None (Cache.load t (key ()))));
      test "distinct keys name distinct entries" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              equal (option string) None (Cache.load t (key ~cmt:"other" ()))));
      test "re-store overwrites: last writer wins" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "first";
              Cache.store t ~now:t0 (key ()) "second";
              equal (option string) (Some "second") (Cache.load t (key ()))));
      test "store leaves no temp file behind" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              is_false
                (Array.exists
                   (fun n -> Filename.check_suffix n ".tmp")
                   (Sys.readdir (Cache.dir t)))));
      test "first store writes the marker with the workspace realpath"
        (fun () ->
          with_cache (fun t ~root:_ ~ws ->
              Cache.store t ~now:t0 (key ()) "payload";
              equal string (Unix.realpath ws)
                (String.trim
                   (read_file (Filename.concat (Cache.dir t) "marker")))));
      test "an unusable root degrades to a miss, never an error" (fun () ->
          with_cache (fun _ ~root ~ws ->
              (* A root that is a regular file: nothing can be created under
                 it. Every operation must degrade silently. *)
              let file_root = Filename.concat root "actually-a-file" in
              write_file file_root "";
              let t = Cache.create ~root:file_root ~workspace_root:ws in
              Cache.store t ~now:t0 (key ()) "payload";
              equal (option string) None (Cache.load t (key ()));
              let s = Cache.sweep t ~now:t0 ~read:[] in
              equal int 0 s.Cache.evicted_entries;
              equal int 0 s.Cache.removed_workspaces));
    ]

(* {1 Corrupted entries} *)

let corruption =
  group "corruption"
    [
      test "garbage bytes are a miss" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              write_file (entry_path t (key ())) "total garbage";
              equal (option string) None (Cache.load t (key ()))));
      test "an empty file is a miss" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              write_file (entry_path t (key ())) "";
              equal (option string) None (Cache.load t (key ()))));
      test "a truncated entry is a miss" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "a payload long enough to cut";
              let path = entry_path t (key ()) in
              let bytes = read_file path in
              write_file path (String.sub bytes 0 (String.length bytes - 5));
              equal (option string) None (Cache.load t (key ()))));
      test "a flipped payload byte is a miss" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let path = entry_path t (key ()) in
              let bytes = Bytes.of_string (read_file path) in
              let last = Bytes.length bytes - 1 in
              Bytes.set bytes last
                (Char.chr (Char.code (Bytes.get bytes last) lxor 1));
              write_file path (Bytes.to_string bytes);
              equal (option string) None (Cache.load t (key ()))));
      test "swapped entry contents are misses, never a wrong-key replay"
        (fun () ->
          (* The frame binds the key (v2): two valid entries whose files an
             external tool swapped verify their payload digests fine, but
             each frame names the other key — both must miss, not replay the
             other key's payload. *)
          with_cache (fun t ~root:_ ~ws:_ ->
              let ka = key ~cmt:"a" () and kb = key ~cmt:"b" () in
              Cache.store t ~now:t0 ka "payload-a";
              Cache.store t ~now:t0 kb "payload-b";
              let pa = entry_path t ka and pb = entry_path t kb in
              let ba = read_file pa and bb = read_file pb in
              write_file pa bb;
              write_file pb ba;
              equal (option string) None (Cache.load t ka);
              equal (option string) None (Cache.load t kb)));
      test "an entry that is a directory is a miss" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let path = entry_path t (key ()) in
              Sys.remove path;
              Unix.mkdir path 0o755;
              equal (option string) None (Cache.load t (key ()))));
      test "a corrupt entry ages out through the sweep" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              write_file (entry_path t (key ())) "garbage";
              let s = Cache.sweep t ~now:(t0 +. (31. *. day)) ~read:[] in
              equal int 1 s.Cache.evicted_entries;
              is_false (Sys.file_exists (entry_path t (key ())))));
    ]

(* {1 Eviction} *)

let eviction =
  group "eviction"
    [
      test "an entry unread past max_age is evicted" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let s = Cache.sweep t ~now:(t0 +. (31. *. day)) ~read:[] in
              equal int 1 s.Cache.evicted_entries;
              equal (option string) None (Cache.load t (key ()));
              (* The stamp went with the entry. *)
              is_false (Sys.file_exists (entry_path t (key ()) ^ ".stamp"))));
      test "a younger entry survives" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let s = Cache.sweep t ~now:(t0 +. (29. *. day)) ~read:[] in
              equal int 0 s.Cache.evicted_entries;
              equal (option string) (Some "payload") (Cache.load t (key ()))));
      test "age exactly max_age is not yet evicted" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let s = Cache.sweep t ~now:(t0 +. Cache.max_age) ~read:[] in
              equal int 0 s.Cache.evicted_entries));
      test "a read stamp renews the lease" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              (* Read at day 15: the entry now lives from there, not t0. *)
              let s =
                Cache.sweep t ~now:(t0 +. (15. *. day)) ~read:[ key () ]
              in
              equal int 0 s.Cache.evicted_entries;
              let s = Cache.sweep t ~now:(t0 +. (40. *. day)) ~read:[] in
              equal int 0 s.Cache.evicted_entries;
              equal (option string) (Some "payload") (Cache.load t (key ()));
              let s = Cache.sweep t ~now:(t0 +. (46. *. day)) ~read:[] in
              equal int 1 s.Cache.evicted_entries));
      test "a missing stamp self-heals to a fresh lease" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              Sys.remove (entry_path t (key ()) ^ ".stamp");
              let s = Cache.sweep t ~now:(t0 +. (100. *. day)) ~read:[] in
              equal int 0 s.Cache.evicted_entries;
              (* The fresh lease still ages out. *)
              let s = Cache.sweep t ~now:(t0 +. (131. *. day)) ~read:[] in
              equal int 1 s.Cache.evicted_entries));
      test "a corrupt stamp self-heals to a fresh lease" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              write_file (entry_path t (key ()) ^ ".stamp") "not a number";
              let s = Cache.sweep t ~now:(t0 +. (100. *. day)) ~read:[] in
              equal int 0 s.Cache.evicted_entries;
              equal (option string) (Some "payload") (Cache.load t (key ()))));
      test "an orphaned stamp is deleted" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              Sys.remove (entry_path t (key ()));
              ignore (Cache.sweep t ~now:t0 ~read:[]);
              is_false (Sys.file_exists (entry_path t (key ()) ^ ".stamp"))));
      test "leftover temp files are deleted" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let residue =
                Filename.concat (Cache.dir t) ".litany.99999.7.tmp"
              in
              write_file residue "half-written";
              ignore (Cache.sweep t ~now:t0 ~read:[]);
              is_false (Sys.file_exists residue)));
      test "stamping a key never read is harmless" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let s = Cache.sweep t ~now:t0 ~read:[ key ~cmt:"other" () ] in
              equal int 0 s.Cache.evicted_entries));
      test "sweeping a workspace that never stored is a no-op" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              let s = Cache.sweep t ~now:t0 ~read:[] in
              equal int 0 s.Cache.evicted_entries;
              equal int 0 s.Cache.removed_workspaces));
    ]

(* {1 Workspace directories and markers} *)

let workspaces =
  group "workspaces"
    [
      test "dir is root/<32-hex workspace digest>" (fun () ->
          with_cache (fun t ~root ~ws:_ ->
              equal string root (Filename.dirname (Cache.dir t));
              is_true (is_hex32 (Filename.basename (Cache.dir t)))));
      test "every spelling of one workspace shares one directory" (fun () ->
          with_cache (fun t ~root ~ws ->
              let t' =
                Cache.create ~root ~workspace_root:(Filename.concat ws ".")
              in
              equal string (Cache.dir t) (Cache.dir t')));
      test "different workspaces get different directories" (fun () ->
          with_cache (fun t ~root ~ws:_ ->
              with_cache (fun _ ~root:_ ~ws:other ->
                  let t' = Cache.create ~root ~workspace_root:other in
                  is_false (String.equal (Cache.dir t) (Cache.dir t')))));
      test "a live sibling workspace is left alone" (fun () ->
          with_cache (fun t ~root ~ws:_ ->
              with_cache (fun _ ~root:_ ~ws:other ->
                  let t' = Cache.create ~root ~workspace_root:other in
                  Cache.store t ~now:t0 (key ()) "mine";
                  Cache.store t' ~now:t0 (key ()) "theirs";
                  let s = Cache.sweep t ~now:t0 ~read:[] in
                  equal int 0 s.Cache.removed_workspaces;
                  is_true (Sys.file_exists (Cache.dir t')))));
      test "a workspace whose root is gone is removed by a sibling's sweep"
        (fun () ->
          with_cache (fun t ~root ~ws:_ ->
              let other = Filename.temp_dir "litany-cache-doomed" "" in
              let t' = Cache.create ~root ~workspace_root:other in
              Cache.store t ~now:t0 (key ()) "mine";
              Cache.store t' ~now:t0 (key ()) "theirs";
              rm_rf other;
              let s = Cache.sweep t ~now:t0 ~read:[] in
              equal int 1 s.Cache.removed_workspaces;
              is_false (Sys.file_exists (Cache.dir t'));
              (* The sweeping workspace itself is untouched. *)
              equal (option string) (Some "mine") (Cache.load t (key ()))));
      test "a marker-less empty directory is crash residue and removed"
        (fun () ->
          with_cache (fun t ~root ~ws:_ ->
              Cache.store t ~now:t0 (key ()) "payload";
              let residue = Filename.concat root (String.make 32 '0') in
              Unix.mkdir residue 0o755;
              let s = Cache.sweep t ~now:t0 ~read:[] in
              equal int 1 s.Cache.removed_workspaces;
              is_false (Sys.file_exists residue)));
      test "a marker-less non-empty directory is left alone" (fun () ->
          with_cache (fun t ~root ~ws:_ ->
              let odd = Filename.concat root (String.make 32 '1') in
              Unix.mkdir odd 0o755;
              write_file (Filename.concat odd "entry") "bytes";
              let s = Cache.sweep t ~now:t0 ~read:[] in
              equal int 0 s.Cache.removed_workspaces;
              is_true (Sys.file_exists odd)));
      test "non-cache names in the root are never touched" (fun () ->
          with_cache (fun t ~root ~ws:_ ->
              let stray = Filename.concat root "README" in
              write_file stray "not a workspace";
              ignore (Cache.sweep t ~now:t0 ~read:[]);
              is_true (Sys.file_exists stray)));
    ]

(* {1 Concurrent writers} *)

let concurrency =
  group "concurrency"
    [
      test "racing writers: one complete payload wins, none is torn" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              let payloads =
                List.init 4 (fun i ->
                    String.concat "-"
                      (List.init 64 (fun j -> Printf.sprintf "p%d.%d" i j)))
              in
              for _ = 1 to 3 do
                let domains =
                  List.map
                    (fun p ->
                      Domain.spawn (fun () -> Cache.store t ~now:t0 (key ()) p))
                    payloads
                in
                List.iter Domain.join domains;
                match Cache.load t (key ()) with
                | None -> is_true false
                | Some got -> is_true (List.exists (String.equal got) payloads)
              done));
      test "loads racing stores always see a complete entry" (fun () ->
          with_cache (fun t ~root:_ ~ws:_ ->
              let payload tag =
                String.concat tag (List.init 64 string_of_int)
              in
              let a = payload "a" and b = payload "b" and c = payload "c" in
              Cache.store t ~now:t0 (key ()) a;
              let writer p =
                Domain.spawn (fun () ->
                    for _ = 1 to 50 do
                      Cache.store t ~now:t0 (key ()) p
                    done)
              in
              let d1 = writer b and d2 = writer c in
              for _ = 1 to 100 do
                match Cache.load t (key ()) with
                | None -> is_true false
                | Some got ->
                    is_true (List.exists (String.equal got) [ a; b; c ])
              done;
              Domain.join d1;
              Domain.join d2));
    ]

(* {1 Locating the cache} *)

let resolve_root =
  let env alist name = List.assoc_opt name alist in
  let full =
    [
      ("LITANY_CACHE_DIR", "/from-env");
      ("XDG_CACHE_HOME", "/xdg");
      ("HOME", "/home/me");
    ]
  in
  group "resolve-root"
    [
      test "--cache-dir wins over everything" (fun () ->
          equal (option string) (Some "/flag")
            (Cache.resolve_root ~cache_dir:"/flag" ~env:(env full) ()));
      test "LITANY_CACHE_DIR is next" (fun () ->
          equal (option string) (Some "/from-env")
            (Cache.resolve_root ~env:(env full) ()));
      test "XDG_CACHE_HOME/litany is next" (fun () ->
          equal (option string) (Some "/xdg/litany")
            (Cache.resolve_root
               ~env:(env [ ("XDG_CACHE_HOME", "/xdg"); ("HOME", "/home/me") ])
               ()));
      test "a relative XDG_CACHE_HOME is ignored per the XDG spec" (fun () ->
          equal (option string) (Some "/home/me/.cache/litany")
            (Cache.resolve_root
               ~env:(env [ ("XDG_CACHE_HOME", "rel"); ("HOME", "/home/me") ])
               ()));
      test "HOME/.cache/litany is the fallback" (fun () ->
          equal (option string) (Some "/home/me/.cache/litany")
            (Cache.resolve_root ~env:(env [ ("HOME", "/home/me") ]) ()));
      test "empty variables are ignored" (fun () ->
          equal (option string) (Some "/home/me/.cache/litany")
            (Cache.resolve_root
               ~env:
                 (env
                    [
                      ("LITANY_CACHE_DIR", "");
                      ("XDG_CACHE_HOME", "");
                      ("HOME", "/home/me");
                    ])
               ()));
      test "no determinable location is None — the driver runs uncached"
        (fun () ->
          equal (option string) None (Cache.resolve_root ~env:(env []) ()));
    ]

let () =
  run "litany_cache"
    [
      keys; storing; corruption; eviction; workspaces; concurrency; resolve_root;
    ]
