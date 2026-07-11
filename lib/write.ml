(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Unique temp names without [Filename.temp_file]: its shared PRNG is not
   domain-safe, and pid + atomic counter is unique across processes and
   domains alike. The ".tmp" suffix is what the cache sweep recognizes as
   residue. *)
let temp_counter = Atomic.make 0

let temp_path ~dir =
  let n = Atomic.fetch_and_add temp_counter 1 in
  Filename.concat dir (Printf.sprintf ".litany.%d.%d.tmp" (Unix.getpid ()) n)

let atomic ?(fsync = true) ?(mode = 0o644) ~path bytes =
  let tmp = temp_path ~dir:(Filename.dirname path) in
  match
    let fd =
      Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL ] mode
    in
    let close_fd () = try Unix.close fd with Unix.Unix_error _ -> () in
    (match
       let len = String.length bytes in
       let rec write off =
         if off < len then
           write (off + Unix.write_substring fd bytes off (len - off))
       in
       write 0;
       if fsync then Unix.fsync fd
     with
    | () -> close_fd ()
    | exception e ->
        let bt = Printexc.get_raw_backtrace () in
        close_fd ();
        Printexc.raise_with_backtrace e bt);
    Sys.rename tmp path
  with
  | () -> Ok ()
  | exception Sys_error msg ->
      (try Sys.remove tmp with Sys_error _ -> ());
      Error msg
  | exception Unix.Unix_error (err, _, _) ->
      (try Sys.remove tmp with Sys_error _ -> ());
      Error (Unix.error_message err)
