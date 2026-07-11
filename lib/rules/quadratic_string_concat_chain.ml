(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"quadratic-string-concat-chain" ~group:Rule.Pedantic
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"a chain of three or more (^) segments"
    ~doc:
      {|`(^)` associates to the right, so `a ^ b ^ c` builds `b ^ c` and then
copies it whole into `a ^ (b ^ c)`: every added segment recopies the ones
after it.

    (* bad *)  dir ^ "/" ^ file
    (* good *) String.concat "" [ dir; "/"; file ]

Fires when `Stdlib.(^)`'s right operand is itself a `Stdlib.(^)`
application — three or more segments in one chain. A two-segment
concatenation, a rebound `(^)`, and a left-parenthesized `(a ^ b) ^ c`
(the right operand is simple) deliberately do not fire. A chain of n
segments holds n − 2 matching nodes; the rule reports one finding per
maximal chain — at the innermost matching node, whose rightmost operand
is simple — so a nine-segment chain is one finding, not seven. Two
copies of three short segments rarely
matter, hence pedantic and off; no fix, because choosing the separator
layout is editorial.

Option `(max-segments <n>)` (n ≥ 2, default 2) raises the tolerated
chain length: only chains of more than n segments fire, anchored at the
node where the chain first exceeds n. This makes the recorded
narrowing — a higher segment threshold — configurable:

    (rule quadratic-string-concat-chain
     (max-segments 4))

Pedantic on field evidence, re-checked after containment landed: with
one finding per maximal chain the
multi-report half of the demote reasoning is retired, but every real
sighting on both corpora was still a 3–4 segment chain in an error
path or paren-wrap — sizes where "quadratic" overclaims and no
maintainer rewrites. The rule stays Pedantic and off; the recorded
narrowing if it is ever to leave is the segment threshold above (≥ 4–5)
or scoping to loops and folds, and the name question rides with it.|}
    ()

let concat_operator = Pat.ident "Stdlib.(^)"

(* [right] captures a [Stdlib.(^)] application's right operand — the step of
   the right-spine walk [segments] performs. *)
let right = Pat.(apply concat_operator (drop ^:: as__ drop ^:: nil))

(* [segments u e] is the number of (^) segments along [e]'s right spine —
   [1] when [e] is not a concatenation, else one per left operand plus the
   spine's tail. A maximal chain of S segments gives its interior nodes the
   downward counts 3..S, strictly increasing towards the root. *)
let rec segments u e =
  match Pat.run right u e Fun.id with
  | Some rest -> 1 + segments u rest
  | None -> 1

(* One finding per maximal chain, threshold-aware: exactly one node of a
   chain of S segments has downward count [max_segments + 1] (counts
   increase strictly towards the root), and such a node exists iff
   S > max_segments. At the default threshold 2 this is precisely the
   pre-option behavior: the innermost matching node — the one whose
   rightmost operand is simple — and only chains of ≥ 3 segments fire.
   Parents cannot be told apart from here, so the count, not the parent,
   decides. *)
let check ~max_segments u (e : Typedtree.expression) =
  if segments u e = max_segments + 1 then
    [
      Finding.v ~loc:e.exp_loc
        "chained (^) recopies later segments; use String.concat";
    ]
  else []

(* The option schema: a closed [(max-segments <n>)] payload, n ≥ 2. The
   reconfigured rule re-attaches the schema, so configuring twice works. *)
let rec with_max max_segments =
  Rule.with_options schema (Rule.expr meta (check ~max_segments))

and schema payload =
  let err at fmt =
    Printf.ksprintf (fun m -> Error (Rule.Options.v ~at m)) fmt
  in
  match payload with
  | [ ({ Rule.Sexp.desc = List [ key; value ]; _ } as form) ] -> (
      match key.Rule.Sexp.desc with
      | Rule.Sexp.Atom "max-segments" -> (
          match value.Rule.Sexp.desc with
          | Rule.Sexp.Atom v -> (
              match int_of_string_opt v with
              | Some n when n >= 2 -> Ok (with_max n)
              | Some _ ->
                  err value "option \"max-segments\" wants an integer >= 2"
              | None ->
                  err value "option \"max-segments\" wants an integer, not %S" v
              )
          | Rule.Sexp.List _ ->
              err value "option \"max-segments\" wants one integer atom")
      | Rule.Sexp.Atom other ->
          err key "unknown option %S%s" other
            (match Rule.suggest ~candidates:[ "max-segments" ] other with
            | Some c -> Printf.sprintf " (did you mean %S?)" c
            | None -> "")
      | Rule.Sexp.List _ -> err form "expected (max-segments <n>)")
  | [ at ] -> err at "expected (max-segments <n>)"
  | _ :: at :: _ -> err at "duplicate option form; one (max-segments <n>) only"
  | [] -> Ok (with_max max_segments_default)

and max_segments_default = 2

let rule = with_max max_segments_default
