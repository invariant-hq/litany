(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type candidate = { rule : string; fix : Fix.t }

(* {1 Planning} *)

type plan = {
  selected : candidate list;
  conflicting : candidate list;
  excluded : candidate list;
}

(* The conflict relation — overlap, or an insertion point strictly inside
   the other's replaced range: [start < stop' && start' < stop] covers
   both, because an empty span [o;o) satisfies it against [s;t) exactly
   when [s < o < t], two empty spans never satisfy it, and for two
   non-empty spans it is [Span.overlaps]. The selected state is
   kept in two sets so each test is a bounded search instead of a rescan
   of everything selected (a full rescan is O(k²) — measured at 2.5 s for
   20k fixes). *)

module Ivl = Set.Make (struct
  (* Selected non-empty edit spans: pairwise disjoint by construction
     (the greedy loop only admits conflict-free candidates), so ordering
     by start alone is total and orders the stops with it. *)
  type t = int * int

  let compare (a, _) (b, _) = Int.compare a b
end)

module Pts = Set.Make (Int)

let edit_conflicts ivls pts (e : Fix.edit) =
  let s = Span.start e.span and t = Span.stop e.span in
  if s = t then
    (* An insertion at [s] conflicts iff strictly inside a selected
       replaced range — the rightmost range starting before [s] is the
       only disjoint-range candidate that can reach past it. *)
    match Ivl.find_last_opt (fun (s', _) -> s' < s) ivls with
    | Some (_, t') -> t' > s
    | None -> false
  else
    (* Overlap with the rightmost selected range starting before [t]
       (disjointness: any earlier range stops even earlier), or a
       selected insertion point strictly inside [s;t). *)
    (match Ivl.find_last_opt (fun (s', _) -> s' < t) ivls with
      | Some (_, t') -> t' > s
      | None -> false)
    ||
    match Pts.find_first_opt (fun o -> o > s) pts with
    | Some o -> o < t
    | None -> false

let record_edit (ivls, pts) (e : Fix.edit) =
  let s = Span.start e.span and t = Span.stop e.span in
  if s = t then (ivls, Pts.add s pts) else (Ivl.add (s, t) ivls, pts)

(* A fix's sort span is its first edit's — edits are sorted in the fix, so
   [List.hd] is the least, and a fix always has one. *)
let first_span c = (List.hd (Fix.edits c.fix)).Fix.span

let compare_candidates c c' =
  match Span.compare (first_span c) (first_span c') with
  | 0 -> String.compare c.rule c'.rule
  | n -> n

let plan ?(unsafe = false) cands =
  let wanted c =
    match Fix.applicability c.fix with
    | Fix.Safe -> true
    | Fix.Unsafe -> unsafe
    | Fix.Display -> false
  in
  let candidates, excluded = List.partition wanted cands in
  let candidates = List.stable_sort compare_candidates candidates in
  (* Greedy in (span, rule) order: the first fix at a spot wins, later
     conflicting ones lose — the drop is deterministic, never
     order-of-arrival. *)
  let selected, conflicting, _, _ =
    List.fold_left
      (fun (sel, con, ivls, pts) c ->
        let edits = Fix.edits c.fix in
        if List.exists (edit_conflicts ivls pts) edits then
          (sel, c :: con, ivls, pts)
        else
          let ivls, pts = List.fold_left record_edit (ivls, pts) edits in
          (c :: sel, con, ivls, pts))
      ([], [], Ivl.empty, Pts.empty)
      candidates
  in
  { selected = List.rev selected; conflicting = List.rev conflicting; excluded }

let selected p = p.selected
let conflicting p = p.conflicting
let excluded p = p.excluded

(* {1 Patching} *)

(* One forward walk over the stably-sorted edits with a cursor and a
   buffer. The single visible invariant carries everything: the cursor
   never moves backward. Conflict detection {e is} the cursor check
   ([start < pos] means the edit reaches into bytes an earlier edit
   already consumed — overlap and insertion-inside alike), same-point
   insertions land in list order because the stable sort left them there,
   and copying is O(len + inserted) instead of a whole-string copy per
   edit (measured at 3.5 s for 20k edits). *)
let patch s edits =
  let len = String.length s in
  let edits =
    List.stable_sort
      (fun (e : Fix.edit) (e' : Fix.edit) -> Span.compare e.span e'.span)
      edits
  in
  let b = Buffer.create (len + 64) in
  let pos = ref 0 in
  List.iter
    (fun (e : Fix.edit) ->
      let start = Span.start e.span and stop = Span.stop e.span in
      if stop > len then
        invalid_arg
          (Printf.sprintf "Apply.patch: edit %s exceeds length %d"
             (Format.asprintf "%a" Span.pp e.span)
             len);
      if start < !pos then invalid_arg "Apply.patch: conflict";
      Buffer.add_substring b s !pos (start - !pos);
      Buffer.add_string b e.text;
      pos := stop)
    edits;
  Buffer.add_substring b s !pos (len - !pos);
  Buffer.contents b

(* {1 Applying} *)

type outcome =
  | Applied
  | Nothing_to_apply
  | Stale
  | Fixer_bug
  | Unverifiable
  | Io_error of string

let parses bytes =
  let lexbuf = Lexing.from_string bytes in
  match Parse.implementation lexbuf with
  | _ -> true
  | exception (Syntaxerr.Error _ | Lexer.Error _) -> false

(* The never-write-unverified-bytes discipline, pure and in one place —
   the disk mode and the proposal mode must both go through it: plan,
   patch, reparse-verify. The original's parse gates
   everything — the applier never verifies what it cannot reparse, so an
   unparsable original is [`Unverifiable] before any fix is blamed. *)
let correct ?unsafe bytes cands =
  if not (parses bytes) then Error `Unverifiable
  else
    let p = plan ?unsafe cands in
    let edits = List.concat_map (fun c -> Fix.edits c.fix) p.selected in
    match patch bytes edits with
    | exception Invalid_argument _ ->
        Error (`Fixer_bug "an edit was out of bounds")
    | fixed ->
        (* A selected fix whose output equals its input is a fixer
           bug: written unconditionally it would re-produce the
           same finding on every pass, so the convergence loop could never
           terminate honestly. An empty selection producing [bytes]
           unchanged is the ordinary nothing-to-correct answer, not a
           bug. Checked before the reparse — equal bytes parse iff the
           original did. *)
        if p.selected <> [] && String.equal fixed bytes then
          Error
            (`Fixer_bug
               "the corrected result equals the input — the fixes change \
                nothing")
        else if parses fixed then Ok fixed
        else Error (`Fixer_bug "the corrected result does not parse")

(* Atomic publication is [Write.atomic] — the one write-then-rename
   implementation, never a local copy — fsynced here: a power loss around
   the rename must not leave the journaled name pointing at unwritten
   blocks, because the user's source is unrecoverable, unlike a cache
   entry. The applier keeps its two policies: the target is resolved
   through symlinks first ([Unix.realpath]), so a vendored-by-symlink
   source is written through rather than replaced by a regular file, and
   the write preserves the target's permission bits. *)
let write_atomic ~path bytes =
  match Unix.realpath path with
  | exception Unix.Unix_error (err, _, _) -> Error (Unix.error_message err)
  | path ->
      let mode =
        match (Unix.stat path).Unix.st_perm with
        | perm -> perm
        | exception Unix.Unix_error _ -> 0o600
      in
      Write.atomic ~fsync:true ~mode ~path bytes

let file ?unsafe ~path ~baseline cands =
  let p = plan ?unsafe cands in
  let outcome =
    match p.selected with
    | [] -> Nothing_to_apply
    | _ -> (
        match In_channel.with_open_bin path In_channel.input_all with
        | exception Sys_error msg -> Io_error msg
        | bytes -> (
            if
              (* Either-digest admission, one home: the write baseline
               accepts exactly what the loader's witness accepted. *)
              not (Digest0.matches ~recorded:baseline bytes)
            then Stale
            else
              (* [correct] re-plans internally (planning is pure and
                 per-file cheap); the plan above is the partition the
                 outcomes report against — the two agree by determinism. *)
              match correct ?unsafe bytes cands with
              | Error `Unverifiable ->
                  (* An unparsable original is refused
                     even when the patch happens to produce parsing
                     bytes — a fix that "repairs" a cppo source into
                     OCaml rewrote bytes it does not own. *)
                  Unverifiable
              | Error (`Fixer_bug _) ->
                  (* Out-of-bounds or non-parsing result against
                     digest-verified bytes: the fix was not computed
                     against the editable source — a rule bug. *)
                  Fixer_bug
              | Ok fixed -> (
                  match write_atomic ~path fixed with
                  | Ok () -> Applied
                  | Error msg -> Io_error msg)))
  in
  (p, outcome)
