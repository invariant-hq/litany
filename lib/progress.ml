(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type t = {
  drawing : bool;
  mutable jobs_ : int;
  started : float;
  mutable label : string;
  mutable total : int;  (** [0]: an uncounted phase — label and clock only. *)
  mutable done_ : int;
  mutable last_draw : float;
  mutable on_screen : bool;
}

(* Redraws are capped: a tick per unit on a fast corpus would otherwise spend
   the run in write(2). A tenth of a second is under the eye's threshold for
   "stopped" and over the terminal's for wasted work. *)
let min_interval = 0.1

let v ~enabled ~jobs =
  let drawing =
    enabled
    && Option.is_none (Sys.getenv_opt "LITANY_NO_PROGRESS")
    && try Unix.isatty Unix.stderr with Unix.Unix_error _ -> false
  in
  {
    drawing;
    jobs_ = jobs;
    started = Unix.gettimeofday ();
    label = "";
    total = 0;
    done_ = 0;
    last_draw = 0.;
    on_screen = false;
  }

let drawing t = t.drawing

(* The terminal's width, so a narrow window scrolls nothing: the line is
   rewritten in place, and a line longer than the window wraps and leaves the
   overflow behind on every redraw. COLUMNS is the only width the stdlib can
   see; 80 is the honest fallback. *)
let width () =
  match Option.map int_of_string_opt (Sys.getenv_opt "COLUMNS") with
  | Some (Some n) when n > 20 -> n
  | Some (Some _) | Some None | None -> 80

let truncate s =
  let max = width () - 1 in
  if String.length s <= max then s else String.sub s 0 max

let elapsed t = Unix.gettimeofday () -. t.started

let line t =
  let secs = elapsed t in
  let prefix = if t.label = "" then "" else t.label ^ ": " in
  if t.total = 0 then Printf.sprintf "%s[%.1fs]" prefix secs
  else
    let left = t.total - t.done_ in
    let pct = t.done_ * 100 / t.total in
    let rate = if secs > 0. then float_of_int t.done_ /. secs else 0. in
    Printf.sprintf "%sDone: %d%% (%d/%d, %d left) (jobs: %d) | [%.1fs] [%.1f/s]"
      prefix pct t.done_ t.total left t.jobs_ secs rate

(* One write per redraw: carriage return, the line, erase-to-end-of-line —
   so a shorter line never leaves the tail of a longer one behind. *)
let draw t ~force =
  if t.drawing then begin
    let now = Unix.gettimeofday () in
    if force || now -. t.last_draw >= min_interval then begin
      t.last_draw <- now;
      t.on_screen <- true;
      output_string stderr ("\r" ^ truncate (line t) ^ "\027[K");
      flush stderr
    end
  end

let clear t =
  if t.drawing && t.on_screen then begin
    t.on_screen <- false;
    output_string stderr "\r\027[K";
    flush stderr
  end

let phase t label =
  t.label <- label;
  t.total <- 0;
  t.done_ <- 0;
  draw t ~force:true

let counting t ~label ~total =
  t.label <- label;
  t.total <- total;
  t.done_ <- 0;
  draw t ~force:true

let add t n =
  t.done_ <- t.done_ + n;
  draw t ~force:false

let tick t = add t 1
let jobs t n = t.jobs_ <- n
let refresh t = draw t ~force:false
