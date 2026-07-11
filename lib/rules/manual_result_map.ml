(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-result-map" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:
      "two-case match that transforms one result arm and rebuilds the other"
    ~doc:
      {|`match r with Ok x -> Ok E | Error e -> Error e` is `Result.map
(fun x -> E) r`: the error arm provably rebuilds the same payload, so
the rewrite is exact. The mirrored shape — identity `Ok` arm,
transforming `Error` arm — is `Result.map_error` and is matched too,
with its own message.

    (* bad *)  match r with Ok x -> Ok (parse x) | Error e -> Error e
    (* good *) Result.map (fun x -> parse x) r

Fires on exactly two guard-less cases — `Ok` and `Error` with
bare-variable payloads, in either order, identified by the constructors'
result-type head being the global `Stdlib.result` path — in both the
`match` and the `function` form, when exactly one arm transforms and the
other is an identity rebuild; when both arms are identity rebuilds the
match is the scrutinee itself and says so. Guards, deeper payload
patterns, wildcard payloads, arms that do not rebuild their constructor
(`Result.bind` territory), both arms transforming, and user variants
spelling `Ok`/`Error` deliberately do not fire. The fix rewrites the
match form to `Result.map (fun x -> E) r` / `Result.map_error (fun e ->
E) r` (the scrutinee alone for the double identity) where the sources
slice cleanly; the `function` form has no scrutinee to name and ships
none.|}
    ()

let map_message =
  "this match transforms the payload and rebuilds the error; use Result.map"

let map_error_message =
  "this match transforms the error and rebuilds the payload; use \
   Result.map_error"

let identity_message =
  "this match rebuilds the result unchanged; it is the scrutinee itself"

(* The two case orders capture the arms' roles at different positions, so
   each order is its own pattern and the continuations restore one role
   order: scrutinee, Ok payload pattern/ident/rebuild, Error payload
   pattern/ident/rebuild. The payload patterns ride along for their
   source names ([bound_var]). *)
let ok_first =
  Pat.(
    match_ __
      (case (pvalue (pok (as__ pvar))) none (eok __)
      ^:: case (pvalue (perror (as__ pvar))) none (eerror __)
      ^:: nil))

let error_first =
  Pat.(
    match_ __
      (case (pvalue (perror (as__ pvar))) none (eerror __)
      ^:: case (pvalue (pok (as__ pvar))) none (eok __)
      ^:: nil))

(* The function forms additionally capture their first case's pattern:
   merged [let f x = function ...] sugar leaves the function expression
   ghost, and the finding then anchors at the first case's pattern. *)
let fn_ok_first =
  Pat.(
    fun_cases drop
      (case (as__ (pok (as__ pvar))) none (eok __)
      ^:: case (perror (as__ pvar)) none (eerror __)
      ^:: nil))

let fn_error_first =
  Pat.(
    fun_cases drop
      (case (as__ (perror (as__ pvar))) none (eerror __)
      ^:: case (pok (as__ pvar)) none (eok __)
      ^:: nil))

let is_var u x ee =
  match Pat.run Pat.var u ee Fun.id with
  | Some p -> Path.same p (Path.Pident x)
  | None -> false

(* One arm's lambda rewrite. The body is spliced raw ([Unit.text]): a
   lambda body is terminal, so it needs no delimiting, and wrapping it
   would only add noise — or a second pair around a body the author
   already parenthesized. The scrutinee is an operand and keeps
   [Unit.splice]. *)
let lambda_fix u (m : Typedtree.expression) ~fn ~pat ~ee ~scrut =
  match (Pat.bound_var pat, Unit.text u ee, Unit.splice u scrut) with
  | Some (name, _), Some body, Some r ->
      Some
        (Fix.safe_replace m.exp_loc
           (Unit.delimited u m
              (String.concat ""
                 [ fn; " (fun "; name.Location.txt; " -> "; body; ") "; r ]))
           ~title:("rewrite with " ^ fn))
  | _ -> None

(* [matched] is the match expression and its scrutinee in the match form;
   the function form has neither, and ships no fix. *)
let findings u ~loc ~matched ~ok_pat ~x ~e_ok ~err_pat ~er ~e_err =
  match (is_var u x e_ok, is_var u er e_err) with
  | true, true ->
      let fix =
        Option.bind matched (fun (m, s) ->
            Option.map
              (fun r ->
                Fix.safe_replace m.Typedtree.exp_loc r
                  ~title:"use the scrutinee")
              (Unit.splice u s))
      in
      [ Finding.v ?fix ~loc identity_message ]
  | false, true ->
      let fix =
        Option.bind matched (fun (m, s) ->
            lambda_fix u m ~fn:"Result.map" ~pat:ok_pat ~ee:e_ok ~scrut:s)
      in
      [ Finding.v ?fix ~loc map_message ]
  | true, false ->
      let fix =
        Option.bind matched (fun (m, s) ->
            lambda_fix u m ~fn:"Result.map_error" ~pat:err_pat ~ee:e_err
              ~scrut:s)
      in
      [ Finding.v ?fix ~loc map_error_message ]
  | false, false -> []

let rule =
  Rule.expr meta @@ fun u e ->
  let match_hit =
    match
      Pat.run ok_first u e (fun s op x eo ep er ee ->
          (s, op, x, eo, ep, er, ee))
    with
    | Some _ as h -> h
    | None ->
        Pat.run error_first u e (fun s ep er ee op x eo ->
            (s, op, x, eo, ep, er, ee))
  in
  match match_hit with
  | Some (scrut, ok_pat, x, e_ok, err_pat, er, e_err) ->
      findings u ~loc:e.exp_loc
        ~matched:(Some (e, scrut))
        ~ok_pat ~x ~e_ok ~err_pat ~er ~e_err
  | None -> (
      let fn_hit =
        match
          Pat.run fn_ok_first u e (fun f op x eo ep er ee ->
              (f, op, x, eo, ep, er, ee))
        with
        | Some _ as h -> h
        | None ->
            Pat.run fn_error_first u e (fun f ep er ee op x eo ->
                (f, op, x, eo, ep, er, ee))
      in
      match fn_hit with
      | Some ((first : Typedtree.pattern), ok_pat, x, e_ok, err_pat, er, e_err)
        ->
          let loc =
            if e.exp_loc.Location.loc_ghost then first.pat_loc else e.exp_loc
          in
          findings u ~loc ~matched:None ~ok_pat ~x ~e_ok ~err_pat ~er ~e_err
      | None -> [])
