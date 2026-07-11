(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type t = { start : int; stop : int }

let v ~start ~stop =
  if start < 0 then
    invalid_arg (Printf.sprintf "Span.v: negative start %d" start);
  if stop < start then
    invalid_arg (Printf.sprintf "Span.v: stop %d precedes start %d" stop start);
  { start; stop }

let start s = s.start
let stop s = s.stop
let length s = s.stop - s.start
let is_empty s = s.start = s.stop
let contains s i = s.start <= i && i < s.stop
let includes s sub = s.start <= sub.start && sub.stop <= s.stop
let overlaps s s' = max s.start s'.start < min s.stop s'.stop

let of_location (loc : Location.t) =
  let start = loc.loc_start.pos_cnum and stop = loc.loc_end.pos_cnum in
  if start < 0 || stop < 0 then
    invalid_arg
      (Printf.sprintf "Span.of_location: negative offset [%d;%d)" start stop);
  v ~start ~stop

let equal s s' = s.start = s'.start && s.stop = s'.stop

let compare s s' =
  match Int.compare s.start s'.start with
  | 0 -> Int.compare s.stop s'.stop
  | c -> c

let pp ppf s = Format.fprintf ppf "[%d;%d)" s.start s.stop
