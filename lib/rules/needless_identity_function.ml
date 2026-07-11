(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"needless-identity-function" ~group:Rule.Style
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"function that only forwards its arguments"
    ~doc:
      {|A wrapper `fun x -> f x` (or `fun x y -> f x y`) passed inline to
another function is the function it wraps, written longer: every
argument is passed through unchanged, in order, to a callee that does
not depend on the parameters.

    (* bad *)  List.map (fun x -> succ x) xs
    (* good *) List.map succ xs

Fires on an inline `fun` in argument position — an argument of a full,
unlabeled application — of any arity, whose parameters are distinct
plain unlabeled variables and whose body applies an independent
identifier to exactly those parameters, by declaration identity, once
each in order without labels — including a partial forward like
`fun x -> add x`. Anchored at the wrapper itself, one finding per
forwarding argument.

Named `let` bindings deliberately do not fire: a named forwarder is
usually the point (a
seam's name, a re-export, deliberate eta for weak polymorphism or
monomorphization), and on real code the named sites were
wrapper-by-design almost without exception, while the doc's own bad
example has always been the inline one. The `let g x = f x` sugar rides
with them, and arguments of labeled applications sit outside the
unlabeled argument view. Reordered, duplicated, missing, extra, or
labeled arguments, labeled or optional or non-variable parameters, a
callee bound by a parameter, shadowed same-spelling variables, curried
multi-stage wrappers, and `function` bodies deliberately do not fire
either. No fix: removing the wrapper changes closure allocation and can
make physical identity observable.|}
    ()

let forward = Pat.(apply __ __)

(* The parameters as declaration identities, when every one is a plain
   unlabeled variable and no identity repeats. Same-spelling shadowed
   variables are distinct identities and compare unequal. *)
let plain_params params =
  let param seen (p : Typedtree.function_param) =
    match (p.fp_arg_label, p.fp_kind) with
    | Asttypes.Nolabel, Typedtree.Tparam_pat pat -> (
        match pat.pat_desc with
        | Typedtree.Tpat_var (id, _, _) ->
            let pid = Path.Pident id in
            if List.exists (Path.same pid) seen then None else Some pid
        | _ -> None)
    | _ -> None
  in
  let rec go seen = function
    | [] -> Some (List.rev seen)
    | p :: rest -> (
        match param seen p with
        | Some pid -> go (pid :: seen) rest
        | None -> None)
  in
  match params with [] -> None | _ :: _ -> go [] params

let ident_path (e : Typedtree.expression) =
  match e.exp_desc with Typedtree.Texp_ident (p, _, _) -> Some p | _ -> None

(* [forwards params callee args]: [callee] is an identifier independent of
   [params] and [args] are exactly [params], by identity, in order. *)
let forwards params callee args =
  match ident_path callee with
  | Some c when not (List.exists (Path.same c) params) ->
      List.compare_lengths params args = 0
      && List.for_all2
           (fun p a ->
             match ident_path a with Some q -> Path.same p q | None -> false)
           params args
  | Some _ | None -> false

(* [forwarder u arg] is [true] when [arg] is a `fun` whose whole body
   forwards its parameters to an independent callee — the wrapper the
   rule reports when it sits in argument position. *)
let forwarder u (arg : Typedtree.expression) =
  match arg.exp_desc with
  | Typedtree.Texp_function (params, Typedtree.Tfunction_body body) -> (
      match plain_params params with
      | Some ps ->
          Pat.run forward u body (fun f args -> forwards ps f args) = Some true
      | None -> false)
  | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  (* Dispatch at the application, not the function: argument position is
     the parent's property, and the engine's traversal carries no
     parent. The wrapper's own visit matches nothing, so nothing
     double-reports. *)
  match Pat.run Pat.(apply drop __) u e Fun.id with
  | None -> []
  | Some args ->
      List.filter_map
        (fun (arg : Typedtree.expression) ->
          if forwarder u arg then
            Some
              (Finding.v ~loc:arg.exp_loc
                 "function only forwards its arguments to another function")
          else None)
        args
