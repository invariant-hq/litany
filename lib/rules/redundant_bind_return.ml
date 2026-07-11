(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-bind-return" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"bind into a bare return re-wraps the value unchanged"
    ~doc:
      {|Binding a computation into its monad's own `return` is the right
identity law: every value is re-wrapped exactly as it arrived, so the
whole expression is the computation it started from.

    (* bad *)  Option.bind o Option.some
    (* good *) o

Fires when a known-lawful pair resolves by declaration: `Option.bind`
with `Option.some`, `Result.bind` with `Result.ok`, or `Lwt.bind` /
`Lwt.Infix.(>>=)` with `Lwt.return` — the return passed as the bare
callback, or as a lambda returning exactly the bound value
(`fun x -> Some x`, `function x -> Ok x`, `fun x -> Lwt.return x`;
constructor and function returns alike, by declaration or
predefined-constructor identity). A project's own `bind` and `return`
never fire, lawful or not: each listed pair is an audited lawfulness
claim, and other identities match nothing. `let*` syntax, guarded or
multi-case `function` callbacks, and callbacks returning anything but
the bound value deliberately do not fire. No automatic fix in this
release — the promise flips to `Sometimes` when the rewrite to the
bound computation lands.|}
    ()

let pair bind returns =
  Pat.(apply (ident bind) (drop ^:: idents returns ^:: nil))

(* The eta-reduced form: the return function itself as the callback. *)
let bind_return =
  Pat.(
    pair "Stdlib.Option.bind" [ "Stdlib.Option.some" ]
    ||| pair "Stdlib.Result.bind" [ "Stdlib.Result.ok" ]
    ||| pair "Lwt.bind" [ "Lwt.return" ]
    ||| pair "Lwt.Infix.(>>=)" [ "Lwt.return" ])

(* The lambda forms: [fun y -> RET y] and the
   one-case guard-less [function y -> RET y], where RET is the pair's
   return function or its constructor form ([Some]/[Ok], by
   predefined/global constructor identity). The pattern captures the
   parameter's ident and the returned variable's path; the callback
   joins them by identity ([Path.same] against the parameter's
   ident) — a different variable refuses there. *)
let ret_of returns wrap =
  let app = Pat.(apply (idents returns) (var ^:: nil)) in
  match wrap with Some w -> Pat.(app ||| w var) | None -> app

let lambda body =
  Pat.(
    fun_body (param pvar ^:: nil) body
    ||| fun_cases nil (case pvar none body ^:: nil))

let pair_lambda bind returns wrap =
  Pat.(apply (ident bind) (drop ^:: lambda (ret_of returns wrap) ^:: nil))

let bind_lambda =
  Pat.(
    pair_lambda "Stdlib.Option.bind" [ "Stdlib.Option.some" ] (Some esome)
    ||| pair_lambda "Stdlib.Result.bind" [ "Stdlib.Result.ok" ] (Some eok)
    ||| pair_lambda "Lwt.bind" [ "Lwt.return" ] None
    ||| pair_lambda "Lwt.Infix.(>>=)" [ "Lwt.return" ] None)

let rule =
  Rule.expr meta @@ fun u e ->
  let hit =
    match Pat.run bind_return u e () with
    | Some () -> true
    | None -> (
        match Pat.run bind_lambda u e (fun y p -> (y, p)) with
        | Some (y, p) -> Path.same p (Path.Pident y)
        | None -> false)
  in
  if hit then
    [
      Finding.v ~loc:e.exp_loc
        "binding into a bare return re-wraps the value; use the computation \
         directly";
    ]
  else []
