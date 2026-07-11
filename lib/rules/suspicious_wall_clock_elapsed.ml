(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-wall-clock-elapsed" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"duration computed from wall-clock reads"
    ~doc:
      {|`Unix.gettimeofday` and `Unix.time` read the wall clock: NTP steps,
manual clock changes, and suspend/resume make it jump both ways.
Arithmetic that turns wall-clock reads into a duration — `now +.
timeout` deadlines, `now -. started` elapsed — silently produces
negative or wildly inflated durations under a clock step: watchdogs
kill healthy children, retry loops spin or hang. A monotonic counter
(`Mtime_clock`, the project's own clock module) is the remedy, and
choosing one is a dependency decision — no fix.

    (* bad *)  let deadline = Unix.gettimeofday () +. timeout in …
    (* good *) let deadline = Mtime.add_span (Mtime_clock.now ()) span in …

Fires on float `+.`/`-.` (and `Float.add`/`Float.sub`) applications
where either argument is directly a `Unix.gettimeofday ()` or
`Unix.time ()` call, anchored at the arithmetic expression. Storing the
function as a clock seam, passing a timestamp as data, scaling with
`*.`, monotonic counter subtraction, and `Sys.time` (process CPU time,
monotone) deliberately do not fire. A wall-clock read that flows
through a `let` binding before the arithmetic is a recorded false
negative.|}
    ()

let message =
  "elapsed-time arithmetic on a wall-clock read; use a monotonic clock"

let ops =
  Pat.(
    idents
      [ "Stdlib.(+.)"; "Stdlib.(-.)"; "Stdlib.Float.add"; "Stdlib.Float.sub" ])

let wall_read =
  Pat.(apply (idents [ "Unix.gettimeofday"; "Unix.time" ]) (drop ^:: nil))

(* Either operand is directly a wall-clock read; left-biased alternation
   yields one finding when both are. *)
let shape =
  Pat.(
    apply ops (wall_read ^:: drop ^:: nil)
    ||| apply ops (drop ^:: wall_read ^:: nil))

let rule =
  Rule.expr meta @@ fun u e ->
  (* Constructor-head gate: only applications can match — the walk
     visits every node, so the miss path must stay cheap. *)
  match e.exp_desc with
  | Typedtree.Texp_apply _ -> (
      match Pat.run shape u e () with
      | Some () -> [ Finding.v ~loc:e.exp_loc message ]
      | None -> [])
  | _ -> []
