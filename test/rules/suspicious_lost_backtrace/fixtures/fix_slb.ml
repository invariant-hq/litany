(* Fixture for suspicious-lost-backtrace: positives carry the FIRE marker;
   every other binding is a negative lookalike from the spec plus
   adversarial extras. *)

let log_error e = prerr_endline (Printexc.to_string e)
let cleanup () = ()
let restore () = ()
let m = Mutex.create ()

(* The classic: logging between catch and reraise. *)
let p1 f =
  try f ()
  with e ->
    log_error e;
    raise e (* FIRE *)

(* Cleanup-then-reraise. *)
let p2 f =
  try f ()
  with e ->
    Mutex.unlock m;
    raise e (* FIRE *)

(* A match exception arm. *)
let p3 job =
  match job () with
  | v -> v
  | exception e ->
      cleanup ();
      raise e (* FIRE *)

(* A let spine. *)
let p4 f =
  try f ()
  with e ->
    let () = restore () in
    raise e (* FIRE *)

(* The sharpest form: a caught raise inside the work still rewrites the
   buffer the reraise preserves. *)
let p5 f g =
  try f ()
  with e ->
    (try g () with _ -> ());
    raise e (* FIRE *)

(* negative: the bare reraise is already backtrace-preserving *)
let n1 f = try f () with e -> raise e

(* negative: the remedy — capture first, raise_with_backtrace last *)
let n2 f =
  try f ()
  with e ->
    let bt = Printexc.get_raw_backtrace () in
    cleanup ();
    Printexc.raise_with_backtrace e bt

(* negative: a different (wrapped) exception is a fresh raise site *)
exception Wrapped of exn

let n3 f =
  try f ()
  with e ->
    log_error e;
    raise (Wrapped e)

(* negative: raise_notrace is an explicit discard *)
let n4 f =
  try f ()
  with e ->
    log_error e;
    raise_notrace e

(* negative (adversarial): a shadowed raise resolves locally *)
let n5 my_raise f =
  let raise = my_raise in
  try f ()
  with e ->
    log_error e;
    raise e

(* negative: no bound exception variable — a fresh raise, not a reraise *)
let n6 f =
  try f ()
  with Failure msg ->
    cleanup ();
    raise (Failure msg)

(* negative: the if-guarded reraise is outside the v1 spine (recorded
   false negative) *)
let retriable _ = false
let n7 f = try f () with e -> if retriable e then 0 else raise e

(* negative: a guarded handler is clean in v1 *)
let n8 p f =
  try f ()
  with e when p e ->
    log_error e;
    raise e

(* negative (adversarial extra): re-raising a different bound exception *)
let n9 e2 f =
  try f ()
  with e ->
    log_error e;
    raise e2
