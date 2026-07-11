(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-result-bind" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"two-case result match that re-implements Result.bind"
    ~doc:
      {|`match r with Ok x -> E | Error e -> Error e`, with `E` itself
result-typed and the error returned unchanged, is
`Result.bind r (fun x -> E)`: same single evaluation of `r`, same `E`
on `Ok`, same error propagation. It is the single most recurrent manual
shape in the corpora — including per-directory hand-defined
`let ( let* ) = <the bind match>` operators, whose definitions fire and
should: `let ( let* ) = Result.bind` is the tighter definition.

    (* bad *)  match route t s with Error e -> Error e | Ok d -> submit d
    (* good *) Result.bind (route t s) (fun d -> submit d)

Fires on the guard-less two-case match — or bare `function` — whose
`Ok` case binds a variable with a right-hand side that is not an
`Ok _` construction (that shape is manual-result-map's — exact
partition, no co-fire), and whose `Error` case is the payload rebuild
`Error e -> Error e`, in either case order. The rebuild's payload types
must agree on both sides: a coerced rebuild
(`Error (e :> wider)`) widens where `Result.bind` would not typecheck
and is refused. The alias spelling `Error _ as e -> e` is a recorded
false negative until a pattern-alias view lands. Guards, exception
arms, deeper payload patterns, transformed or dropped errors, `Error`
right-hand sides that are not `Error` constructions, and user variants
spelling `Ok`/`Error` deliberately do not fire. One definition site is
exempt — the self-definition gate: a module named `Result` defining the
like-named `bind` from this match (stdppx's shape; its `Result.bind`
is this match) must not be told to use `Result.bind`. The gate accepts
the match that is the eventual function body of a value binding named
`bind` inside a module binding named `Result`, or at the root of a
unit itself named `Result`; every other definition, `( let* )`
included, keeps firing. No fix: the rewrite restructures the `Ok` arm
into a lambda — the message shows the form.|}
    ()

let message =
  "manual match re-implements Result.bind — use Result.bind r (fun x -> …)"

(* The two case orders capture the arms' roles at different positions, so
   each order is its own pattern and the continuations restore one role
   order: Ok RHS, Error payload pattern, Error ident, rebuilt payload
   expression, rebuilt payload path. *)
let ok_first =
  Pat.(
    match_ drop
      (case (pvalue (pok pvar)) none __
      ^:: case (pvalue (perror (as__ pvar))) none (eerror (as__ var))
      ^:: nil))

let error_first =
  Pat.(
    match_ drop
      (case (pvalue (perror (as__ pvar))) none (eerror (as__ var))
      ^:: case (pvalue (pok pvar)) none __
      ^:: nil))

(* The function forms additionally capture their first case's pattern:
   merged [let f x = function ...] sugar leaves the function expression
   ghost, and the finding then anchors at the first case's pattern. *)
let fn_ok_first =
  Pat.(
    fun_cases nil
      (case (as__ (pok pvar)) none __
      ^:: case (perror (as__ pvar)) none (eerror (as__ var))
      ^:: nil))

let fn_error_first =
  Pat.(
    fun_cases nil
      (case (as__ (perror (as__ pvar))) none (eerror (as__ var))
      ^:: case (pok pvar) none __
      ^:: nil))

let ok_construction = Pat.(eok drop)

(* The rebuild's typing side condition: the pattern-bound payload's type
   and the rebuilt payload's type must be equal — the reuse of the one
   binder makes unification force it for the plain rebuild, and a
   coercion in the rebuild ([Error (e :> wider)]) is exactly what this
   refuses: there [Result.bind] would not typecheck. Conservative
   structural equality — node identity, or equal heads over equal
   arguments. A [Tvar] on either side accepts: pattern types are
   recorded before later arms constrain them, so an unlinked variable
   means "unconstrained at record time" — unification made it equal by
   construction, while the coercion exclusion needs both sides concrete
   (the scrutinee's written variant against the coercion target).
   Distinct concrete polymorphic-variant nodes refuse (a false
   negative, the safe direction). *)
let rec same_type a b =
  Types.eq_type a b
  ||
  match (Types.get_desc a, Types.get_desc b) with
  | Types.Tvar _, _ | _, Types.Tvar _ -> true
  | Types.Tconstr (p, args, _), Types.Tconstr (q, brgs, _) ->
      Path.same p q
      && List.length args = List.length brgs
      && List.for_all2 same_type args brgs
  | _ -> false

let bind_shape u ~ok_rhs ~er_pat ~er ~rebuilt ~rebuilt_path =
  Path.same rebuilt_path (Path.Pident er)
  && Pat.run ok_construction u ok_rhs () = None
  && same_type er_pat.Typedtree.pat_type rebuilt.Typedtree.exp_type

(* The self-definition gate: a module named [Result] defining the
   like-named [bind]
   from exactly this match — stdppx's shape — must not be told to use
   [Result.bind]. [self_definition u e] holds when [e] is the eventual
   function body ([Texp_function] spines stripped) of a value binding
   named [bind] whose group sits in the body of a module binding named
   [Result], or at the root of a unit itself named [Result] (the
   vendored-compat spelling). Runs only on hits (the cheap shape
   gates come first), matches [e] by node identity against the engine's
   own traversal tree, and reads only the mid-window-stable typedtree
   fields (the [module_binding] record is never rebuilt or exhaustively
   matched here). Expression-level module bindings are out of its walk —
   a recorded non-goal, matching the sibling rules' item-spine scope. *)
let self_definition u (e : Typedtree.expression) =
  let rec strips_to (x : Typedtree.expression) =
    x == e
    ||
    match x.Typedtree.exp_desc with
    | Typedtree.Texp_function (_, Typedtree.Tfunction_body b) -> strips_to b
    | _ -> false
  in
  let binds_e (vb : Typedtree.value_binding) =
    (match Pat.bound_var vb.Typedtree.vb_pat with
      | Some (name, _) -> String.equal name.Location.txt "bind"
      | None -> false)
    && strips_to vb.Typedtree.vb_expr
  in
  let rec in_structure ~named_result (str : Typedtree.structure) =
    List.exists (in_item ~named_result) str.Typedtree.str_items
  and in_item ~named_result (it : Typedtree.structure_item) =
    match it.Typedtree.str_desc with
    | Typedtree.Tstr_value (_, vbs) -> named_result && List.exists binds_e vbs
    | Typedtree.Tstr_module mb -> in_module_binding mb
    | Typedtree.Tstr_recmodule mbs -> List.exists in_module_binding mbs
    | _ -> false
  and in_module_binding (mb : Typedtree.module_binding) =
    let named_result =
      match mb.Typedtree.mb_name.Location.txt with
      | Some n -> String.equal n "Result"
      | None -> false
    in
    in_module_expr ~named_result mb.Typedtree.mb_expr
  and in_module_expr ~named_result (me : Typedtree.module_expr) =
    match me.Typedtree.mod_desc with
    | Typedtree.Tmod_structure str -> in_structure ~named_result str
    | Typedtree.Tmod_constraint (me', _, _, _) ->
        in_module_expr ~named_result me'
    | _ -> false
  in
  in_structure
    ~named_result:(String.equal (Unit.name u) "Result")
    (Unit.implementation u)

let rule =
  Rule.expr meta @@ fun u e ->
  (* Constructor-head gate: only the two host forms can match — the
     walk visits every node, so the miss path must stay cheap. *)
  match e.exp_desc with
  | Typedtree.Texp_match _ -> (
      let hit =
        match
          Pat.run ok_first u e (fun _x ok_rhs er_pat er rebuilt p ->
              (ok_rhs, er_pat, er, rebuilt, p))
        with
        | Some _ as h -> h
        | None ->
            Pat.run error_first u e (fun er_pat er rebuilt p _x ok_rhs ->
                (ok_rhs, er_pat, er, rebuilt, p))
      in
      match hit with
      | Some (ok_rhs, er_pat, er, rebuilt, rebuilt_path)
        when bind_shape u ~ok_rhs ~er_pat ~er ~rebuilt ~rebuilt_path
             && not (self_definition u e) ->
          [ Finding.v ~loc:e.exp_loc message ]
      | Some _ | None -> [])
  | Typedtree.Texp_function _ -> (
      let hit =
        match
          Pat.run fn_ok_first u e (fun first _x ok_rhs er_pat er rebuilt p ->
              (first, ok_rhs, er_pat, er, rebuilt, p))
        with
        | Some _ as h -> h
        | None ->
            Pat.run fn_error_first u e
              (fun first er_pat er rebuilt p _x ok_rhs ->
                (first, ok_rhs, er_pat, er, rebuilt, p))
      in
      match hit with
      | Some ((first : Typedtree.pattern), ok_rhs, er_pat, er, rebuilt, p)
        when bind_shape u ~ok_rhs ~er_pat ~er ~rebuilt ~rebuilt_path:p
             && not (self_definition u e) ->
          let loc =
            if e.exp_loc.Location.loc_ghost then first.pat_loc else e.exp_loc
          in
          [ Finding.v ~loc message ]
      | Some _ | None -> [])
  | _ -> []
