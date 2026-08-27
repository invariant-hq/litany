(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The dune half exercises [Litany.Adapter.Dune.roster ~build:false] over
   crafted build trees — the roster is read straight from the tree, so the
   tests spawn nothing. The walk half exercises [Litany.Adapter.Walk] over
   the compiled fixtures of test/unit and over crafted directory trees. *)

open Windtrap

module Dune = Litany.Adapter.Dune
module Walk = Litany.Adapter.Walk
module Roster = Litany.Roster

(* A crafted workspace: writers for source files, dune files, and empty
   artifact placeholders (the roster reads no artifact bytes). *)
let craft () =
  let dir = temp_dir () in
  let rec mkdir_p d =
    if not (Sys.file_exists d) then begin
      mkdir_p (Filename.dirname d);
      Sys.mkdir d 0o700
    end
  in
  let write rel contents =
    let path = Filename.concat dir rel in
    mkdir_p (Filename.dirname path);
    Out_channel.with_open_bin path (fun oc ->
        Out_channel.output_string oc contents)
  in
  (dir, write)

let dune_roster dir =
  require_ok ~msg:"dune roster"
    (Result.map_error
       (fun e -> `Msg (Format.asprintf "%a" Dune.pp_error e))
       (Dune.roster ~build:false ~root:dir ()))

let entry_for r source =
  match
    List.find_opt
      (fun e -> Roster.Entry.source e = source)
      (Roster.entries r)
  with
  | Some e -> e
  | None ->
      failf "no entry for %s (have: %s)" source
        (String.concat ", "
           (List.map Roster.Entry.source (Roster.entries r)))

let dune_tests =
  group "Dune"
    [
      test "an absent build tree is an empty, complete roster" (fun () ->
          let dir, write = craft () in
          write "dune-project" "(lang dune 3.0)\n";
          let r = dune_roster dir in
          is_true (Roster.complete r);
          equal int 0 (List.length (Roster.entries r)));
      test "a library unit carries its stanza's name, kind, and visibility"
        (fun () ->
          let dir, write = craft () in
          write "lib/dune"
            "(library (name inv) (public_name inventory))\n";
          write "lib/store.ml" "let x = 1\n";
          write "_build/default/lib/.inv.objs/byte/inv__Store.cmt" "";
          write "_build/default/lib/.inv.objs/byte/inv.cmt" "";
          write "_build/default/lib/inv.ml-gen" "";
          let r = dune_roster dir in
          let store = entry_for r "lib/store.ml" in
          equal (option string) (Some "inv") (Roster.Entry.library store);
          is_true (Roster.Entry.kind store = Some Roster.Library);
          is_true (Roster.Entry.visibility store = Roster.Public);
          (* The wrapped library's alias module stays, sourced from its
             generated impl. *)
          let alias = entry_for r "_build/default/lib/inv.ml-gen" in
          is_true (Roster.Entry.kind alias = Some Roster.Library));
      test "the trailing-underscore alias unit pairs its generated source"
        (fun () ->
          (* A wrapped library holding a module of its own name gets the
             [lib__] alias unit; its leaf is empty under the [__] split, so
             a naive pairing minted [dir/.ml] and every such unit skipped
             missing-source (75 units on one real tree). *)
          let dir, write = craft () in
          write "lib/dune" "(library (name inv))\n";
          write "lib/inv.ml" "";
          write "_build/default/lib/.inv.objs/byte/inv__.cmt" "";
          write "_build/default/lib/.inv.objs/byte/inv__Inv.cmt" "";
          write "_build/default/lib/inv__.ml-gen" "";
          let r = dune_roster dir in
          let alias = entry_for r "_build/default/lib/inv__.ml-gen" in
          equal (option string) (Some "inv") (Roster.Entry.library alias);
          ignore (entry_for r "lib/inv.ml"));
      test "a private library reads Private; an unfound stanza stays Unknown"
        (fun () ->
          let dir, write = craft () in
          write "lib/dune" "(library (name inv))\n";
          write "lib/store.ml" "";
          write "_build/default/lib/.inv.objs/byte/inv__Store.cmt" "";
          write "other/store2.ml" "";
          write "_build/default/other/.mystery.objs/byte/mystery__Store2.cmt"
            "";
          let r = dune_roster dir in
          is_true
            (Roster.Entry.visibility (entry_for r "lib/store.ml")
            = Roster.Private);
          let unfound = entry_for r "other/store2.ml" in
          is_true (Roster.Entry.visibility unfound = Roster.Unknown);
          (* The objs directory still names the owning library. *)
          equal (option string) (Some "mystery") (Roster.Entry.library unfound));
      test "the dune-file scan splits tests from executables" (fun () ->
          let dir, write = craft () in
          write "bin/dune" "(executable (name main))\n";
          write "bin/main.ml" "";
          write "_build/default/bin/.main.eobjs/byte/dune__exe__Main.cmt" "";
          write "test/dune" "(test (name t))\n";
          write "test/t.ml" "";
          write "_build/default/test/.t.eobjs/byte/dune__exe__T.cmt" "";
          write "loose/dune" "; nothing relevant\n";
          write "loose/x.ml" "";
          write "_build/default/loose/.x.eobjs/byte/dune__exe__X.cmt" "";
          let r = dune_roster dir in
          is_true (Roster.Entry.kind (entry_for r "bin/main.ml")
                   = Some Roster.Executable);
          is_true (Roster.Entry.kind (entry_for r "test/t.ml")
                   = Some Roster.Test);
          (* An eobjs unit whose stanza the scan cannot find stays
             metadata-less: exe-family is known, which stanza is not. *)
          let loose = entry_for r "loose/x.ml" in
          is_true (Roster.Entry.kind loose = None);
          equal (option string) None (Roster.Entry.library loose));
      test "generated harness stanzas and the exe alias are excluded"
        (fun () ->
          (* The inline-tests runner mirrors a real stanza's sources under
             a generated dot-directory stanza; admitting it minted
             duplicate-source entries (and crashed the unit-file encoder on
             a real tree). The per-stanza [dune__exe] alias collides by
             construction. *)
          let dir, write = craft () in
          write "lib/dune" "(library (name inv) (inline_tests))\n";
          write "lib/store.ml" "";
          write "_build/default/lib/.inv.objs/byte/inv__Store.cmt" "";
          write
            "_build/default/lib/.inv.inline-tests/.t.eobjs/byte/dune__exe__Main.cmt"
            "";
          write "_build/default/bin/.main.eobjs/byte/dune__exe.cmt" "";
          let r = dune_roster dir in
          equal int 1 (List.length (Roster.entries r));
          equal string "lib/store.ml"
            (Roster.Entry.source (List.hd (Roster.entries r))));
      test "qualified subdir units pair through the source index" (fun () ->
          (* Under [(include_subdirs qualified)] the unit's source lives
             deeper than the stanza directory; the leaf convention alone
             guessed [lib/read_file.ml] and skipped missing-source (40
             units on one real tree). The proximity-scoped index pairs it;
             a same-basename source in a sibling stanza's subtree does not
             steal it. *)
          let dir, write = craft () in
          write "lib/dune" "(library (name inv))\n";
          write "lib/fs/read_file.ml" "";
          write "other/read_file.ml" "";
          write "_build/default/lib/.inv.objs/byte/inv__Fs__Read_file.cmt" "";
          let r = dune_roster dir in
          ignore (entry_for r "lib/fs/read_file.ml"));
      test "a built pp source rides its entry" (fun () ->
          let dir, write = craft () in
          write "lib/dune" "(library (name inv))\n";
          write "lib/store.ml" "";
          write "_build/default/lib/.inv.objs/byte/inv__Store.cmt" "";
          write "_build/default/lib/store.pp.ml" "";
          let r = dune_roster dir in
          equal (option string)
            (Some "_build/default/lib/store.pp.ml")
            (Roster.Entry.preprocessed_source (entry_for r "lib/store.ml")));
      test "cmi dirs are the walked object dirs plus the pkg store" (fun () ->
          let dir, write = craft () in
          write "lib/dune" "(library (name inv))\n";
          write "lib/store.ml" "";
          write "_build/default/lib/.inv.objs/byte/inv__Store.cmt" "";
          write "_build/_private/default/.pkg/dep.1.0/target/lib/dep/dep.cmi"
            "";
          write
            "_build/_private/default/.pkg/dep.1.0/target/lib/dep/sub/none.txt"
            "";
          let r = dune_roster dir in
          is_true ~msg:"local objs dir"
            (List.mem "_build/default/lib/.inv.objs/byte" (Roster.cmi_dirs r));
          is_true ~msg:"pkg store dir"
            (List.mem "_build/_private/default/.pkg/dep.1.0/target/lib/dep"
               (Roster.cmi_dirs r));
          is_false ~msg:"cmi-less dir excluded"
            (List.mem
               "_build/_private/default/.pkg/dep.1.0/target/lib/dep/sub"
               (Roster.cmi_dirs r)));
      test "is deterministic across runs" (fun () ->
          let dir, write = craft () in
          write "lib/dune" "(library (name inv))\n";
          write "lib/a.ml" "";
          write "lib/b.ml" "";
          write "_build/default/lib/.inv.objs/byte/inv__A.cmt" "";
          write "_build/default/lib/.inv.objs/byte/inv__B.cmt" "";
          let s r = List.map Roster.Entry.source (Roster.entries r) in
          equal (list string) (s (dune_roster dir)) (s (dune_roster dir)));
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

let () = run "litany_adapter" [ dune_tests; walk_tests ]
