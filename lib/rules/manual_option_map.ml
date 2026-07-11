(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-option-map" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"two-case match that unwraps, transforms, and rewraps an option"
    ~doc:
      {|`match o with Some x -> Some E | None -> None` is `Option.map
(fun x -> E) o` written longhand: both forms evaluate the scrutinee once
and `E` only in the `Some` case, so the rewrite is exact.

    (* bad *)  match o with Some x -> Some (x + 1) | None -> None
    (* good *) Option.map (fun x -> x + 1) o

Fires on exactly two guard-less cases — `Some` with a bare-variable
payload rebuilding `Some`, and `None` rebuilding `None`, in either
order, by predefined-constructor identity — in both the `match` and the
`function` form. The degenerate rebuild `Some x -> Some x` is the
scrutinee itself and gets its own message. Guards, wildcard arms, deeper
payload patterns, aliases, `exception` arms, user-defined `Some`/`None`
constructors, and `Some` arms that do not rebuild `Some` (`Option.bind`
territory) deliberately do not fire. The fix rewrites the match form to
`Option.map (fun x -> E) o` — the tighter `Option.map f o` when `E` is
exactly `f x` for an identifier `f` other than `x`, and the scrutinee
alone for the degenerate rebuild — where the sources slice cleanly; the
`function` form has no scrutinee to name and ships none.|}
    ()

let map_message =
  "this match unwraps, transforms, and rewraps the option; use Option.map"

let identity_message =
  "this match rebuilds the option unchanged; it is the scrutinee itself"

(* Both case orders capture in the same role order — payload pattern,
   payload ident, rebuilt expression — so one alternation serves each
   form. The payload pattern rides along for its source name
   ([bound_var]); the [match_]/[fun_cases] views refuse effect-carrying
   matches, guards refuse via [none], and aliased or deeper payloads
   refuse by the view contracts. *)
let match_form =
  Pat.(
    match_ __
      (case (pvalue (psome (as__ pvar))) none (esome __)
       ^:: case (pvalue pnone) none enone
       ^:: nil
      ||| case (pvalue pnone) none enone
          ^:: case (pvalue (psome (as__ pvar))) none (esome __)
          ^:: nil))

(* The function form captures its first case's pattern: when the merged
   `let f x = function …` sugar leaves the function expression ghost, the
   finding anchors there instead. *)
let function_form =
  Pat.(
    fun_cases drop
      (case (as__ (psome pvar)) none (esome __)
       ^:: case pnone none enone ^:: nil
      ||| case (as__ pnone) none enone
          ^:: case (psome pvar) none (esome __)
          ^:: nil))

(* [E] is the bound variable itself: the identity rebuild. *)
let is_var u x ee =
  match Pat.run Pat.var u ee Fun.id with
  | Some p -> Path.same p (Path.Pident x)
  | None -> false

(* [E] is exactly [f x] for an identifier [f] other than [x] itself: the
   tighter [Option.map f o] rewrite ([f] is a bare identifier, so the
   only way it could use [x] is being [x]). *)
let tight_shape = Pat.(apply (as__ var) (var ^:: nil))

let tight u x ee =
  match Pat.run tight_shape u ee (fun fe fp ap -> (fe, fp, ap)) with
  | Some (fe, fp, ap)
    when Path.same ap (Path.Pident x) && not (Path.same fp (Path.Pident x)) ->
      Unit.splice u fe
  | _ -> None

let build_fix u (e : Typedtree.expression) ~scrut ~pat ~x ~ee ~identity =
  let loc = e.exp_loc in
  match Unit.splice u scrut with
  | None -> None
  | Some o ->
      if identity then Some (Fix.safe_replace loc o ~title:"use the scrutinee")
      else
        let rewrite =
          match tight u x ee with
          | Some f -> Some (String.concat "" [ "Option.map "; f; " "; o ])
          | None -> (
              match (Pat.bound_var pat, Unit.splice u ee) with
              | Some (name, _), Some body ->
                  Some
                    (String.concat ""
                       [
                         "Option.map (fun ";
                         name.Location.txt;
                         " -> ";
                         body;
                         ") ";
                         o;
                       ])
              | _ -> None)
        in
        Option.map
          (fun text ->
            Fix.safe_replace loc (Unit.delimited u e text)
              ~title:"rewrite with Option.map")
          rewrite

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run match_form u e (fun s p x ee -> (s, p, x, ee)) with
  | Some (scrut, pat, x, ee) ->
      let identity = is_var u x ee in
      let message = if identity then identity_message else map_message in
      let fix = build_fix u e ~scrut ~pat ~x ~ee ~identity in
      [ Finding.v ?fix ~loc:e.exp_loc message ]
  | None -> (
      match Pat.run function_form u e (fun p x ee -> (p, x, ee)) with
      | Some ((first : Typedtree.pattern), x, ee) ->
          let message =
            if is_var u x ee then identity_message else map_message
          in
          let loc =
            if e.exp_loc.Location.loc_ghost then first.pat_loc else e.exp_loc
          in
          [ Finding.v ~loc message ]
      | None -> [])
