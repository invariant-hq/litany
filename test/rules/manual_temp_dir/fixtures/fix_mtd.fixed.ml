(* Fixture for manual-temp-dir: each FIRE marker sits on a temp_file
   binding whose body removes the bound path and re-creates it as a
   directory; every other shape is a negative from the spec plus the
   shadowing adversarial. Nothing here runs — the library only
   compiles. *)

(* The windtrap shape: Unix pair, default permissions — fixable. *)
let with_dir prefix =
  let path = Filename.temp_dir prefix ".dir" in (* FIRE *)
  path

(* The sift shape: Sys pair, non-default literal permissions carried as
   ~perms: — fixable. *)
let make prefix =
  let dir = Filename.temp_dir prefix "" ~perms:0o755 in (* FIRE *)
  dir

(* One intervening statement: the v1 window fires, the fix refuses. *)
let logged prefix log =
  let d = Filename.temp_file prefix "" in (* FIRE *)
  Sys.remove d;
  log d;
  Unix.mkdir d 0o700;
  d

(* The mkdir is the final statement: the finding fires, the fix
   refuses — nothing would be left binding the path. *)
let create prefix =
  let d = Filename.temp_file prefix "" in (* FIRE *)
  Sys.remove d;
  Unix.mkdir d 0o700

(* The remedy, present in the same workspace. *)
let good prefix = Filename.temp_dir prefix ""

(* An actual temp file for atomic write-then-rename: the evaluated
   ~temp_dir is tolerated by the view, and no remove/mkdir follows. *)
let atomic dir path write =
  let tmp = Filename.temp_file ~temp_dir:dir (Filename.basename path) ".tmp" in
  write tmp;
  Sys.rename tmp path

(* A temp file used as a file. *)
let as_file prefix use =
  let f = Filename.temp_file prefix ".ml" in
  use f;
  Sys.remove f

(* Identity, not spelling: the remove and mkdir touch another path. *)
let other prefix q =
  let d = Filename.temp_file prefix "" in
  Sys.remove q;
  Sys.mkdir q 0o700;
  d

(* Adversarial: a same-named local temp_file is a different
   declaration and never matches. *)
module Local_filename = struct
  let temp_file p s = p ^ s
end

let shadowed p =
  let d = Local_filename.temp_file p "" in
  Sys.remove d;
  Sys.mkdir d 0o700;
  d
