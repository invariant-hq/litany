(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The describe half decodes describe_workspace.csexp — real bytes captured
   from this workspace with [dune describe workspace --format csexp --lang
   0.1 --with-deps] at M2 time and committed verbatim, so the decoder is
   pinned to what dune actually emits, not to what its documentation says.
   The walk half exercises [Litany.Adapter.Walk] over the compiled fixtures
   of test/unit and over crafted directory trees. *)

open Windtrap

(* The describe decode is adapter-internal (a non-facade module of the
   litany library, litany_dune_describe.ml); reach it by its unmangled global
   name rather than widening the gated [Litany.Adapter] surface. *)
module Describe = Litany.Dune_describe
module Walk = Litany.Adapter.Walk
module Roster = Litany.Roster

let fixture =
  In_channel.with_open_bin "describe_workspace.csexp" In_channel.input_all

let decoded =
  fixture |> Describe.decode |> Result.map_error (fun e -> `Msg e) |> fun r ->
  lazy (require_ok ~msg:"fixture decode" r)

let libraries d =
  List.filter_map
    (function Describe.Library l -> Some l | Describe.Executables _ -> None)
    d.Describe.stanzas

let executables d =
  List.filter_map
    (function Describe.Executables e -> Some e | Describe.Library _ -> None)
    d.Describe.stanzas

let describe_tests =
  group "Dune_describe"
    [
      test "decodes the captured workspace reply" (fun () ->
          let d = Lazy.force decoded in
          equal (option string)
            (Some "/Users/tmattio/Workspace/invariant/litany") d.Describe.root;
          equal (option string) (Some "_build/default") d.Describe.build_context);
      test "finds every stanza of the captured reply" (fun () ->
          let d = Lazy.force decoded in
          equal int ~msg:"local libraries" 21
            (List.length
               (List.filter
                  (fun (l : Describe.library) -> l.local)
                  (libraries d)));
          equal int ~msg:"executables stanzas" 3 (List.length (executables d)));
      test "decodes a local library's module paths" (fun () ->
          let d = Lazy.force decoded in
          let ident =
            List.find
              (fun (l : Describe.library) -> l.name = "litany_ident")
              (libraries d)
          in
          is_true ident.local;
          equal (option string) (Some "_build/default/lib/ident")
            ident.source_dir;
          equal (list string)
            [ "_build/default/lib/ident/.litany_ident.objs/byte" ]
            ident.include_dirs;
          match ident.modules with
          | [ m ] ->
              equal string "Litany_ident" m.name;
              equal (option string)
                (Some "_build/default/lib/ident/litany_ident.ml") m.impl;
              equal (option string)
                (Some "_build/default/lib/ident/litany_ident.mli") m.intf;
              equal (option string)
                (Some
                   "_build/default/lib/ident/.litany_ident.objs/byte/litany_ident.cmt")
                m.cmt;
              equal (option string)
                (Some
                   "_build/default/lib/ident/.litany_ident.objs/byte/litany_ident.cmti")
                m.cmti
          | ms -> failf "expected one module, got %d" (List.length ms));
      test "decodes a non-local library with empty modules" (fun () ->
          let d = Lazy.force decoded in
          let compiler_libs =
            List.find
              (fun (l : Describe.library) -> l.name = "compiler-libs")
              (libraries d)
          in
          is_false compiler_libs.local;
          equal (list string) []
            (List.map
               (fun (m : Describe.module_) -> m.name)
               compiler_libs.modules);
          is_true (compiler_libs.include_dirs <> []));
      test "decodes an executables stanza" (fun () ->
          let d = Lazy.force decoded in
          let main =
            List.find
              (fun (e : Describe.executables) -> e.names = [ "main" ])
              (executables d)
          in
          match main.modules with
          | [ m ] ->
              equal string "Main" m.name;
              equal (option string)
                (Some "_build/default/bin/.main.eobjs/byte/dune__exe__Main.cmt")
                m.cmt
          | ms -> failf "expected one module, got %d" (List.length ms));
      test "rejects truncated bytes with an offset" (fun () ->
          match Describe.decode (String.sub fixture 0 100) with
          | Error reason -> contains ~sub:"byte" reason
          | Ok _ -> fail "decoded truncated bytes");
      test "rejects a top-level atom" (fun () ->
          is_true (Result.is_error (Describe.decode "5:hello")));
      test "rejects a lying length prefix" (fun () ->
          is_true (Result.is_error (Describe.decode "(999:x)")));
      test "rejects trailing data" (fun () ->
          is_true (Result.is_error (Describe.decode "()3:foo")));
      test "tolerates unknown item kinds" (fun () ->
          match Describe.decode "((7:mystery1:x)(4:root1:/))" with
          | Ok d ->
              equal (option string) (Some "/") d.Describe.root;
              equal int 0 (List.length d.Describe.stanzas)
          | Error e -> failf "refused a forward-compatible reply: %s" e);
    ]

(* {1 The artifact walk} *)

let entry_source e = Roster.Entry.source e

let walk_fixtures () =
  require_ok ~msg:"walk roster"
    (Result.map_error
       (fun e -> `Msg (Format.asprintf "%a" Walk.pp_error e))
       (Walk.roster ~cmt_root:"fixtures/unit" ~source_root:"fixtures/unit"))

let walk_tests =
  group "Walk"
    [
      test "refuses a missing cmt root" (fun () ->
          match Walk.roster ~cmt_root:"no-such-dir" ~source_root:"." with
          | Error (Walk.Root_missing dir) -> equal string "no-such-dir" dir
          | Ok _ -> fail "walked a missing directory");
      test "refuses a missing source root" (fun () ->
          is_true
            (Result.is_error
               (Walk.roster ~cmt_root:"." ~source_root:"no-such-dir")));
      test "pairs artifacts with editable sources by unit name" (fun () ->
          let r = walk_fixtures () in
          is_false (Roster.complete r);
          let sources = List.map entry_source (Roster.entries r) in
          is_true ~msg:"wit_direct paired"
            (List.mem "fixtures/unit/plain/wit_direct.ml" sources);
          is_true ~msg:"wit_mli paired"
            (List.mem "fixtures/unit/plain/wit_mli.ml" sources));
      test "pairs a cmt with its cmti in one entry" (fun () ->
          let r = walk_fixtures () in
          let entry =
            List.find
              (fun e -> entry_source e = "fixtures/unit/plain/wit_mli.ml")
              (Roster.entries r)
          in
          is_some (Roster.Entry.cmt entry);
          is_some (Roster.Entry.cmti entry);
          (* The text lane's second file: the
             paired editable mli rides the entry. *)
          equal (option string) (Some "fixtures/unit/plain/wit_mli.mli")
            (Roster.Entry.interface_source entry));
      test "an implementation-only unit names no interface source" (fun () ->
          let r = walk_fixtures () in
          let entry =
            List.find
              (fun e -> entry_source e = "fixtures/unit/plain/wit_direct.ml")
              (Roster.entries r)
          in
          equal (option string) None (Roster.Entry.interface_source entry));
      test "cmi_dirs are the walked artifact directories" (fun () ->
          let r = walk_fixtures () in
          is_true
            (List.mem "fixtures/unit/plain/.fix_wit.objs/byte"
               (Roster.cmi_dirs r)));
      test "supplies no ownership metadata" (fun () ->
          let r = walk_fixtures () in
          List.iter
            (fun e ->
              equal (option string) None (Roster.Entry.library e);
              is_true (Roster.Entry.visibility e = Roster.Unknown);
              is_true (Roster.Entry.kind e = None))
            (Roster.entries r));
      test "is deterministic across runs" (fun () ->
          let s r = List.map entry_source (Roster.entries r) in
          equal (list string) (s (walk_fixtures ())) (s (walk_fixtures ())));
      test "the basename fallback stays inside the artifact's subtree"
        (fun () ->
          (* Over a store of unrelated trees, a cmt in one subtree
             must not pair with a same-basename source in another — the
             global sorted-first pick stole ~20% of a real store's units as
             stale skips and printed findings under other packages' paths.
             Scoped: [bar] pairs within pkga even though the directory
             names differ; [foo]'s only candidate lives in pkgb and is
             refused (the default, nonexistent mirrored path costs a
             missing-source skip at join time); a root-level artifact has
             no subtree to scope by and keeps the sorted-first pick. *)
          let dir = temp_dir () in
          let rec mkdir_p d =
            if not (Sys.file_exists d) then begin
              mkdir_p (Filename.dirname d);
              Sys.mkdir d 0o700
            end
          in
          let write rel =
            let path = Filename.concat dir rel in
            mkdir_p (Filename.dirname path);
            Out_channel.with_open_bin path (fun oc ->
                Out_channel.output_string oc "irrelevant bytes")
          in
          List.iter write
            [
              "pkga/objs/foo.cmt";
              "pkga/objs/bar.cmt";
              "pkga/src/bar.ml";
              "pkgb/src/foo.ml";
              "baz.cmt";
              "src2/baz.ml";
            ];
          let r =
            require_ok
              (Result.map_error
                 (fun e -> `Msg (Format.asprintf "%a" Walk.pp_error e))
                 (Walk.roster ~cmt_root:dir ~source_root:dir))
          in
          let source_of cmt_rel =
            let cmt = Filename.concat dir cmt_rel in
            match
              List.find_opt
                (fun e -> Roster.Entry.cmt e = Some cmt)
                (Roster.entries r)
            with
            | Some e -> entry_source e
            | None -> failf "no entry for %s" cmt_rel
          in
          equal ~msg:"in-subtree fallback pairs" string
            (Filename.concat dir "pkga/src/bar.ml")
            (source_of "pkga/objs/bar.cmt");
          equal ~msg:"cross-subtree candidate refused" string
            (Filename.concat dir "pkga/objs/foo.ml")
            (source_of "pkga/objs/foo.cmt");
          equal ~msg:"root-level artifact keeps the sorted-first pick" string
            (Filename.concat dir "src2/baz.ml")
            (source_of "baz.cmt"));
      test "project markers stop the fallback scope below a shared parent"
        (fun () ->
          (* The one-segment floor is a package boundary only
             for flat stores. Projects nested under a shared parent segment
             (duniverse or vendor dirs) satisfy the floor via the parent
             alone, so an artifact in duniverse/x with no in-package
             candidate would pair with a same-basename source in
             duniverse/y again. When the artifact's ancestry carries a
             project marker (dune-project here) strictly below the walked
             root, the deepest marked directory bounds the scope: the
             cross-project candidate is refused, while an in-project
             candidate still pairs across differing dir names. *)
          let dir = temp_dir () in
          let rec mkdir_p d =
            if not (Sys.file_exists d) then begin
              mkdir_p (Filename.dirname d);
              Sys.mkdir d 0o700
            end
          in
          let write rel =
            let path = Filename.concat dir rel in
            mkdir_p (Filename.dirname path);
            Out_channel.with_open_bin path (fun oc ->
                Out_channel.output_string oc "irrelevant bytes")
          in
          List.iter write
            [
              "duniverse/x/dune-project";
              "duniverse/x/objs/foo.cmt";
              "duniverse/x/objs/bar.cmt";
              "duniverse/x/src/bar.ml";
              "duniverse/y/dune-project";
              "duniverse/y/src/foo.ml";
            ];
          let r =
            require_ok
              (Result.map_error
                 (fun e -> `Msg (Format.asprintf "%a" Walk.pp_error e))
                 (Walk.roster ~cmt_root:dir ~source_root:dir))
          in
          let source_of cmt_rel =
            let cmt = Filename.concat dir cmt_rel in
            match
              List.find_opt
                (fun e -> Roster.Entry.cmt e = Some cmt)
                (Roster.entries r)
            with
            | Some e -> entry_source e
            | None -> failf "no entry for %s" cmt_rel
          in
          equal ~msg:"cross-project candidate under the shared parent refused"
            string
            (Filename.concat dir "duniverse/x/objs/foo.ml")
            (source_of "duniverse/x/objs/foo.cmt");
          equal ~msg:"in-project fallback still pairs" string
            (Filename.concat dir "duniverse/x/src/bar.ml")
            (source_of "duniverse/x/objs/bar.cmt"));
      bracket
        ~setup:(fun () ->
          (* A hostile artifact dir: one real artifact name, one dangling
             symlink with an artifact name. The walk reads no artifact
             bytes, so any content does. *)
          let dir = Filename.temp_dir "litany-walk" "" in
          Out_channel.with_open_bin (Filename.concat dir "real.cmt") (fun oc ->
              Out_channel.output_string oc "not really a cmt");
          Unix.symlink
            (Filename.concat dir "deleted.cmt")
            (Filename.concat dir "dangling.cmt");
          dir)
        ~teardown:(fun dir ->
          Array.iter
            (fun f -> Sys.remove (Filename.concat dir f))
            (Sys.readdir dir);
          Sys.rmdir dir)
        "skips dangling symlinks silently"
        (fun dir ->
          let r =
            require_ok
              (Result.map_error
                 (fun e -> `Msg (Format.asprintf "%a" Walk.pp_error e))
                 (Walk.roster ~cmt_root:dir ~source_root:dir))
          in
          match Roster.entries r with
          | [ e ] ->
              equal (option string)
                (Some (Filename.concat dir "real.cmt"))
                (Roster.Entry.cmt e)
          | es ->
              failf "expected the one real artifact, got %d" (List.length es));
    ]

let () = run "litany_adapter" [ describe_tests; walk_tests ]
