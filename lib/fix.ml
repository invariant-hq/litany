(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type applicability = Safe | Unsafe | Display

let applicability_to_string = function
  | Safe -> "safe"
  | Unsafe -> "unsafe"
  | Display -> "display"

type availability = Never | Sometimes | Always

let availability_to_string = function
  | Never -> "never"
  | Sometimes -> "sometimes"
  | Always -> "always"

type edit = { span : Span.t; text : string }

type t = {
  title : string;
  applicability : applicability;
  edits : edit list;  (** Sorted by [Span.compare] of their spans. *)
}

let v ?(applicability = Unsafe) ~title edits =
  if edits = [] then invalid_arg "Fix.v: no edits";
  let edits =
    List.stable_sort (fun e e' -> Span.compare e.span e'.span) edits
  in
  (* Pairwise conflict-freedom over the sorted list — the relation the
     applier's [plan] enforces: no overlap, and no insertion point strictly
     inside a replaced range. Every edit (empty spans included) is checked
     against the greatest stop seen so far; only non-empty spans advance
     it. Adjacent-pair checking is not enough — an empty span sorted
     between two overlapping neighbours would mask them. *)
  let max_stop = ref (-1) in
  List.iter
    (fun e ->
      if Span.start e.span < !max_stop then
        invalid_arg
          "Fix.v: conflicting edits (overlapping, or an insertion inside a \
           replaced range)";
      if not (Span.is_empty e.span) then
        max_stop := max !max_stop (Span.stop e.span))
    edits;
  { title; applicability; edits }

let safe_replace loc text ~title =
  {
    title;
    applicability = Safe;
    edits = [ { span = Span.of_location loc; text } ];
  }

let unsafe_replace loc text ~title =
  { (safe_replace loc text ~title) with applicability = Unsafe }

let safe_delete loc ~title = safe_replace loc "" ~title
let title f = f.title
let applicability f = f.applicability
let edits f = f.edits
let with_applicability applicability f = { f with applicability }

let pp ppf f =
  Format.fprintf ppf "@[<h>fix (%s) %S:"
    (applicability_to_string f.applicability)
    f.title;
  List.iter (fun e -> Format.fprintf ppf " %a" Span.pp e.span) f.edits;
  Format.fprintf ppf "@]"
