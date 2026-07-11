(* Fixture for suspicious-file-exists-race: positives carry the FIRE
   marker; negatives are the spec's named lookalikes plus adversarial
   extras. *)

(* Guarded remove — the finally-cleanup shape. *)
let cleanup path = if Sys.file_exists path then Sys.remove path (* FIRE *)

(* Guarded remove as a statement before re-creating the file. *)
let fresh candidate =
  if Sys.file_exists candidate then Sys.remove candidate (* FIRE *);
  open_out candidate

(* Negated guard creating the path: parallel runs race to EEXIST. *)
let ensure dir =
  if not (Sys.file_exists dir) then Sys.mkdir dir 0o755 (* FIRE *)

(* The create arm in the else of a plain guard (the mkdir_p shape). *)
let rec mkdir_p path =
  if String.equal path "/" then ()
  else if Sys.file_exists path then () (* FIRE *)
  else begin
    mkdir_p (Filename.dirname path);
    Unix.mkdir path 0o755
  end

(* Guarded unlink and rmdir through a match on the file kind. *)
let remove_any path =
  if Sys.file_exists path (* FIRE *) then
    match (Unix.lstat path).Unix.st_kind with
    | Unix.S_DIR -> Unix.rmdir path
    | _ -> Unix.unlink path

(* Guarded rename: either rename argument may be the probed path. *)
let backup dst =
  if Sys.file_exists dst (* FIRE *) then Sys.rename dst (dst ^ ".bak")

(* The is_directory refinement conjunct. *)
let drop_dir p =
  if Sys.file_exists p && Sys.is_directory p then Unix.rmdir p (* FIRE *)

(* A literal path is a pure probe. *)
let clear_lock () =
  if Sys.file_exists "sfer.lock" then Sys.remove "sfer.lock" (* FIRE *)

(* Alias transparency: [module S = Sys] resolves through. *)
module S = Sys

let alias_cleanup path = if S.file_exists path then S.remove path (* FIRE *)

(* Negated guard with the op in the else arm — the swapped spelling. *)
let swap_arms path =
  if not (Sys.file_exists path) then () else Sys.remove path (* FIRE *)

(* A nested exists-guard is a boundary: the inner if reports itself,
   once — the outer guard stays silent. *)
let nested path =
  if Sys.file_exists path then
    if Sys.file_exists path then Sys.remove path (* FIRE *)

(* negative: platform probe — no op-set call on the tested path. *)
let stat_source () = if Sys.file_exists "/proc/stat" then "linux" else "macos"

(* negative: validation producing a value — no mutating op. *)
let check_dir path =
  if Sys.file_exists path then
    if Sys.is_directory path then Ok () else Error (path ^ " is not a directory")
  else Error (path ^ " is missing")

(* negative: the handler carve-out — the guarded op tolerates the race. *)
let ensure_dir dir =
  if not (Sys.file_exists dir) then
    try Sys.mkdir dir 0o755 with Sys_error _ -> ()

(* negative: a match with an exception case handles its scrutinee. *)
let quiet_remove path =
  if Sys.file_exists path then
    match Sys.remove path with () -> () | exception Sys_error _ -> ()

(* negative: the existence test is the result, not a guard. *)
let wrote_nothing path = not (Sys.file_exists path)

(* negative: guarded read — the same race, a muddier fix; recorded
   false negative. *)
let entries dir = if Sys.file_exists dir then Sys.readdir dir else [||]

(* negative: an op on a different path never counts. *)
let other src dst = if Sys.file_exists src then Sys.remove dst

(* negative: a computed path refuses the purity test — identical slices
   of two calls could denote different files. *)
let computed dir name =
  if Sys.file_exists (Filename.concat dir name) then
    Sys.remove (Filename.concat dir name)

(* negative: the op deferred into a closure leaves the guarded window. *)
let deferred path =
  if Sys.file_exists path then at_exit (fun () -> Sys.remove path)

(* negative (adversarial): a same-spelled local Sys resolves to local
   declarations, never to Stdlib.Sys. *)
module Local = struct
  module Sys = struct
    let file_exists _ = true
    let remove _ = ()
  end

  let shadowed path = if Sys.file_exists path then Sys.remove path
end

(* negative: a let that rebinds the probed identifier is a
   boundary — past it, the spelling names a different file, so slice
   equality would compare two different paths. *)
let rotate p =
  if Sys.file_exists p then begin
    let p = p ^ ".bak" in
    Sys.remove p
  end
