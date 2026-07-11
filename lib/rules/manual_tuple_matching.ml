(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-tuple-matching" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"single irrefutable tuple case that could be a let binding"
    ~doc:
      {|A `match` with exactly one case whose pattern is an irrefutable tuple
does no branching: a single guard-less irrefutable case evaluates the
scrutinee, binds, and continues — which is `let`'s definition, and `let`
says so.

    (* bad *)  match p with (a, b) -> a + b
    (* good *) let (a, b) = p in a + b

Fires on a `match` with exactly one guard-less computation case whose
pattern is an unlabeled tuple of irrefutable components — variables,
wildcards, and nested unlabeled tuples of the same. Refutable
components (constants, constructors, records) refuse conservatively:
there the `let` form merely relocates the partiality, which is warning
8's business in both spellings. Guarded cases, multi-case matches,
`exception` arms, effect-handler matches, and the `function (a, b) ->`
spelling (`needless-fun-match`'s territory) do not fire. Alias
components (`(x, _) as whole`) and constraint components
(`((a : int), b)`) refuse conservatively in this version — recorded
false negatives: the vocabulary has no view into an alias's
sub-pattern yet. The fix rewrites `match ... with pat -> body` to
`let pat = scrutinee in body` when the unit is not preprocessed and
the keyword gaps normalize to exactly `match`, `with` (or `with |`),
and `->` — a comment in any gap refuses the fix, never the finding.
The pattern is spliced verbatim; the scrutinee through `Unit.splice`.
Purely stylistic; some houses prefer `match` even here for uniformity
with sibling arms — Style/off is the posture. `fun x -> match x with
(a, b) -> e` co-fires with `needless-fun-match` at distinct anchors
with converging remedies — both claims true; apply either fix and the
other finding clears.|}
    ()

let message = "this match has one irrefutable case; bind it with let"

(* A [match] with exactly one guard-less computation case whose value
   pattern is an unlabeled tuple. The [match_] view refuses
   effect-handler matches by contract; the single-case shape excludes
   [exception]-arm forms, whose rewrite would change semantics. *)
let single_tuple_case =
  Pat.(
    match_ (as__ drop)
      (case (pvalue (as__ (ptuple __))) none (as__ drop) ^:: nil))

(* Irrefutability, proved conservatively: variables, wildcards, and
   nested unlabeled tuples of the same. Aliases and constraint-carrying
   components ([pat_extra]) refuse — recorded false negatives, not
   judgments. *)
let rec irrefutable u (p : Typedtree.pattern) =
  match p.Typedtree.pat_extra with
  | _ :: _ -> false
  | [] -> (
      match Pat.run Pat.pany u p () with
      | Some () -> true
      | None -> (
          match Pat.run Pat.pvar u p (fun _ -> ()) with
          | Some () -> true
          | None -> (
              match Pat.run Pat.(ptuple __) u p Fun.id with
              | Some components -> List.for_all (irrefutable u) components
              | None -> false)))

let tokens s =
  List.filter
    (fun t -> t <> "")
    (String.split_on_char ' '
       (String.map (function '\t' | '\n' | '\r' -> ' ' | c -> c) s))

let span_of start stop =
  if start < 0 || stop < start then None else Some (Span.v ~start ~stop)

let gap_is u expected start stop =
  match span_of start stop with
  | None -> false
  | Some sp -> (
      match Source.slice (Unit.source u) sp with
      | Some s -> List.mem (tokens s) expected
      | None -> false)

(* The grammar-gated fix: one edit replacing everything from the
   [match] keyword to the case body with [let <pat> = <scrutinee> in].
   The three keyword gaps must normalize to exactly [match], [with]
   (or [with |]), and [->]; a comment anywhere there refuses the fix,
   never the finding. *)
let bind_with_let u (e : Typedtree.expression) scrut (pat : Typedtree.pattern)
    (rhs : Typedtree.expression) =
  if Unit.preprocessed u then None
  else
    let cn (p : Lexing.position) = p.Lexing.pos_cnum in
    let m0 = cn e.exp_loc.Location.loc_start
    and s0 = cn scrut.Typedtree.exp_loc.Location.loc_start
    and s1 = cn scrut.Typedtree.exp_loc.Location.loc_end
    and p0 = cn pat.pat_loc.Location.loc_start
    and p1 = cn pat.pat_loc.Location.loc_end
    and r0 = cn rhs.exp_loc.Location.loc_start in
    if
      gap_is u [ [ "match" ] ] m0 s0
      && gap_is u [ [ "with" ]; [ "with"; "|" ] ] s1 p0
      && gap_is u [ [ "->" ] ] p1 r0
    then
      let src = Unit.source u in
      match (span_of p0 p1, Unit.splice u scrut, span_of m0 r0) with
      | Some pat_span, Some scrut_atom, Some whole -> (
          match (Source.slice src pat_span, Source.location src whole) with
          | Some pat_text, Some loc ->
              Some
                (Fix.safe_replace loc
                   ("let " ^ pat_text ^ " = " ^ scrut_atom ^ " in ")
                   ~title:"bind with let")
          | _, _ -> None)
      | _, _, _ -> None
    else None

let rule =
  Rule.expr meta @@ fun u e ->
  match
    Pat.run single_tuple_case u e (fun scrut pat components rhs ->
        (scrut, pat, components, rhs))
  with
  | Some (scrut, pat, components, rhs)
    when List.for_all (irrefutable u) components ->
      let fix = bind_with_let u e scrut pat rhs in
      [ Finding.v ?fix ~loc:e.exp_loc message ]
  | Some _ | None -> []
