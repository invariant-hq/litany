(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type t = { loc : Location.t; message : string; fix : Fix.t option }

let v ?fix ~loc message = { loc; message; fix }
let loc f = f.loc
let message f = f.message
let fix f = f.fix

let equal_position (p : Lexing.position) (q : Lexing.position) =
  String.equal p.pos_fname q.pos_fname
  && p.pos_lnum = q.pos_lnum && p.pos_bol = q.pos_bol && p.pos_cnum = q.pos_cnum

let equal_location (l : Location.t) (m : Location.t) =
  equal_position l.loc_start m.loc_start
  && equal_position l.loc_end m.loc_end
  && Bool.equal l.loc_ghost m.loc_ghost

let equal f f' =
  equal_location f.loc f'.loc && String.equal f.message f'.message

(* (path, start offset, end offset, message) — the report's total order
   interleaves the paired rule name between start and end. *)
let compare f f' =
  let s = f.loc.Location.loc_start and s' = f'.loc.Location.loc_start in
  let c = String.compare s.pos_fname s'.pos_fname in
  if c <> 0 then c
  else
    let c = Int.compare s.pos_cnum s'.pos_cnum in
    if c <> 0 then c
    else
      let c =
        Int.compare f.loc.Location.loc_end.pos_cnum
          f'.loc.Location.loc_end.pos_cnum
      in
      if c <> 0 then c else String.compare f.message f'.message

let pp ppf f =
  let p = f.loc.Location.loc_start in
  Format.fprintf ppf "@[<h>%s:%d:%d: %s%s@]" p.pos_fname p.pos_lnum
    (p.pos_cnum - p.pos_bol) f.message
    (match f.fix with Some _ -> " (fix)" | None -> "")
