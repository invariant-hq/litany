(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module W = Litany.Write

let in_dir f =
  let dir = Filename.temp_file "litany-write" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  Fun.protect
    ~finally:(fun () ->
      Array.iter
        (fun n ->
          try Sys.remove (Filename.concat dir n) with Sys_error _ -> ())
        (Sys.readdir dir);
      try Unix.rmdir dir with Unix.Unix_error _ -> ())
    (fun () -> f dir)

let read path = In_channel.with_open_bin path In_channel.input_all

let () =
  Windtrap.run "litany_write"
    [
      test "publishes bytes, creating or replacing" (fun () ->
          in_dir @@ fun dir ->
          let path = Filename.concat dir "out" in
          equal (result unit string) (Ok ()) (W.atomic ~path "one");
          equal string "one" (read path);
          equal (result unit string) (Ok ()) (W.atomic ~fsync:false ~path "two");
          equal string "two" (read path));
      test "no temp residue after success or failure" (fun () ->
          in_dir @@ fun dir ->
          let path = Filename.concat dir "out" in
          ignore (W.atomic ~path "bytes");
          (match W.atomic ~path:(Filename.concat dir "no/such/dir") "x" with
          | Ok () -> fail "write into a missing directory succeeded"
          | Error _ -> ());
          equal (list string) [ "out" ]
            (List.sort String.compare (Array.to_list (Sys.readdir dir))));
      test "mode sets the created file's permissions" (fun () ->
          in_dir @@ fun dir ->
          let path = Filename.concat dir "out" in
          equal (result unit string) (Ok ())
            (W.atomic ~mode:0o600 ~path "secret");
          equal int 0o600 (Unix.stat path).Unix.st_perm);
      test "a failed write leaves the target's bytes alone" (fun () ->
          in_dir @@ fun dir ->
          let path = Filename.concat dir "out" in
          ignore (W.atomic ~path "keep");
          (* A directory in place of the temp target's rename destination:
             rename over an existing non-empty directory fails. *)
          let clash = Filename.concat dir "clash" in
          Unix.mkdir clash 0o755;
          ignore (W.atomic ~path:(Filename.concat clash "no/way") "x");
          equal string "keep" (read path));
    ]
