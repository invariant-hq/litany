(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-swallowed-cancellation" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Sometimes
    ~summary:"total handler around eio code converts cancellation into a value"
    ~doc:
      {|Eio delivers fiber cancellation as the `Eio.Cancel.Cancelled`
exception out of any suspending operation, and a handler must let it
through, or the fiber keeps running with a corrupted notion of what
happened: cancellations get recorded as data errors, cleanup runs
twice, supervisors log garbage.

    (* bad *)  try Ok (Eio.Path.read_dir dir) with exn -> Error exn
    (* good *) try Ok (Eio.Path.read_dir dir) with
               | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
               | exn -> Error exn

Fires on a `try` handler or the `exception` cases of a `match` where a
guard-less total arm — a bare variable or wildcard — converts to a
value (a wrap-raise like `raise (Wrapped e)` still converts
cancellation and counts; a plain re-raise of the binder, or
`Printexc.raise_with_backtrace`, does not), no sibling arm passes the
exception through (an alias arm re-raising its own binder,
`| Eio.Cancel.Cancelled _ as e -> raise e` — the discipline real Eio
code practices), and the guarded region applies at least one function
declared in an `Eio`-family compilation unit (`Eio`, `Eio_unix`,
`Eio_main`, `Eio_posix`) — total handlers around pure code stay silent.
The pass-through condition is meant to be `Eio.Cancel.Cancelled`
constructor identity by UID; pattern-side exception-constructor
identity has not landed, so the alias-re-raise shape stands in — a bare
`Eio.Cancel.Cancelled _` sibling arm does not yet silence (a recorded
gap), and a sibling alias arm re-raising a non-Cancelled exception
silences (recorded false negative). Handlers inside
`Eio.Cancel.protect` and deliberate supervisor recorders are
`[@litany.allow]` cases. The fix inserts the guard arm on its own line
before the total one, and only when that arm sits on its own
`| `-prefixed line; it changes behavior — that is its point — so it
applies only under `--fix --unsafe`.|}
    ()

let message =
  "this handler converts Eio cancellation into a value; re-raise \
   Eio.Cancel.Cancelled first"

(* Hosts. *)
let try_shape = Pat.(try_ __ __)
let match_shape = Pat.(match_ __ __)

(* Total arms, guard-less: bare variable or wildcard. The alias-of-one
   spelling ([_ as e]) needs a pattern-alias view and is a recorded
   false negative. *)
let total_var = Pat.(case (as__ pvar) none __)
let total_any = Pat.(case (as__ pany) none __)
let m_total_var = Pat.(case (as__ (pexception (as__ pvar))) none __)
let m_total_any = Pat.(case (as__ (pexception (as__ pany))) none __)

(* Re-raises of a binder. *)
let reraise = Pat.(apply (ident "Stdlib.raise") (as__ var ^:: nil))

let reraise_bt =
  Pat.(
    apply
      (ident "Stdlib.Printexc.raise_with_backtrace")
      (as__ var ^:: drop ^:: nil))

(* Any case, pattern and right-hand side surfaced, guard ignored — the
   sibling pass-through scan. *)
let any_case = Pat.(case (as__ drop) drop __)
let m_any_case = Pat.(case (pexception (as__ drop)) drop __)

(* Application heads declared in an Eio-family compilation unit. *)
let eio_heads =
  Pat.(
    from_unit "Eio" ||| from_unit "Eio_unix" ||| from_unit "Eio_main"
    ||| from_unit "Eio_posix")

let reraise_paths u rhs =
  match Pat.run reraise u rhs (fun arg p -> (arg, p)) with
  | Some _ as hit -> hit
  | None -> Pat.run reraise_bt u rhs (fun arg p -> (arg, p))

(* The total arm's own re-raise exclusion: [| exception exn -> raise exn]
   converts nothing. *)
let reraises_binder u binder rhs =
  match reraise_paths u rhs with
  | Some (_, p) -> Path.same p (Path.Pident binder)
  | None -> false

(* A sibling arm that passes the exception through: an alias pattern
   ([bound_var] answers, a bare variable does not) whose right-hand side
   re-raises its own binder — the binder join is the bound declaration
   UID against the unit's use index. *)
let passes_through u (pat : Typedtree.pattern) rhs =
  match Pat.bound_var pat with
  | Some (_, uid) when Pat.run Pat.pvar u pat (fun _ -> ()) = None -> (
      match reraise_paths u rhs with
      | Some (arg, Path.Pident _) ->
          List.exists
            (fun (l : Location.t) -> l = arg.Typedtree.exp_loc)
            (Unit.uses u uid)
      | Some _ | None -> false)
  | Some _ | None -> false

(* The eio-bearing region test: some application in the subtree has a
   head declared in an Eio-family unit — a bounded sub-walk, run last:
   the cheap structural gates come first. *)
let eio_bearing u (region : Typedtree.expression) =
  let found = ref false in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.expr =
        (fun sub (x : Typedtree.expression) ->
          (match x.exp_desc with
          | Typedtree.Texp_apply (head, _)
            when Pat.run eio_heads u head () <> None ->
              found := true
          | _ -> ());
          if not !found then default.expr sub x);
    }
  in
  iterator.expr iterator region;
  !found

(* The guard arm, inserted as a new line before the total arm — the
   plain-arm-list condition read mechanically: the fix applies
   only when the total arm sits on its own [| ]-prefixed line, so the
   inserted arm reproduces the surrounding layout byte-exactly (the
   compiled golden pins it). *)
let guard_fix u ~match_form ~outer_loc =
  if Unit.preprocessed u || outer_loc.Location.loc_ghost then None
  else
    let start = outer_loc.Location.loc_start.Lexing.pos_cnum
    and bol = outer_loc.Location.loc_start.Lexing.pos_bol
    and stop = outer_loc.Location.loc_end.Lexing.pos_cnum in
    if bol < 0 || start < bol + 2 || stop < start then None
    else
      let contents = Source.contents (Unit.source u) in
      if stop > String.length contents then None
      else
        let prefix = String.sub contents bol (start - bol) in
        let cut = String.length prefix - 2 in
        let indent = String.sub prefix 0 cut in
        if
          not
            (String.equal (String.sub prefix cut 2) "| "
            && String.for_all (fun c -> c = ' ') indent)
        then None
        else
          match Source.slice (Unit.source u) (Span.of_location outer_loc) with
          | None -> None
          | Some original ->
              let arm =
                if match_form then
                  "exception (Eio.Cancel.Cancelled _ as cancelled) -> raise \
                   cancelled"
                else "Eio.Cancel.Cancelled _ as cancelled -> raise cancelled"
              in
              Some
                (Fix.unsafe_replace outer_loc
                   (String.concat "" [ arm; "\n"; indent; "| "; original ])
                   ~title:"re-raise Eio.Cancel.Cancelled before the total arm")

(* One handler analysis. [total c] surfaces the total arm — outer span
   for the fix, anchor pattern, optional binder, right-hand side;
   [sibling c] surfaces every arm's pattern and right-hand side. *)
let analyze u ~match_form ~region ~cases ~total ~sibling =
  let candidate =
    List.find_map
      (fun c ->
        match total c with
        | Some (outer_loc, anchor, binder, rhs) ->
            let converts =
              match binder with
              | Some b -> not (reraises_binder u b rhs)
              | None -> true
            in
            if converts then Some (outer_loc, anchor, rhs) else None
        | None -> None)
      cases
  in
  match candidate with
  | None -> []
  | Some (outer_loc, (anchor : Typedtree.pattern), total_rhs) ->
      let guarded =
        List.exists
          (fun c ->
            match sibling c with
            | Some (pat, rhs) ->
                (not (rhs == total_rhs)) && passes_through u pat rhs
            | None -> false)
          cases
      in
      if guarded || not (eio_bearing u region) then []
      else
        let fix = guard_fix u ~match_form ~outer_loc in
        [ Finding.v ?fix ~loc:anchor.pat_loc message ]

let rule =
  Rule.expr meta @@ fun u e ->
  (* Constructor-head gate: only the two host forms can match — the
     walk visits every node, so the miss path must stay cheap. *)
  match e.exp_desc with
  | Typedtree.Texp_try _ -> (
      match Pat.run try_shape u e (fun body cases -> (body, cases)) with
      | Some (body, cases) ->
          let total c =
            match
              Pat.run total_var u c (fun pat b rhs -> (pat, Some b, rhs))
            with
            | Some ((pat : Typedtree.pattern), b, rhs) ->
                Some (pat.pat_loc, pat, b, rhs)
            | None -> (
                match Pat.run total_any u c (fun pat rhs -> (pat, rhs)) with
                | Some ((pat : Typedtree.pattern), rhs) ->
                    Some (pat.pat_loc, pat, None, rhs)
                | None -> None)
          and sibling c = Pat.run any_case u c (fun pat rhs -> (pat, rhs)) in
          analyze u ~match_form:false ~region:body ~cases ~total ~sibling
      | None -> [])
  | Typedtree.Texp_match _ -> (
      match Pat.run match_shape u e (fun scrut cases -> (scrut, cases)) with
      | Some (scrut, cases) ->
          let total c =
            match
              Pat.run m_total_var u c (fun outer pat b rhs ->
                  (outer, pat, Some b, rhs))
            with
            | Some (outer, (pat : Typedtree.pattern), b, rhs) ->
                Some (outer.Typedtree.pat_loc, pat, b, rhs)
            | None -> (
                match
                  Pat.run m_total_any u c (fun outer pat rhs ->
                      (outer, pat, rhs))
                with
                | Some (outer, (pat : Typedtree.pattern), rhs) ->
                    Some (outer.Typedtree.pat_loc, pat, None, rhs)
                | None -> None)
          and sibling c = Pat.run m_any_case u c (fun pat rhs -> (pat, rhs)) in
          analyze u ~match_form:true ~region:scrut ~cases ~total ~sibling
      | None -> [])
  | _ -> []
