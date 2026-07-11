(* Fixture for suspicious-wall-clock-elapsed: positives carry the FIRE
   marker; every other binding is a negative from the spec plus one
   adversarial extra. *)

(* Deadline arithmetic: wall-clock read on the left. *)
let deadline timeout = Unix.gettimeofday () +. timeout (* FIRE *)

(* Elapsed arithmetic: wall-clock read on the right. *)
let remaining expires_at = expires_at -. Unix.gettimeofday () (* FIRE *)

(* Unix.time reads the same clock. *)
let later () = Unix.time () +. 1. (* FIRE *)

(* Elapsed against a stored start. *)
let started = ref 0.
let duration () = Unix.gettimeofday () -. !started (* FIRE *)

(* Float.add / Float.sub are the same operators by identity. *)
let f_deadline timeout = Float.add (Unix.gettimeofday ()) timeout (* FIRE *)
let f_elapsed t0 = Float.sub (Unix.gettimeofday ()) t0 (* FIRE *)

(* Both operands read the clock: one finding, left-biased. *)
let gap () = Unix.gettimeofday () -. Unix.gettimeofday () (* FIRE *)

(* negative: the function stored as a clock seam — no arithmetic. *)
let now = Unix.gettimeofday

(* negative: a default-argument clock seam. *)
let wait ?(clock = Unix.gettimeofday) () = clock ()

(* negative: a timestamp payload, not duration arithmetic. *)
type tick = { at : float }

let tick () = { at = Unix.gettimeofday () }

(* negative: monotonic counter subtraction — different identities. *)
let count start = Int64.sub 1_000_000L start

(* negative: Sys.time is process CPU time, monotone. *)
let cpu started = Sys.time () -. started

(* negative: scaling for display uses an excluded operator. *)
let millis () = Unix.gettimeofday () *. 1000.

(* negative: the read flowing through a let is a recorded v1 false
   negative — the spec's documented boundary, pinned here. *)
let bound_read timeout =
  let now = Unix.gettimeofday () in
  now +. timeout

(* negative (adversarial): a same-spelled local module resolves to local
   declarations, never to Unix. *)
module Unix = struct
  let gettimeofday () = 0.
end

let local_elapsed t0 = Unix.gettimeofday () -. t0
