(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-eta-lambda" ~group:Rule.Style
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Sometimes
    ~summary:"anonymous function that only forwards its parameters"
    ~doc:
      {|An anonymous function whose body only forwards its parameters, in
order, to a single identifier is that identifier wrapped in a closure:
`fun x -> parse x` is `parse`, and the wrapper adds an allocation and a
layer of reading without adding meaning.

    (* bad *)  Result.map (fun x -> parse x) r
    (* good *) Result.map parse r

Fires on an anonymous function expression (`fun`, not a `let`-bound
definition) in any position — an argument, the callee of an immediate
application, a list element, a pipeline stage — whose parameters are all
unlabeled plain variables and whose body is one application of an
identifier callee to exactly those parameters, in order, all unlabeled,
proved by declaration identity (`Ident.same` positionally, which also
retires the duplicate-name hazard: in `fun x x -> g x x` both arguments
carry the second `x` and position one fails). The gate is what makes
the reduction exact, and each clause is a deliberate non-firing: the
callee must be a plain identifier or module path (`(get ()) x` forces
`get ()` once per call, `f` once at the reduction; a staged `(add 1) x`
likewise), not one of the lambda's own parameters (`fun f -> f x`), and
not spelled as an operator (`fun x y -> x + y` is the section `( + )`, a
different edit — and the parser respells unary minus, so an operator's
slice is not its name); the application must apply all and only the
parameters as unlabeled positional arguments (a partial forward
`fun x y -> f x`, an extra argument `f x 0`, a repeated one `f x x`, a
swapped order, a labeled or optional argument — labels change arity
semantics); the callee's arrow spine must be unlabeled over the
forwarded prefix (with `g : ?d:int -> int -> int`, `fun x -> g x` has
type `int -> int` while `g` keeps the optional — the probe-pinned
erasure gate eta-reducible-forwarding records); and the lambda, its
parameters, its callee, its body, and its arguments carry no type
annotation, coercion, newtype, or attribute the reduction would drop —
`fun env -> f (env :> t)` forwards a coerced `env`, not `env`, the
corpus-recorded false positive of this rule's predecessor. A body that
is itself a function (`fun x -> fun y -> f x y`, `fun x -> function
...`) is not a forward. The callee's own arity is irrelevant:
`fun x -> f x` with a binary `f` is `f` at the same type.

Two further non-firings keep the fix legal. A lambda that is the whole
right-hand side of a `let` binding (`let f = fun x -> g x`, and the
`let f x = g x` sugar the parser desugars to it) is
eta-reducible-forwarding's — that rule's doc records why reducing a
named definition is a judgment, not a mechanical edit (closure identity,
the type surface a wrapper pins); this rule never fires there. And a
lambda in tail position of a `let rec` right-hand side whose callee is
one of the recursively bound names (`let rec f = let g = 1 in fun x -> f
x`) does not fire: the reduced `let rec f = let g = 1 in f` is rejected
by the compiler's recursive-definition check, while under an intervening
`fun` (`let rec go = fun l -> List.map (fun x -> go x) l`) the use is
already delayed and the reduction is legal.

Style, off by default: an eta-expanded lambda is sometimes deliberate —
an `[@inline]` site, a closure the author wants distinct from the callee,
or a forward reference to a not-yet-defined recursive binding. The fix
replaces the lambda with the callee's own spelling, restoring the
author's parentheses when the lambda's location included them
(`Result.map (fun x -> parse x) r` becomes `Result.map parse r`), and is
Safe: under the gate the two expressions are the same value at the same
type. The one observable difference is closure identity — the wrapper
is a fresh allocation, the callee is the one it already was, so `==` on
them differs — which is not a soundness concern: a program observing it
compares functions, itself flagged — physically by
suspicious-physical-equality, structurally (where it raises) by
invalid-function-comparison. Verified OCaml 5.5.0 arm64 non-flambda:
`fun x -> succ x` and `succ` compile to the same cmm up to symbol names
(the compiler eta-expands the primitive itself), so the rationale is
style and identity, never speed.|}
    ()

(* A function whose whole body is one application, all arguments
   unlabeled and evaluated: parameters, body, callee expression, callee
   path, arguments. *)
let forwarding = Pat.(fun_body __ (as__ (apply (as__ var) __)))

(* An unlabeled, non-optional parameter ([param] refuses the others),
   its pattern captured for the variable and annotation tests. *)
let param_pat = Pat.(param __)

(* [params_idents u ps] is every parameter's ident when each is an
   unlabeled, unannotated plain variable introducing no newtype. *)
let params_idents u (ps : Typedtree.function_param list) =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | (p : Typedtree.function_param) :: rest -> (
        match (p.fp_newtypes, Pat.run param_pat u p Fun.id) with
        | [], Some ({ Typedtree.pat_extra = []; _ } as pat) -> (
            match Pat.run Pat.pvar u pat Fun.id with
            | Some id -> go (id :: acc) rest
            | None -> None)
        | [], Some _ | [], None | _ :: _, _ -> None)
  in
  go [] ps

(* Plain: no annotation, coercion, newtype, or attribute on the node. *)
let plain (e : Typedtree.expression) = e.exp_extra = [] && e.exp_attributes = []

(* Positional identity: argument [i] is exactly parameter [i]'s ident,
   bare — a coerced or annotated argument ([f (env :> t)]) forwards a
   different value than the parameter. *)
let forwards u pids args =
  List.length pids = List.length args
  && List.for_all2
       (fun pid (arg : Typedtree.expression) ->
         plain arg
         &&
         match Pat.run Pat.var u arg Fun.id with
         | Some (Path.Pident aid) -> Ident.same pid aid
         | Some _ | None -> false)
       pids args

(* The erasure gate: the callee's first [n] arrows must all be unlabeled.
   A type variable in the spine refuses. *)
let rec unlabeled_prefix n ty =
  n = 0
  ||
  match Types.get_desc ty with
  | Types.Tarrow (Asttypes.Nolabel, _, ret, _) -> unlabeled_prefix (n - 1) ret
  | _ -> false

(* A path of identifiers and dots only — no functor application, whose
   evaluation the reduction would move. *)
let rec plain_path = function
  | Path.Pident _ -> true
  | Path.Pdot (p, _) -> plain_path p
  | _ -> false

(* An identifier path as spelled — letters, digits, [_], ['] and [.] —
   never an operator: the replacement is the callee's own name. *)
let identifier_spelling s =
  s <> ""
  && (match s.[0] with 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false)
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' | '.' -> true
         | _ -> false)
       s

(* [spelling callee] is the callee identifier as the author wrote it, from
   its longident — the resolved path's own name may be a different
   spelling ([Stdlib.List.map] for [List.map]). Called only after
   [plain_path], so the longident carries no functor application. *)
let spelling (callee : Typedtree.expression) =
  match callee.exp_desc with
  | Typedtree.Texp_ident (_, lid, _) ->
      Some (String.concat "." (Longident.flatten lid.txt))
  | _ -> None

(* [binding_context u target] is [(bound, recs)]: [bound] when [target] is
   the whole right-hand side of a value binding, and [recs] the
   recursively bound idents whose right-hand side reaches [target] with
   no intervening function — the parent context the dispatch callback
   does not carry, recovered by a [Tast_iterator] walk of the same tree
   the engine dispatches ([Unit.implementation]), so physical identity
   decides. Pruned to expressions whose span encloses [target]'s — a
   ghost span cannot prune — and run only at the rare forwarding
   lambdas. *)
let binding_context u (target : Typedtree.expression) =
  let bound = ref false and recs = ref [] and found = ref false in
  let open_recs = ref [] in
  let encloses (outer : Location.t) =
    outer.loc_ghost
    || outer.loc_start.pos_cnum <= target.exp_loc.loc_start.pos_cnum
       && target.exp_loc.loc_end.pos_cnum <= outer.loc_end.pos_cnum
  in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.value_bindings =
        (fun sub ((flag, vbs) as group) ->
          if not !found then begin
            let saved = !open_recs in
            (match flag with
            | Asttypes.Recursive ->
                open_recs :=
                  List.filter_map
                    (fun (vb : Typedtree.value_binding) ->
                      Pat.run Pat.pvar u vb.vb_pat Fun.id)
                    vbs
                  @ saved
            | Asttypes.Nonrecursive -> ());
            List.iter
              (fun (vb : Typedtree.value_binding) ->
                if vb.vb_expr == target then bound := true)
              vbs;
            default.value_bindings sub group;
            open_recs := saved
          end);
      expr =
        (fun sub (ex : Typedtree.expression) ->
          if (not !found) && encloses ex.exp_loc then
            if ex == target then begin
              found := true;
              recs := !open_recs
            end
            else
              match ex.exp_desc with
              | Typedtree.Texp_function _ ->
                  (* Delayed: a use below a function is legal in a
                     recursive right-hand side, so the open set resets. *)
                  let saved = !open_recs in
                  open_recs := [];
                  default.expr sub ex;
                  open_recs := saved
              | _ -> default.expr sub ex);
    }
  in
  iterator.structure iterator (Unit.implementation u);
  (!bound, !recs)

let rule =
  Rule.expr meta @@ fun u e ->
  match
    Pat.run forwarding u e (fun ps body callee path args ->
        (ps, body, callee, path, args))
  with
  | None -> []
  | Some (ps, body, callee, path, args) -> (
      if not (plain e && plain body && plain callee && plain_path path) then []
      else
        match (params_idents u ps, spelling callee) with
        | Some pids, Some name
          when pids <> [] && forwards u pids args && identifier_spelling name
               && (match path with
                 | Path.Pident c -> not (List.exists (Ident.same c) pids)
                 | _ -> true)
               && unlabeled_prefix (List.length pids) callee.Typedtree.exp_type
          -> (
            match binding_context u e with
            | true, _ -> []
            | false, recs
              when match path with
                   | Path.Pident c -> List.exists (Ident.same c) recs
                   | _ -> false ->
                []
            | false, _ ->
                let fix =
                  match Unit.splice u callee with
                  | Some src when identifier_spelling src ->
                      Some
                        (Fix.safe_replace e.exp_loc (Unit.delimited u e src)
                           ~title:("eta-reduce to " ^ src))
                  | Some _ | None -> None
                in
                [
                  Finding.v ?fix ~loc:e.exp_loc
                    ("this function only forwards its parameters; it is " ^ name);
                ])
        | (Some _ | None), _ -> [])
