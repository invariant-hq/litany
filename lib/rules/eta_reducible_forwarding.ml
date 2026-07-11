(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"eta-reducible-forwarding" ~group:Rule.Style
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"binding that only forwards its arguments"
    ~doc:
      {|A binding whose body only forwards its parameters, in order, to a
single identifier is that identifier with extra ceremony: an allocation
per closure, and a name that promises logic it does not have.

    (* bad *)  let f x y = g x y
    (* good *) let f = g

Fires once per variable binding of an n-parameter function — every
parameter unlabeled and a plain variable — whose body is a single
application of an identifier callee to exactly those parameters, in
order, all unlabeled, proved by declaration identity (`Ident.same`
positionally, which also retires the duplicate-name hazard: in
`fun x x -> g x x` both arguments carry the second `x` and position
one fails). It fires only where the reduction is type-preserving and
legal: the callee must not be the binding itself (`let rec f = f` is
rejected by the compiler) nor one of the parameters, and the callee's
arrow spine must be unlabeled over the forwarded prefix — the
probe-pinned gate: with `let g ?(d = 0) x = x + d`, the wrapper
`let f x = g x` has type `int -> int` while `g` keeps
`?d:int -> int -> int`, so reducing changes the type and the call-site
surface. A type variable in the spine, or fewer visible arrows than
parameters, refuses. Inline eta-lambdas passed to higher-order
functions are a separate rule candidate with their own false-positive
profile, not this rule; PPX-materialized forwarders never fire (the
engine-wide emit contract). The value restriction is not a hazard: the
callee is an identifier — a syntactic value — so `let f = g`
generalizes exactly as the wrapper does; recorded here so reviewers
need not re-derive it.
Style, off by default: the claim is true, and the remedy is sometimes
worse than the disease — deliberate wrappers name things, pin
monomorphic types without an annotation, keep closure identity distinct,
or hold an indirection the author expects to swap. All are true
positives by the rule's claim and all defensible; the rule is for
codebases that want forwarding wrappers called out. No fix, ever: eta
reduction can change a binding's inferred type surface and its closure
identity — never mechanical.|}
    ()

(* An n-parameter function whose whole body is one application, all
   arguments unlabeled and evaluated: parameters, callee expression,
   callee path, arguments. *)
let forwarding = Pat.(fun_body __ (apply (as__ var) __))

(* Each parameter must be unlabeled ([param] refuses labeled and
   optional ones) and a plain variable. *)
let param_var = Pat.(param pvar)

let params_idents u ps =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | p :: rest -> (
        match Pat.run param_var u p Fun.id with
        | Some id -> go (id :: acc) rest
        | None -> None)
  in
  go [] ps

(* Positional identity: argument [i] is exactly parameter [i]'s ident. *)
let forwards u pids args =
  List.length pids = List.length args
  && List.for_all2
       (fun pid arg ->
         match Pat.run Pat.var u arg Fun.id with
         | Some (Path.Pident aid) -> Ident.same pid aid
         | Some _ | None -> false)
       pids args

(* The probe-pinned erasure gate: the callee's first [n] arrows must all
   be unlabeled. A type variable in the spine refuses. *)
let rec unlabeled_prefix n ty =
  n = 0
  ||
  match Types.get_desc ty with
  | Types.Tarrow (Asttypes.Nolabel, _, ret, _) -> unlabeled_prefix (n - 1) ret
  | _ -> false

let rule =
  Rule.binding meta @@ fun u vb ->
  match Pat.run Pat.pvar u vb.Typedtree.vb_pat Fun.id with
  | None -> []
  | Some self -> (
      match
        Pat.run forwarding u vb.Typedtree.vb_expr (fun ps callee path args ->
            (ps, callee, path, args))
      with
      | None -> []
      | Some (ps, callee, path, args) -> (
          match params_idents u ps with
          | Some pids
            when pids <> [] && forwards u pids args
                 && (match path with
                   | Path.Pident c ->
                       (not (Ident.same c self))
                       && not (List.exists (Ident.same c) pids)
                   | _ -> true)
                 && unlabeled_prefix (List.length pids)
                      callee.Typedtree.exp_type ->
              [
                Finding.v ~loc:vb.Typedtree.vb_pat.pat_loc
                  (Printf.sprintf
                     "this binding only forwards its arguments; it is \
                      eta-reducible to %s"
                     (Path.name path));
              ]
          | Some _ | None -> []))
