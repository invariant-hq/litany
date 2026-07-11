(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Roster = Litany.Roster

let entry = Testable.make ~pp:Roster.Entry.pp ~equal:( = )

let full ?(library = "lib") ?(kind = Roster.Library) source =
  Roster.Entry.v ~source ~cmt:(source ^ ".cmt") ~library ~kind ()

let entries =
  group "Entry"
    [
      test "an entry naming no artifact constructs; admission skips it"
        (fun () ->
          (* The skip taxonomy already owns this state —
             [Litany.Unit.load] returns [Missing_artifact] for it. *)
          let e = Roster.Entry.v ~source:"a.ml" () in
          equal (option string) None (Roster.Entry.cmt e);
          equal (option string) None (Roster.Entry.cmti e));
      test "cmt alone is enough" (fun () ->
          let e = Roster.Entry.v ~source:"a.ml" ~cmt:"a.cmt" () in
          equal (option string) (Some "a.cmt") (Roster.Entry.cmt e);
          equal (option string) None (Roster.Entry.cmti e));
      test "cmti alone is enough" (fun () ->
          let e = Roster.Entry.v ~source:"a.ml" ~cmti:"a.cmti" () in
          equal (option string) None (Roster.Entry.cmt e);
          equal (option string) (Some "a.cmti") (Roster.Entry.cmti e));
      test "paths are kept verbatim" (fun () ->
          let e =
            Roster.Entry.v ~source:"lib/a.ml" ~cmt:"_build/x/a.cmt"
              ~preprocessed_source:"_build/x/a.pp.ml" ()
          in
          equal string "lib/a.ml" (Roster.Entry.source e);
          equal (option string) (Some "_build/x/a.pp.ml")
            (Roster.Entry.preprocessed_source e));
      test "metadata defaults to absent, visibility to Unknown" (fun () ->
          let e = Roster.Entry.v ~source:"a.ml" ~cmt:"a.cmt" () in
          equal (option string) None (Roster.Entry.library e);
          is_true (Roster.Entry.kind e = None);
          is_true (Roster.Entry.visibility e = Roster.Unknown));
      test "metadata is recorded when given" (fun () ->
          let e =
            Roster.Entry.v ~source:"a.ml" ~cmt:"a.cmt" ~library:"mylib"
              ~visibility:Roster.Private ~kind:Roster.Executable ()
          in
          equal (option string) (Some "mylib") (Roster.Entry.library e);
          is_true (Roster.Entry.kind e = Some Roster.Executable);
          is_true (Roster.Entry.visibility e = Roster.Private));
    ]

let rosters =
  group "roster"
    [
      test "defaults: incomplete, no cmi dirs" (fun () ->
          let r = Roster.v [ full "a.ml" ] in
          is_false (Roster.complete r);
          equal (list string) [] (Roster.cmi_dirs r));
      test "entries keep the adapter's order" (fun () ->
          let e1 = full "a.ml" and e2 = full "b.ml" and e3 = full "c.ml" in
          equal (list entry) [ e1; e2; e3 ]
            (Roster.entries (Roster.v [ e1; e2; e3 ])));
      test "cmi_dirs are kept verbatim, in order" (fun () ->
          let r = Roster.v ~cmi_dirs:[ "b"; "a" ] [ full "a.ml" ] in
          equal (list string) [ "b"; "a" ] (Roster.cmi_dirs r));
    ]

let capability =
  group "project_capable"
    [
      test "complete with full metadata is capable" (fun () ->
          is_true
            (Roster.project_capable
               (Roster.v ~complete:true [ full "a.ml"; full "b.ml" ])));
      test "an incomplete roster is never capable" (fun () ->
          is_false
            (Roster.project_capable (Roster.v ~complete:false [ full "a.ml" ])));
      test "one entry without a library breaks capability" (fun () ->
          let bare =
            Roster.Entry.v ~source:"b.ml" ~cmt:"b.cmt" ~kind:Roster.Test ()
          in
          is_false
            (Roster.project_capable
               (Roster.v ~complete:true [ full "a.ml"; bare ])));
      test "one entry without a kind breaks capability" (fun () ->
          let bare =
            Roster.Entry.v ~source:"b.ml" ~cmt:"b.cmt" ~library:"lib" ()
          in
          is_false
            (Roster.project_capable
               (Roster.v ~complete:true [ full "a.ml"; bare ])));
      test "Unknown visibility never gates capability" (fun () ->
          (* Unknown resolves to Public under root policy; capability only
             needs library and kind. *)
          let e =
            Roster.Entry.v ~source:"a.ml" ~cmt:"a.cmt" ~library:"lib"
              ~visibility:Roster.Unknown ~kind:Roster.Library ()
          in
          is_true (Roster.project_capable (Roster.v ~complete:true [ e ])));
    ]

let () = run "litany_roster" [ entries; rosters; capability ]
